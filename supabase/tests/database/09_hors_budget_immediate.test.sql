-- Hors budget ignoré, débit immédiat, échelonnements débités par mensualité.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

-- Crée l'utilisateur n (courant de départ, octobre en cours) et agit en son nom.
create function pg_temp.setup(p_n int, p_courant numeric) returns uuid
language plpgsql as $$
declare
  v_id uuid := ('90000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email) values (v_id, 'h' || p_n || '@test.local');
  update public.accounts set balance = p_courant where user_id = v_id and type = 'courant';
  insert into public.monthly_settlements (user_id, month, salary, shared_transfer)
  values (v_id, '2026-10-01', 2500, 600);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
  return v_id;
end;
$$;

create function pg_temp.courant() returns numeric language sql as $$
  select balance from public.accounts where type = 'courant'
$$;

create function pg_temp.amounts(p jsonb) returns text language sql as $$
  select format('%s|%s|%s',
    (p ->> 'total_expenses')::numeric(12,2),
    (p ->> 'total_savings')::numeric(12,2),
    (p ->> 'courant')::numeric(12,2))
$$;

create function pg_temp.flows_balance() returns numeric language sql as $$
  select sum(case side when 'in' then amount else -amount end) from public.settlement_flows
$$;

-- Hors budget : hors des budgets, mais déduit à la clôture ------------------
select pg_temp.setup(1, 350);
set local role authenticated;
insert into public.transactions (type, amount, label, category, date) values
  ('depense', 1400, 'Courses', 'Courses', '2026-10-05');
insert into public.transactions (type, amount, label, category, date, hors_budget) values
  ('depense', 300, 'Billet avancé', 'Loisirs', '2026-10-06', true);

select is(
  (select (unsettled_expenses, hors_budget_expenses, projected_savings)::text
   from public.current_month_summary),
  '(1700.00,300.00,350.00)', 'hors budget : compté dans l''épargne prévue, totalisé à part');
select is((select spent from public.budget_status_current_month where category = 'Loisirs'),
  0.00, 'hors budget : exclu du budget de sa catégorie');
select set_config('test.preview', public.preview_close_month(2500, 600)::text, true);
select is(pg_temp.amounts(public.close_month('2026-10-01', 2500, 600)), '1700.00|350.00|200.00',
  'hors budget : déduit à la clôture');
select is(pg_temp.amounts(current_setting('test.preview')::jsonb), '1700.00|350.00|200.00',
  'hors budget : aperçu = clôture');
select is(
  (select amount from public.settlement_flows where label = 'Loisirs'),
  300.00, 'hors budget : dans les flux');
select is(pg_temp.flows_balance(), 0.00, 'hors budget : entrées = sorties');

-- Débit immédiat ---------------------------------------------------------------
reset role;
select pg_temp.setup(2, 350);
set local role authenticated;
insert into public.transactions (type, amount, label, category, date, immediate) values
  ('depense', 100, 'Retrait', 'Courses', '2026-10-05', true);
select is(pg_temp.courant(), 250.00, 'immédiat : courant débité à la saisie');
update public.transactions set amount = 150 where label = 'Retrait';
select is(pg_temp.courant(), 200.00, 'immédiat : montant modifié, courant ajusté');
update public.transactions set immediate = false where label = 'Retrait';
select is(pg_temp.courant(), 350.00, 'immédiat désactivé : courant recrédité');
update public.transactions set immediate = true where label = 'Retrait';
insert into public.transactions (type, amount, label, category, date, immediate) values
  ('depense', 40, 'Annulée', 'Courses', '2026-10-05', true);
delete from public.transactions where label = 'Annulée';
select is(pg_temp.courant(), 200.00, 'immédiat supprimé : courant recrédité');

insert into public.transactions (type, amount, label, category, date) values
  ('depense', 1250, 'Courses', 'Courses', '2026-10-06');
select is(
  (select (courant, unsettled_expenses, immediate_expenses, projected_savings)::text
   from public.current_month_summary),
  '(200.00,1250.00,150.00,650.00)', 'immédiat : déjà dans le courant, pas dans les dépenses à régler');
select set_config('test.preview', public.preview_close_month(2500, 600)::text, true);
select is(pg_temp.amounts(public.close_month('2026-10-01', 2500, 600)),
  pg_temp.amounts(current_setting('test.preview')::jsonb), 'immédiat : aperçu = clôture');
select is(pg_temp.amounts(current_setting('test.preview')::jsonb), '1400.00|650.00|200.00',
  'immédiat : pas débité deux fois (épargne 650)');
select is(
  (select (opening_balance, total_expenses)::text from public.monthly_settlements
   where month = '2026-10-01'),
  '(350.00,1400.00)', 'immédiat : solde de départ avant débit, compté dans les dépenses');
select is(
  (select amount from public.settlement_flows where kind = 'expense' and label = 'Courses'),
  1400.00, 'immédiat : dans les flux de sa catégorie');
select is(pg_temp.flows_balance(), 0.00, 'immédiat : entrées = sorties');

select lives_ok(
  $$insert into public.transactions (type, amount, category, hors_budget, immediate)
    values ('depense', 10, 'Courses', true, true)$$,
  'débit immédiat possible pour une dépense hors budget');
insert into public.transactions (type, amount, label, category, date, immediate) values
  ('depense', 90, 'Casque', 'Loisirs', '2026-11-05', true);
select lives_ok(
  $$insert into public.installment_plans (transaction_id, installments)
    select id, 3 from public.transactions where label = 'Casque'$$,
  'débit immédiat échelonnable : l''étalement ne touche que le budget');

-- Échelonnement : budget étalé, dépense débitée en entier -----------------------
reset role;
select pg_temp.setup(3, 350);
set local role authenticated;
insert into public.transactions (type, amount, label, category, date) values
  ('depense', 200, 'Téléphone', 'Loisirs', '2026-10-16'),
  ('depense', 1000, 'Courses', 'Courses', '2026-10-05');
insert into public.installment_plans (transaction_id, installments)
select id, 3 from public.transactions where label = 'Téléphone';

select is((select unsettled_expenses from public.current_month_summary), 1200.00,
  'échelonnée : la dépense entière à débiter');
select is((select spent from public.budget_status_current_month where category = 'Loisirs'),
  66.66, 'échelonnée : le budget ne compte que la mensualité');
select set_config('test.preview', public.preview_close_month(2500, 600)::text, true);
select is(pg_temp.amounts(public.close_month('2026-10-01', 2500, 600)),
  pg_temp.amounts(current_setting('test.preview')::jsonb), 'échelonnée : aperçu = clôture');
select is(pg_temp.amounts(current_setting('test.preview')::jsonb), '1200.00|850.00|200.00',
  'échelonnée : débitée en entier à la clôture de son mois');
select is(
  (select amount from public.settlement_flows where kind = 'expense' and label = 'Loisirs'),
  200.00, 'échelonnée : en entier dans les flux');
select is(pg_temp.flows_balance(), 0.00, 'échelonnée : entrées = sorties');
select is((select unsettled_expenses from public.current_month_summary), 0.00,
  'novembre : plus rien à débiter');
select is((select spent from public.budget_status_current_month where category = 'Loisirs'),
  66.66, 'novembre : le budget compte la mensualité 2');

select * from finish();
rollback;
