-- Lot 3 bis : résumé du mois en cours, aperçu = résultat réel de close_month.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- Crée l'utilisateur n (courant de départ, octobre en cours, dépenses
-- d'octobre) et agit en son nom.
create function pg_temp.setup(p_n int, p_courant numeric, p_expenses numeric) returns uuid
language plpgsql as $$
declare
  v_id uuid := ('40000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email) values (v_id, 's' || p_n || '@test.local');
  update public.accounts set balance = p_courant where user_id = v_id and type = 'courant';
  insert into public.monthly_settlements (user_id, month, salary, shared_transfer)
  values (v_id, '2026-10-01', 2500, 600);
  insert into public.transactions (user_id, type, amount, category, date)
  values (v_id, 'depense', p_expenses, 'Courses', '2026-10-10');
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
  return v_id;
end;
$$;

-- Ne garde que les montants, pour comparer aperçu et résultat.
create function pg_temp.amounts(p jsonb) returns text language sql as $$
  select format('%s|%s|%s',
    (p ->> 'total_expenses')::numeric(12,2),
    (p ->> 'total_savings')::numeric(12,2),
    (p ->> 'courant')::numeric(12,2))
$$;

-- Résumé ----------------------------------------------------------------------
select pg_temp.setup(1, 350, 1000);
insert into public.transactions (user_id, type, amount, category, date) values
  ('40000000-0000-0000-0000-000000000001', 'depense', 450, 'Courses', '2026-10-12'),
  ('40000000-0000-0000-0000-000000000001', 'revenu', 50, 'Courses', '2026-10-13'),
  ('40000000-0000-0000-0000-000000000001', 'depense', 80, 'Courses', '2026-11-02');

set local role authenticated;
select is(
  (select (month, courant, unsettled_expenses, available)::text from public.current_month_summary),
  '(2026-10-01,350.00,1400.00,-1050.00)',
  'résumé : disponible estimé = courant − (dépenses − revenus) non réglées, mois suivant exclu');
select is(
  (select (suggested_salary, suggested_shared_transfer)::text from public.current_month_summary),
  '(2500.00,600.00)', 'résumé : valeurs du mois en cours proposées');

-- Aperçu = clôture réelle ----------------------------------------------------
select set_config('test.preview', public.preview_close_month(2500, 600)::text, true);
select is(pg_temp.amounts(current_setting('test.preview')::jsonb), '1400.00|650.00|200.00',
  'aperçu §3 : épargne 650, courant 200');
select is(
  pg_temp.amounts(public.close_month('2026-10-01', 2500, 600)),
  pg_temp.amounts(current_setting('test.preview')::jsonb),
  'aperçu §3 = résultat de close_month');
select is(
  (select (month, unsettled_expenses)::text from public.current_month_summary),
  '(2026-11-01,80.00)', 'après clôture : novembre en cours avec ses dépenses');

reset role;
select pg_temp.setup(2, 100, 2300);
set local role authenticated;
select set_config('test.preview', public.preview_close_month(2500, 600)::text, true);
select is(pg_temp.amounts(current_setting('test.preview')::jsonb), '2300.00|0.00|-300.00',
  'aperçu négatif : courant −300');
select is(
  pg_temp.amounts(public.close_month('2026-10-01', 2500, 600)),
  pg_temp.amounts(current_setting('test.preview')::jsonb),
  'aperçu négatif = résultat de close_month');

reset role;
select pg_temp.setup(3, 350, 1400);
set local role authenticated;
select set_config('test.preview', public.preview_close_month(2500, 600, true)::text, true);
select is(pg_temp.amounts(current_setting('test.preview')::jsonb), '1400.00|0.00|850.00',
  'aperçu mois particulier : pas d''épargne');
select is(
  pg_temp.amounts(public.close_month('2026-10-01', 2500, 600, true)),
  pg_temp.amounts(current_setting('test.preview')::jsonb),
  'aperçu mois particulier = résultat de close_month');

-- Onboarding : rien à proposer, settings par défaut à 0 ----------------------
reset role;
insert into auth.users (id, email) values ('40000000-0000-0000-0000-000000000009', 'new@test.local');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000009","role":"authenticated"}', true);
select throws_ok($$select public.preview_close_month(2500, 600)$$, 'FF001', null,
  'aperçu sans mois en cours : refusé');
select public.complete_onboarding(200);
select is(
  (select (courant, available, suggested_salary)::text from public.current_month_summary),
  '(200.00,200.00,0.00)', 'après onboarding : salaire à saisir');
select is((select count(*)::int from public.current_month_summary), 1,
  'résumé : uniquement l''utilisateur connecté');

select * from finish();
rollback;
