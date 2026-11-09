-- Épargne prévue : les hors budget seront remboursés, ils ne la diminuent pas.
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email) values ('d0000000-0000-0000-0000-000000000001', 'hb@test.local');
update public.accounts set balance = 350
where user_id = 'd0000000-0000-0000-0000-000000000001' and type = 'courant';
update public.savings_projects set current_amount = 500
where user_id = 'd0000000-0000-0000-0000-000000000001' and is_default;
update public.accounts set balance = 500
where user_id = 'd0000000-0000-0000-0000-000000000001' and type = 'epargne';
insert into public.monthly_settlements (user_id, month, salary, shared_transfer)
values ('d0000000-0000-0000-0000-000000000001', '2026-10-01', 2500, 600);
select set_config('request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

insert into public.transactions (type, amount, label, category, date) values
  ('depense', 1000, 'Courses', 'Courses', '2026-10-05');
insert into public.transactions (type, amount, label, category, date, hors_budget) values
  ('depense', 100, 'Cadeau', 'Loisirs', '2026-10-06', true);

select is(
  (select (unsettled_expenses, hors_budget_pending, projected_savings)::text from public.current_month_summary),
  '(1100.00,100.00,1050.00)', 'hors budget à rembourser : ne diminue pas l''épargne prévue');
select is((public.preview_close_month(2500, 600) ->> 'total_savings')::numeric, 950.00,
  'aperçu de clôture : déduit tout ce que la carte débite');

select public.withdraw_from_savings(40, null, (select id from public.transactions where label = 'Cadeau'));
select is(
  (select (courant, hors_budget_pending, projected_savings)::text from public.current_month_summary),
  '(390.00,60.00,1050.00)', 'remboursement partiel : épargne prévue inchangée');

select public.withdraw_from_savings(60, null, (select id from public.transactions where label = 'Cadeau'));
select is(
  (select (courant, hors_budget_pending, projected_savings)::text from public.current_month_summary),
  '(450.00,0.00,1050.00)', 'remboursé en entier : épargne prévue inchangée');
select is((public.preview_close_month(2500, 600) ->> 'total_savings')::numeric, 1050.00,
  'remboursé : la clôture rejoint l''épargne prévue');

select set_config('test.projected',
  (select projected_savings::text from public.current_month_summary), true);
select is(
  (public.close_month('2026-10-01', 2500, 600) ->> 'total_savings')::numeric(12,2),
  current_setting('test.projected')::numeric(12,2),
  'clôture réelle = épargne prévue une fois remboursé');

select * from finish();
rollback;
