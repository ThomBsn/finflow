-- Lot 5 : flux d'une clôture (page Distribution).
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

create function pg_temp.setup(p_n int, p_courant numeric) returns uuid
language plpgsql as $$
declare
  v_id uuid := ('60000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email) values (v_id, 'd' || p_n || '@test.local');
  update public.accounts set balance = p_courant where user_id = v_id and type = 'courant';
  insert into public.monthly_settlements (user_id, month) values (v_id, '2026-10-01');
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
  return v_id;
end;
$$;

-- Flux d'une clôture sous forme « side:label:montant », triés.
create function pg_temp.flows(p_n int) returns text language sql as $$
  select string_agg(format('%s:%s:%s', side, label, amount), ' | ' order by side, label collate "C")
  from public.settlement_flows
  where user_id = ('60000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid
$$;

create function pg_temp.balance(p_n int) returns numeric language sql as $$
  select sum(case side when 'in' then amount else -amount end)
  from public.settlement_flows
  where user_id = ('60000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid
$$;

-- §3 avec un projet à 50 % et un revenu : 350 · 1 000 + 400 − 50 · 2 500 · 600
select pg_temp.setup(1, 350);
insert into public.savings_projects (user_id, name, percentage)
values ('60000000-0000-0000-0000-000000000001', 'Vacances', 50);
insert into public.transactions (user_id, type, amount, category, date) values
  ('60000000-0000-0000-0000-000000000001', 'depense', 1000, 'Courses', '2026-10-05'),
  ('60000000-0000-0000-0000-000000000001', 'depense', 400, 'Loisirs', '2026-10-06'),
  ('60000000-0000-0000-0000-000000000001', 'revenu', 50, 'Courses', '2026-10-07');
select public.close_month('2026-10-01', 2500, 600);

select is(
  (select (opening_balance, closing_balance)::text from public.monthly_settlements
   where user_id = '60000000-0000-0000-0000-000000000001' and month = '2026-10-01'),
  '(350.00,200.00)', 'clôture : soldes avant et après mémorisés');
select is(
  pg_temp.flows(1),
  'in:Autres revenus:50.00 | in:Salaire:2500.00 | in:Solde de départ:350.00 | '
  'out:Compte commun:600.00 | out:Courant restant:200.00 | out:Courses:1000.00 | '
  'out:Loisirs:400.00 | out:Vacances:350.00 | out:Épargne générale:350.00',
  'flux : revenus, dépenses par catégorie, commun, épargne par projet, reste');
select is(pg_temp.balance(1), 0.00, 'flux : entrées = sorties');
select is(
  (select count(*)::int from public.transactions
   where user_id = '60000000-0000-0000-0000-000000000001' and settlement_id is null),
  0, 'toutes les transactions sont rattachées à la clôture');

-- Exemple négatif : 100 · 2 300 · 2 500 · 600 → −300
select pg_temp.setup(2, 100);
insert into public.transactions (user_id, type, amount, category, date)
values ('60000000-0000-0000-0000-000000000002', 'depense', 2300, 'Courses', '2026-10-05');
select public.close_month('2026-10-01', 2500, 600);
select is(
  pg_temp.flows(2),
  'in:Découvert:300.00 | in:Salaire:2500.00 | in:Solde de départ:100.00 | '
  'out:Compte commun:600.00 | out:Courses:2300.00',
  'découvert final : apparaît en entrée');
select is(pg_temp.balance(2), 0.00, 'découvert : entrées = sorties');

-- Mois suivant parti d'un découvert : comblé en sortie.
insert into public.transactions (user_id, type, amount, category, date)
values ('60000000-0000-0000-0000-000000000002', 'depense', 100, 'Courses', '2026-11-05');
select public.close_month('2026-11-01', 2500, 600);
select is(
  (select amount from public.settlement_flows
   where user_id = '60000000-0000-0000-0000-000000000002' and month = '2026-11-01'
     and kind = 'opening_overdraft'),
  300.00, 'découvert de départ : comblé en sortie');
select is(
  (select sum(case side when 'in' then amount else -amount end) from public.settlement_flows
   where user_id = '60000000-0000-0000-0000-000000000002' and month = '2026-11-01'),
  0.00, 'mois suivant : entrées = sorties');

-- Isolation --------------------------------------------------------------------
set local role authenticated;
select is(
  (select count(distinct user_id)::int from public.settlement_flows), 1,
  'un utilisateur ne voit que ses propres flux');

select * from finish();
rollback;
