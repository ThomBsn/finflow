-- Projets : icône, correction du montant ; jauge : part des étalements.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email)
values ('80000000-0000-0000-0000-000000000001', 'icons@test.local');
insert into public.monthly_settlements (user_id, month)
values ('80000000-0000-0000-0000-000000000001', '2026-10-01');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"80000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

-- Icônes ------------------------------------------------------------------------
select is(
  (select array_agg(icon order by icon)::text from public.savings_projects),
  '{account_balance,shield}', 'projets système créés avec leur icône');
select public.create_savings_project('Moto', 10, 3000, 1000, 'two_wheeler');
select is((select icon from public.savings_projects where name = 'Moto'), 'two_wheeler',
  'icône choisie à la création');
update public.savings_projects set icon = 'flight' where name = 'Moto';
select is((select icon from public.savings_projects where name = 'Moto'), 'flight',
  'icône modifiable par le client');

-- Correction du montant ----------------------------------------------------------
select public.adjust_savings_project(
  (select id from public.savings_projects where is_safety_fund), 2500);
select is((select current_amount from public.savings_projects where is_safety_fund), 2500.00,
  'Fond de sécurité corrigé');
select public.adjust_savings_project(
  (select id from public.savings_projects where name = 'Moto'), 800);
select is((select balance from public.accounts where type = 'epargne'), 3300.00,
  'compte épargne recalé (2 500 + 800)');
select is((select balance from public.accounts where type = 'courant'), 0.00,
  'correction : courant inchangé');
select throws_ok(
  $$select public.adjust_savings_project(
      (select id from public.savings_projects where is_default), -1)$$,
  'FF004', null, 'montant négatif refusé');
select throws_ok(
  $$select public.adjust_savings_project('00000000-0000-0000-0000-000000000000', 10)$$,
  'FF003', null, 'projet inconnu refusé');

-- Jauge : part des étalements ------------------------------------------------------
update public.budgets set monthly_amount = 300 where category = 'Loisirs';
insert into public.transactions (type, amount, label, category, date) values
  ('depense', 200, 'Display', 'Loisirs', '2026-10-16'),
  ('depense', 50, 'Cinéma', 'Loisirs', '2026-10-18');
insert into public.installment_plans (transaction_id, installments)
select id, 4 from public.transactions where label = 'Display';
select is(
  (select (allocated, spent, installment_spent)::text from public.budget_status_current_month
   where category = 'Loisirs'),
  '(300.00,100.00,50.00)', 'Loisirs : 50 de mensualité + 50 de dépenses');

-- Isolation ------------------------------------------------------------------------
reset role;
insert into auth.users (id, email)
values ('80000000-0000-0000-0000-000000000002', 'icons2@test.local');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"80000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select throws_ok(
  format($$select public.adjust_savings_project(%L, 10)$$,
         (select id::text from public.savings_projects
          where user_id = '80000000-0000-0000-0000-000000000001' and is_default)),
  'FF003', null, 'impossible de corriger le projet d''un autre utilisateur');

select * from finish();
rollback;
