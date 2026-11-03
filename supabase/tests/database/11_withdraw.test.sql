-- Virement de l'épargne vers le courant.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email) values
  ('c0000000-0000-0000-0000-000000000001', 'w@test.local'),
  ('c0000000-0000-0000-0000-000000000002', 'w2@test.local');
update public.accounts set balance = 100
where user_id = 'c0000000-0000-0000-0000-000000000001' and type = 'courant';
update public.savings_projects set current_amount = 500
where user_id = 'c0000000-0000-0000-0000-000000000001' and is_safety_fund;
update public.savings_projects set current_amount = 50
where user_id = 'c0000000-0000-0000-0000-000000000001' and is_default;
insert into public.savings_projects (user_id, name, current_amount) values
  ('c0000000-0000-0000-0000-000000000001', 'Vacances', 200);
update public.accounts set balance = 750
where user_id = 'c0000000-0000-0000-0000-000000000001' and type = 'epargne';
select set_config('request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

create function pg_temp.saved(p_name text) returns numeric language sql as $$
  select current_amount from public.savings_projects where name = p_name
$$;
create function pg_temp.balance(p_type public.account_type) returns numeric language sql as $$
  select balance from public.accounts where type = p_type
$$;

select public.withdraw_from_savings(30, (select id from public.savings_projects where name = 'Vacances'));
select is(pg_temp.saved('Vacances'), 170.00, 'avec projet : retiré de ce projet');
select is(pg_temp.balance('courant'), 130.00, 'courant crédité tout de suite');

select public.withdraw_from_savings(250);
select is(
  (select array[pg_temp.saved('Épargne générale'), pg_temp.saved('Vacances'), pg_temp.saved('Fond de sécurité')]::text),
  '{0.00,0.00,470.00}', 'sans projet : Épargne générale, autres projets, Fond de sécurité en dernier');
select is(pg_temp.balance('epargne'),
  (select sum(current_amount) from public.savings_projects), 'invariant : compte épargne = Σ projets');
select is(pg_temp.balance('courant'), 380.00, 'courant : + 280 au total');
select is(
  (select count(*)::int from public.transactions where type = 'retrait_epargne' and settled),
  4, 'un retrait par projet entamé');

insert into public.transactions (type, amount, label, category, hors_budget)
values ('depense', 20, 'Cadeau', 'Courses', true);
select public.withdraw_from_savings(20, null,
  (select id from public.transactions where label = 'Cadeau'));
select is(
  (select (t.amount, t.label)::text from public.transactions t
   join public.transactions d on d.id = t.reimburses_id where d.label = 'Cadeau'),
  '(20.00,"Fond de sécurité")', 'remboursement relié à la dépense');
select throws_ok(
  $$select public.withdraw_from_savings(5, null,
    (select id from public.transactions where type = 'retrait_epargne' limit 1))$$,
  'FF004', null, 'on ne rembourse qu''une dépense');

select throws_ok($$select public.withdraw_from_savings(1000)$$, 'FF004', null,
  'épargne insuffisante : refusé, rien de retiré');
select throws_ok(
  $$select public.withdraw_from_savings(10, (select id from public.savings_projects where name = 'Vacances'))$$,
  'FF004', null, 'projet vide : refusé');

select set_config('test.fund', (select id::text from public.savings_projects where is_safety_fund), true);
select set_config('request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select throws_ok(
  format($$select public.withdraw_from_savings(10, %L)$$, current_setting('test.fund')),
  'FF003', null, 'projet d''un autre utilisateur : refusé');

select * from finish();
rollback;
