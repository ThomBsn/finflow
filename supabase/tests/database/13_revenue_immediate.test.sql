-- Un revenu saisi est crédité sur le courant tout de suite.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email) values ('e0000000-0000-0000-0000-000000000001', 'rev@test.local');
update public.accounts set balance = 350
where user_id = 'e0000000-0000-0000-0000-000000000001' and type = 'courant';
insert into public.monthly_settlements (user_id, month, salary, shared_transfer)
values ('e0000000-0000-0000-0000-000000000001', '2026-10-01', 2500, 600);
select set_config('request.jwt.claims',
  '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

create function pg_temp.courant() returns numeric language sql as $$
  select balance from public.accounts where type = 'courant'
$$;

insert into public.transactions (type, amount, label, category, date) values
  ('depense', 1500, 'Courses', 'Courses', '2026-10-05');
insert into public.transactions (type, amount, label, date) values
  ('revenu', 100, 'Remboursement mutuelle', '2026-10-06');

select is(
  (select (immediate, pg_temp.courant())::text from public.transactions where label = 'Remboursement mutuelle'),
  '(t,450.00)', 'revenu : immédiat, courant crédité à la saisie');
update public.transactions set amount = 150 where label = 'Remboursement mutuelle';
select is(pg_temp.courant(), 500.00, 'revenu modifié : courant ajusté');
update public.transactions set immediate = false where label = 'Remboursement mutuelle';
select is(pg_temp.courant(), 500.00, 'un revenu reste immédiat');
select is(
  (select (unsettled_expenses, immediate_expenses, projected_savings)::text from public.current_month_summary),
  '(1500.00,-150.00,700.00)', 'épargne prévue : le revenu est sur le courant, pas en déduction');
select is(
  (public.preview_close_month(2500, 600) ->> 'total_expenses')::numeric, 1350.00,
  'aperçu : dépenses du mois nettes du revenu');
select is(
  ((public.close_month('2026-10-01', 2500, 600)) ->> 'total_savings')::numeric, 700.00,
  'clôture : revenu pas recrédité (épargne 700)');
select is(
  (select (opening_balance, total_expenses)::text from public.monthly_settlements where month = '2026-10-01'),
  '(350.00,1350.00)', 'clôture : solde de départ avant le revenu, dépenses nettes');

select * from finish();
rollback;
