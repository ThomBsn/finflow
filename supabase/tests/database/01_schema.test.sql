-- Lot 1 : données par défaut, isolation entre utilisateurs, droits d'écriture.
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

-- Données par défaut créées à l'inscription -------------------------------
select is(
  (select array_agg(type order by type)::text from public.accounts
   where user_id = '11111111-1111-1111-1111-111111111111'),
  '{courant,epargne}', 'comptes courant + épargne créés');
select is(
  (select count(*)::int from public.savings_projects
   where user_id = '11111111-1111-1111-1111-111111111111' and (is_default or is_safety_fund)),
  2, 'Fond de sécurité + Épargne générale créés');
select ok(
  exists (select 1 from public.budgets
          where user_id = '11111111-1111-1111-1111-111111111111'
            and category = 'Frais externes' and hors_budget),
  'budget « Frais externes » hors budget');
select ok(
  exists (select 1 from public.budgets
          where user_id = '11111111-1111-1111-1111-111111111111' and category = 'Abonnements'),
  'budget « Abonnements »');
select is(
  (select safety_margin from public.settings
   where user_id = '11111111-1111-1111-1111-111111111111'),
  200.00, 'marge de sécurité à 200 par défaut');

-- Compte courant de A, pour la tentative d'accès de B plus bas.
select set_config('test.a_courant', id::text, true)
from public.accounts
where user_id = '11111111-1111-1111-1111-111111111111' and type = 'courant';

-- En tant que A ------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select lives_ok(
  $$insert into public.transactions (type, amount, label, category, date)
    values ('depense', 42.50, 'Courses', 'Courses', '2026-10-16')$$,
  'A saisit une dépense');
select is((select month from public.transactions), '2026-10-01'::date,
  'month calculé depuis date');
select is((select account_id::text from public.transactions),
  current_setting('test.a_courant'), 'compte courant par défaut');
select is((select settled from public.transactions), false, 'dépense non réglée');

select throws_ok(
  $$update public.accounts set balance = 1000$$,
  '42501', null, 'solde non modifiable par le client');
select throws_ok(
  $$update public.transactions set settled = true$$,
  '42501', null, 'settled non modifiable par le client');
select throws_ok(
  $$insert into public.transactions (type, amount) values ('transfert_epargne', 10)$$,
  '42501', null, 'pas de transfert d''épargne saisi à la main');
select throws_ok(
  $$update public.savings_projects set current_amount = 1000$$,
  '42501', null, 'montant épargné non modifiable par le client');

select lives_ok(
  $$insert into public.savings_projects (name, percentage) values ('Vacances', 60)$$,
  'projet à 60 %');
select throws_ok(
  $$insert into public.savings_projects (name, percentage) values ('Voiture', 50)$$,
  '23514', null, 'somme des pourcentages > 100 refusée');

delete from public.savings_projects where is_safety_fund or is_default;
select is((select count(*)::int from public.savings_projects where is_safety_fund or is_default),
  2, 'Fond de sécurité et Épargne générale non supprimables');

-- Une transaction réglée est figée.
reset role;
update public.transactions set settled = true
where user_id = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
delete from public.transactions;
select is((select count(*)::int from public.transactions), 1,
  'transaction réglée non supprimable');

-- En tant que B ------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is((select count(*)::int from public.transactions), 0,
  'B ne voit pas les transactions de A');
select is((select count(*)::int from public.savings_projects), 2,
  'B ne voit que ses propres projets');
select is((select count(*)::int from public.accounts), 2,
  'B ne voit que ses propres comptes');
select throws_ok(
  format($$insert into public.transactions (type, amount, category, account_id)
           values ('depense', 1, 'Courses', %L)$$, current_setting('test.a_courant')),
  '23503', null, 'B ne peut pas utiliser le compte de A');

select * from finish();
rollback;
