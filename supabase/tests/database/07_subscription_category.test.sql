-- Catégorie par abonnement : prélèvement, part réservée, renommage.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email)
values ('70000000-0000-0000-0000-000000000001', 'cat@test.local');
insert into public.monthly_settlements (user_id, month)
values ('70000000-0000-0000-0000-000000000001', '2026-10-01');
insert into public.budgets (user_id, category, monthly_amount)
values ('70000000-0000-0000-0000-000000000001', 'Véhicule', 150);
insert into public.subscriptions (user_id, name, amount, billing_day, category, created_at) values
  ('70000000-0000-0000-0000-000000000001', 'Assurance moto', 40, 20, 'Véhicule', '2026-10-01'),
  ('70000000-0000-0000-0000-000000000001', 'Streaming', 9.99, 5, 'Abonnements', '2026-10-10');
select set_config('request.jwt.claims',
  '{"sub":"70000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

create function pg_temp.budget(p_category text) returns text language sql as $$
  select (allocated, spent, remaining, reserved)::text
  from public.budget_status_current_month
  where user_id = '70000000-0000-0000-0000-000000000001' and category = p_category
$$;

-- Avant le prélèvement ---------------------------------------------------------
select is(pg_temp.budget('Véhicule'), '(150.00,0.00,150.00,40.00)',
  'Véhicule : 40 € réservés pour l''assurance à venir');
select is(pg_temp.budget('Abonnements'), '(9.99,0.00,9.99,0.00)',
  'Abonnements : alloué = ses seuls abonnements ; créé après le 5, rien de réservé');

update public.budgets set monthly_amount = 20
where user_id = '70000000-0000-0000-0000-000000000001' and category = 'Véhicule';
select is(
  (select budget_remaining from public.current_month_summary
   where user_id = '70000000-0000-0000-0000-000000000001'),
  49.99, 'enveloppe trop petite : l''abonnement à venir compte quand même (40 + 9,99)');

-- Prélèvement ------------------------------------------------------------------
select private.generate_subscription_charges('2026-10-20');
select is(
  (select (category, amount, hors_budget)::text from public.transactions
   where user_id = '70000000-0000-0000-0000-000000000001' and label = 'Assurance moto'),
  '(Véhicule,40.00,f)', 'prélèvement rangé dans la catégorie de l''abonnement');
select is(pg_temp.budget('Véhicule'), '(20.00,40.00,-20.00,0.00)',
  'après prélèvement : dépensé, plus rien de réservé');

-- Catégorie hors budget : le prélèvement l'est aussi.
insert into public.subscriptions (user_id, name, amount, billing_day, category, created_at)
values ('70000000-0000-0000-0000-000000000001', 'Box', 30, 20, 'Frais externes', '2026-10-01');
select private.generate_subscription_charges('2026-10-21');
select is(
  (select hors_budget from public.transactions
   where user_id = '70000000-0000-0000-0000-000000000001' and label = 'Box'),
  true, 'abonnement d''une catégorie hors budget : prélèvement hors budget');

-- Renommage / suppression d'un budget ---------------------------------------------
update public.budgets set category = 'Moto'
where user_id = '70000000-0000-0000-0000-000000000001' and category = 'Véhicule';
select is(
  (select category from public.subscriptions
   where user_id = '70000000-0000-0000-0000-000000000001' and name = 'Assurance moto'),
  'Moto', 'budget renommé : l''abonnement suit');
select is(
  (select category from public.transactions
   where user_id = '70000000-0000-0000-0000-000000000001' and label = 'Assurance moto'),
  'Moto', 'budget renommé : son prélèvement aussi');

delete from public.budgets
where user_id = '70000000-0000-0000-0000-000000000001' and category = 'Moto';
select is(
  (select category from public.subscriptions
   where user_id = '70000000-0000-0000-0000-000000000001' and name = 'Assurance moto'),
  'Abonnements', 'budget supprimé : l''abonnement revient dans Abonnements');
select is(pg_temp.budget('Abonnements'), '(49.99,0.00,49.99,0.00)',
  'Abonnements reprend l''assurance ; déjà prélevée en octobre, rien de réservé');

-- Isolation -----------------------------------------------------------------------
insert into auth.users (id, email)
values ('70000000-0000-0000-0000-000000000002', 'other@test.local');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"70000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is((select count(*)::int from public.subscriptions), 0,
  'un autre utilisateur ne voit pas ces abonnements');

select * from finish();
rollback;
