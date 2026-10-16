-- Lot 4 : abonnements, échelonnements, projets d'épargne.
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

insert into auth.users (id, email) values
  ('51111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('52222222-2222-2222-2222-222222222222', 'b@test.local');
insert into public.monthly_settlements (user_id, month) values
  ('51111111-1111-1111-1111-111111111111', '2026-10-01'),
  ('52222222-2222-2222-2222-222222222222', '2026-10-01');
update public.accounts set balance = 200
where type = 'courant' and user_id in (
  '51111111-1111-1111-1111-111111111111', '52222222-2222-2222-2222-222222222222');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true)
$$;
select pg_temp.act_as('51111111-1111-1111-1111-111111111111');

-- Abonnements ---------------------------------------------------------------
insert into public.subscriptions (user_id, name, amount, billing_day, created_at)
values ('51111111-1111-1111-1111-111111111111', 'Streaming', 12.99, 5, '2026-10-01');

-- La génération traite tous les utilisateurs : on ne compte que ceux de A.
select private.generate_subscription_charges('2026-10-05');
select is((select count(*)::int from public.transactions where user_id = '51111111-1111-1111-1111-111111111111' and subscription_id is not null), 1, 'prélèvement du 5');
delete from public.transactions where user_id = '51111111-1111-1111-1111-111111111111' and subscription_id is not null;
select private.generate_subscription_charges('2026-10-06');
select is((select count(*)::int from public.transactions where user_id = '51111111-1111-1111-1111-111111111111' and subscription_id is not null), 0, 'prélèvement supprimé : pas recréé');
update public.subscriptions set billing_day = 20 where user_id = '51111111-1111-1111-1111-111111111111';
select private.generate_subscription_charges('2026-10-20');
select is((select count(*)::int from public.transactions where user_id = '51111111-1111-1111-1111-111111111111' and subscription_id is not null), 0, 'jour changé : pas de second prélèvement dans le mois');
select private.generate_subscription_charges('2026-11-20');
select is((select count(*)::int from public.transactions where user_id = '51111111-1111-1111-1111-111111111111' and subscription_id is not null), 1, 'mois suivant : prélèvement au nouveau jour');
select is(
  (select last_charge_date from public.subscriptions where name = 'Streaming'),
  '2026-11-20'::date, 'date du dernier prélèvement mémorisée');
select is(
  (select count(*)::int from cron.job
   where jobname = 'finflow-subscription-charges' and schedule = '0 4 * * *'),
  1, 'passage quotidien planifié');

-- Échelonnements : étalement d'une dépense sur son budget ------------------
set local role authenticated;

insert into public.transactions (type, amount, label, category, date)
values ('depense', 200, 'Téléphone', 'Loisirs', '2026-10-16');
select set_config('test.tx',
  (select id::text from public.transactions where label = 'Téléphone'), true);
insert into public.installment_plans (transaction_id, installments)
values (current_setting('test.tx')::uuid, 3);

select is(
  (select spent from public.budget_status_current_month where category = 'Loisirs'),
  66.66, 'budget : seule la mensualité du mois compte');
select is(
  (select (l.amount, l.installment_number, l.installments)::text
   from public.budget_lines_current_month l
   join public.budgets b on b.id = l.budget_id where b.category = 'Loisirs'),
  '(66.66,1,3)', 'composition : mensualité 1/3');
select is((select unsettled_expenses from public.current_month_summary), 200.00,
  'courant : la dépense entière sera réglée à la clôture');
select is(
  (select (monthly_amount, current_number, remaining_count, remaining_amount)::text
   from public.installment_plans_status),
  '(66.66,1,2,133.34)', 'plan : mensualité 1, 2 restantes');

insert into public.transactions (type, amount, label, category, date) values
  ('revenu', 20, 'Remboursement', 'Courses', '2026-10-10'),
  ('depense', 50, 'Marché', 'Courses', '2026-10-11');
insert into public.transactions (type, amount, label, category, date, hors_budget)
values ('depense', 40, 'Cadeau', 'Courses', '2026-10-12', true);
select throws_ok(
  $$insert into public.installment_plans (transaction_id, installments)
    select id, 2 from public.transactions where label = 'Remboursement'$$,
  'FF004', null, 'un revenu ne s''échelonne pas');
