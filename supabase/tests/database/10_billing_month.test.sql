-- Mois de débit choisi à la saisie, prérempli avec le mois en cours.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email)
values ('a0000000-0000-0000-0000-000000000001', 'billing@test.local');
update public.accounts set balance = 1000
where user_id = 'a0000000-0000-0000-0000-000000000001' and type = 'courant';
insert into public.monthly_settlements (user_id, month)
values ('a0000000-0000-0000-0000-000000000001', '2026-10-01');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

insert into public.transactions (type, amount, label, category, date) values
  ('depense', 100, 'Début novembre', 'Courses', '2026-11-02');
insert into public.transactions (type, amount, label, category, date, month) values
  ('depense', 40, 'Fin octobre reportée', 'Courses', '2026-10-30', '2026-11-01'),
  ('depense', 1.99, 'Septembre oubliée', 'Courses', '2026-09-29', '2026-09-01');

select is(
  (select month from public.transactions where label = 'Début novembre'),
  '2026-10-01'::date, 'sans mois précisé : mois en cours, même datée du mois suivant');
select is((select unsettled_expenses from public.current_month_summary), 100.00,
  'la dépense reportée ne compte pas pour octobre');
select is((select spent from public.budget_status_current_month where category = 'Courses'),
  100.00, 'budget d''octobre : selon le mois de débit');
select throws_ok(
  $$update public.transactions set month = '2026-11-15' where label = 'Début novembre'$$,
  '23514', null, 'mois de débit : premier jour du mois');

select public.close_month('2026-10-01', 2000, 0, true);
select is(
  (select settled from public.transactions where label = 'Septembre oubliée'),
  false, 'transaction d''un mois antérieur : ni comptée ni réglée par la clôture');
select is(
  (select (settled, month)::text from public.transactions where label = 'Fin octobre reportée'),
  '(f,2026-11-01)', 'clôture d''octobre : la dépense reportée reste à régler');
select is(
  (select month from public.transactions where type = 'salaire' and label = 'Salaire'),
  '2026-11-01'::date, 'salaire créé par la clôture : mois de sa date');
select is((select unsettled_expenses from public.current_month_summary), 40.00,
  'novembre : la dépense reportée à régler');

select * from finish();
rollback;
