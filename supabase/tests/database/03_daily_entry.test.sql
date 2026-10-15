-- Lot 3 : onboarding et vue budget_status_current_month.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email) values
  ('31111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('32222222-2222-2222-2222-222222222222', 'b@test.local');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"31111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- Onboarding ------------------------------------------------------------------
select is(
  public.complete_onboarding(200, 1000, 500),
  date_trunc('month', now() at time zone 'Europe/Paris')::date,
  'onboarding : ouvre le mois en cours');
select is((select balance from public.accounts where type = 'courant'), 200.00,
  'onboarding : courant initialisé');
select is((select current_amount from public.savings_projects where is_safety_fund), 1000.00,
  'onboarding : Fond de sécurité initialisé');
select is((select balance from public.accounts where type = 'epargne'), 1500.00,
  'onboarding : compte épargne = Σ projets');
select is((select status::text from public.monthly_settlements), 'pending',
  'onboarding : mois en cours ouvert');
select throws_ok($$select public.complete_onboarding(200)$$, 'FF005', null,
  'onboarding : une seule fois');

-- Budgets du mois en cours ---------------------------------------------------
update public.budgets set monthly_amount = 400 where category = 'Courses';
insert into public.transactions (type, amount, category, date) values
  ('depense', 120, 'Courses', current_date),
  ('depense', 30, 'Courses', current_date),
  ('revenu', 20, 'Courses', current_date),
  ('depense', 999, 'Courses', current_date - interval '2 months');
insert into public.transactions (type, amount, category, date, hors_budget)
values ('depense', 50, 'Courses', current_date, true),
       ('depense', 600, 'Frais externes', current_date, true);
insert into public.subscriptions (name, amount, billing_day) values
  ('Streaming', 12.99, 5), ('Musique', 10.99, 12);
insert into public.subscriptions (name, amount, billing_day, active) values ('Ancien', 50, 1, false);

select is(
  (select (allocated, spent, remaining)::text from public.budget_status_current_month
   where category = 'Courses'),
  '(400.00,130.00,270.00)',
  'Courses : revenu déduit, hors budget et autres mois exclus');
select is(
  (select allocated from public.budget_status_current_month where category = 'Abonnements'),
  23.98, 'Abonnements : alloué = Σ abonnements actifs');
select is(
  (select spent from public.budget_status_current_month where category = 'Frais externes'),
  600.00, 'Frais externes : budget hors budget, compte ses propres dépenses');
select is((select count(*)::int from public.budget_status_current_month), 9,
  'une ligne par budget');

-- Catégories -----------------------------------------------------------------
reset role;
update public.transactions set settled = true
where user_id = '31111111-1111-1111-1111-111111111111' and amount = 999;
set local role authenticated;

update public.budgets set category = 'Alimentation' where category = 'Courses';
select is(
  (select count(*)::int from public.transactions where category = 'Alimentation'),
  5, 'renommage : transactions renommées, réglées comprises');
select throws_ok(
  $$update public.budgets set category = 'Abos' where category = 'Abonnements'$$,
  'FF006', null, 'budget Abonnements non renommable');
select throws_ok(
  $$delete from public.budgets where category = 'Frais externes'$$,
  'FF006', null, 'budget Frais externes non supprimable');
select lives_ok(
  $$delete from public.budgets where category = 'Loisirs'$$,
  'budget ordinaire supprimable');

-- Isolation ---------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"32222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*)::int from public.budget_status_current_month), 0,
  'B sans mois en cours ne voit aucun budget de A');
select lives_ok($$select public.complete_onboarding(200)$$, 'B fait son onboarding');
select is(
  (select spent from public.budget_status_current_month where category = 'Courses'),
  0.00, 'B ne voit pas les dépenses de A');

-- Suppression d'un compte utilisateur : les budgets système partent en cascade.
reset role;
select lives_ok(
  $$delete from auth.users where id = '31111111-1111-1111-1111-111111111111'$$,
  'suppression d''un utilisateur malgré les budgets système');

select * from finish();
rollback;