select throws_ok(
  $$insert into public.installment_plans (transaction_id, installments)
    select id, 2 from public.transactions where label = 'Cadeau'$$,
  'FF004', null, 'une dépense hors budget ne s''échelonne pas');
select is(
  (select array_agg(l.amount order by l.amount)::text
   from public.budget_lines_current_month l
   join public.budgets b on b.id = l.budget_id where b.category = 'Courses'),
  '{-20.00,50.00}', 'composition : dépense +, revenu −, hors budget exclu');

insert into public.transactions (type, amount, label, category, date)
values ('depense', 90, 'Concert', 'Loisirs', '2026-10-20');
insert into public.installment_plans (transaction_id, installments)
select id, 3 from public.transactions where label = 'Concert';
select is(
  (select spent from public.budget_status_current_month where category = 'Loisirs'),
  96.66, 'deux dépenses étalées : 66,66 + 30');
delete from public.installment_plans
where transaction_id = (select id from public.transactions where label = 'Concert');
select is(
  (select spent from public.budget_status_current_month where category = 'Loisirs'),
  156.66, 'étalement supprimé : la dépense compte en entier');
insert into public.installment_plans (transaction_id, installments)
select id, 3 from public.transactions where label = 'Concert';
delete from public.transactions where label = 'Concert';
select is((select count(*)::int from public.installment_plans), 1,
  'dépense supprimée : son étalement aussi');

select public.close_month('2026-10-01', 0, 0, true);
select is(
  (select spent from public.budget_status_current_month where category = 'Loisirs'),
  66.66, 'novembre : mensualité 2');
select is(
  (select (current_number, remaining_count, remaining_amount)::text
   from public.installment_plans_status),
  '(2,1,66.68)', 'novembre : 1 mensualité restante');
select public.close_month('2026-11-01', 0, 0, true);
select is(
  (select spent from public.budget_status_current_month where category = 'Loisirs'),
  66.68, 'décembre : dernière mensualité avec le reliquat');
select public.close_month('2026-12-01', 0, 0, true);
select is(
  (select spent from public.budget_status_current_month where category = 'Loisirs'),
  0.00, 'janvier : étalement terminé');

-- Projets d'épargne ---------------------------------------------------------
select set_config('test.project',
  public.create_savings_project('Vacances', 20, 500, 300)::text, true);
select is((select current_amount from public.savings_projects where name = 'Vacances'),
  300.00, 'projet repris avec son montant déjà épargné');
select is((select balance from public.accounts where type = 'epargne'), 300.00,
  'reprise : compte épargne crédité');
select is((select balance from public.accounts where type = 'courant'), -82.99,
  'reprise : courant inchangé (200 − 270 de dépenses − 12,99 d''abonnement)');

select public.save_to_savings(100, 'precis', current_setting('test.project')::uuid);
select is((select current_amount from public.savings_projects where name = 'Vacances'),
  400.00, 'versement précis : projet crédité');
select is((select balance from public.accounts where type = 'courant'), -182.99,
  'versement : courant débité');
select is(
  (select balance from public.accounts where type = 'epargne'),
  (select sum(current_amount) from public.savings_projects),
  'invariant : compte épargne = Σ projets');

select throws_ok($$select public.create_savings_project('Voiture', 90)$$,
  '23514', null, 'somme des pourcentages > 100 refusée');
select throws_ok($$select public.save_to_savings(0, 'automatique')$$,
  'FF004', null, 'versement nul refusé');

-- Isolation -------------------------------------------------------------------
select pg_temp.act_as('52222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.installment_plans_status), 0,
  'B ne voit pas les échelonnements de A');
select throws_ok(
  format($$select public.save_to_savings(10, 'precis', %L)$$, current_setting('test.project')),
  'FF003', null, 'B ne peut pas verser sur le projet de A');
select throws_ok(
  format($$insert into public.installment_plans (transaction_id, installments) values (%L, 2)$$,
         current_setting('test.tx')),
  'FF004', null, 'B ne peut pas étaler une dépense de A');

select * from finish();
rollback;
