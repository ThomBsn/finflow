-- Lot 2 : transition, épargne, rééquilibrage, abonnements (spec §3 à §6).
begin;
create extension if not exists pgtap with schema extensions;
select plan(53);

-- Helpers -------------------------------------------------------------------
-- Crée l'utilisateur n avec un courant de départ et octobre 2026 en cours,
-- puis agit en son nom (auth.uid()).
create function pg_temp.new_user(p_n int, p_courant numeric) returns uuid
language plpgsql as $$
declare
  v_id uuid := ('00000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email) values (v_id, 'u' || p_n || '@test.local');
  update public.accounts set balance = p_courant where user_id = v_id and type = 'courant';
  insert into public.monthly_settlements (user_id, month) values (v_id, '2026-10-01');
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
  return v_id;
end;
$$;

create function pg_temp.uid(p_n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid
$$;

create function pg_temp.add(p_n int, p_amount numeric, p_type public.transaction_type default 'depense')
returns void language sql as $$
  insert into public.transactions (user_id, type, amount, category, date)
  values (pg_temp.uid(p_n), p_type, p_amount, 'Courses', '2026-10-10')
$$;

create function pg_temp.balance(p_n int, p_type public.account_type) returns numeric
language sql as $$
  select balance from public.accounts where user_id = pg_temp.uid(p_n) and type = p_type
$$;

create function pg_temp.saved(p_n int, p_name text) returns numeric language sql as $$
  select current_amount from public.savings_projects
  where user_id = pg_temp.uid(p_n) and name = p_name
$$;

create function pg_temp.project(p_n int, p_name text, p_pct numeric, p_target numeric default null)
returns uuid language sql as $$
  insert into public.savings_projects (user_id, name, percentage, target_amount)
  values (pg_temp.uid(p_n), p_name, p_pct, p_target)
  returning id
$$;

create function pg_temp.settlement(p_n int, p_month date) returns text language sql as $$
  select (status, total_expenses, total_savings, special_month)::text
  from public.monthly_settlements where user_id = pg_temp.uid(p_n) and month = p_month
$$;

-- §3 Exemple chiffré : 350 · dépenses 1 400 · salaire 2 500 · commun 600 ---
select pg_temp.new_user(1, 350);
select pg_temp.add(1, 1000);
select pg_temp.add(1, 400);
select public.close_month('2026-10-01', 2500, 600);

select is(pg_temp.balance(1, 'courant'), 200.00, '§3 courant final = 200');
select is(pg_temp.balance(1, 'epargne'), 650.00, '§3 épargne = 650');
select is(pg_temp.saved(1, 'Épargne générale'), 650.00, '§3 sans pourcentages, tout va à Épargne générale');
select is(pg_temp.settlement(1, '2026-10-01'), '(settled,1400.00,650.00,f)', '§3 octobre clôturé avec totaux');
select is(
  (select (status, salary, shared_transfer)::text from public.monthly_settlements
   where user_id = pg_temp.uid(1) and month = '2026-11-01'),
  '(pending,2500.00,600.00)', '§3 novembre ouvert');
select is(
  (select count(*)::int from public.transactions
   where user_id = pg_temp.uid(1) and month = '2026-10-01' and not settled),
  0, '§3 dépenses d''octobre réglées');
select ok(
  exists (select 1 from public.transactions
          where user_id = pg_temp.uid(1) and type = 'revenu' and amount = 2500
            and date = '2026-11-01' and settled),
  '§3 salaire de novembre crédité');
select ok(
  exists (select 1 from public.transactions
          where user_id = pg_temp.uid(1) and type = 'depense' and amount = 600
            and category = 'Frais externes' and hors_budget and settled
            and date = '2026-11-01'),
  '§3 virement commun de novembre hors budget');
select throws_ok(
  $$select public.close_month('2026-10-01', 2500, 600)$$,
  'FF001', null, '§3 double clic : octobre déjà clôturé, refusé');

-- §3 Exemple négatif : 100 · dépenses 2 300 ----------------------------------
select pg_temp.new_user(2, 100);
select pg_temp.add(2, 2300);
select public.close_month('2026-10-01', 2500, 600);

select is(pg_temp.balance(2, 'courant'), -300.00, 'négatif : courant final = −300');
select is(pg_temp.balance(2, 'epargne'), 0.00, 'négatif : aucune épargne');
select is(pg_temp.settlement(2, '2026-10-01'), '(settled,2300.00,0.00,f)', 'négatif : total_savings = 0');

-- §8 Mois particulier : étape 4 sautée ---------------------------------------
select pg_temp.new_user(3, 350);
select pg_temp.add(3, 1400);
select public.close_month('2026-10-01', 2500, 600, true);

select is(pg_temp.balance(3, 'courant'), 850.00, 'mois particulier : le surplus reste sur le courant');
select is(pg_temp.balance(3, 'epargne'), 0.00, 'mois particulier : aucune épargne');
select is(pg_temp.settlement(3, '2026-10-01'), '(settled,1400.00,0.00,t)', 'mois particulier enregistré');

-- Revenus en cours de mois : déduits des dépenses ----------------------------
select pg_temp.new_user(4, 350);
select pg_temp.add(4, 1400);
select pg_temp.add(4, 100, 'revenu');
select public.close_month('2026-10-01', 2500, 600);

select is(pg_temp.settlement(4, '2026-10-01'), '(settled,1300.00,750.00,f)', 'revenu déduit des dépenses');
select is(pg_temp.balance(4, 'courant'), 200.00, 'revenu : courant final = 200');

-- Garde-fous ------------------------------------------------------------------
select pg_temp.new_user(5, 0);
insert into public.monthly_settlements (user_id, month, status)
values (pg_temp.uid(5), '2026-11-01', 'settled');
select throws_ok($$select public.close_month('2026-10-01', 2500, 600)$$,
  'FF002', null, 'mois suivant déjà existant : refusé');
select throws_ok($$select public.close_month('2026-12-01', 2500, 600)$$,
  'FF001', null, 'mois pas en cours : refusé');
select throws_ok($$select public.close_month('2026-10-01', -1, 600)$$,
  'FF004', null, 'salaire négatif : refusé');

-- §5 Distribution automatique + cascade --------------------------------------
-- 1 000 € : Vacances 50 % (sans plafond), Voiture 30 % (objectif 100).
select pg_temp.new_user(6, 0);
select pg_temp.project(6, 'Vacances', 50);
select pg_temp.project(6, 'Voiture', 30, 100);
select private.distribute_savings(pg_temp.uid(6), 1000, 'automatique');

select is(pg_temp.saved(6, 'Vacances'), 500.00, 'auto : Vacances reçoit 50 %');
select is(pg_temp.saved(6, 'Voiture'), 100.00, 'auto : Voiture plafonnée à son objectif');
select is(pg_temp.saved(6, 'Fond de sécurité'), 200.00, 'cascade : excédent de Voiture → Fond de sécurité');
select is(pg_temp.saved(6, 'Épargne générale'), 200.00, 'complément à 100 % → Épargne générale');
select is(pg_temp.balance(6, 'courant'), -1000.00, 'courant débité du montant épargné');
select is(pg_temp.balance(6, 'epargne'),
  (select sum(current_amount) from public.savings_projects where user_id = pg_temp.uid(6)),
  'invariant : compte épargne = Σ projets');
select is(
  (select count(*)::int from public.transactions
   where user_id = pg_temp.uid(6) and type = 'transfert_epargne'
     and distribution_mode = 'automatique' and settled),
  4, 'un transfert d''épargne par projet crédité');

-- Fond de sécurité plein → Épargne générale.
select pg_temp.new_user(7, 0);
update public.savings_projects set target_amount = 50, current_amount = 50
where user_id = pg_temp.uid(7) and is_safety_fund;
update public.accounts set balance = 50 where user_id = pg_temp.uid(7) and type = 'epargne';
select pg_temp.project(7, 'Voiture', 30, 100);
select private.distribute_savings(pg_temp.uid(7), 1000, 'automatique');

select is(pg_temp.saved(7, 'Fond de sécurité'), 50.00, 'cascade : Fond plein, inchangé');
select is(pg_temp.saved(7, 'Épargne générale'), 900.00, 'cascade : Fond plein → Épargne générale');

-- Reliquat d'arrondi → Épargne générale.
select pg_temp.new_user(8, 0);
select pg_temp.project(8, 'A', 33.33);
select pg_temp.project(8, 'B', 33.33);
select pg_temp.project(8, 'C', 33.34);
select private.distribute_savings(pg_temp.uid(8), 100.01, 'automatique');

select is(pg_temp.saved(8, 'A'), 33.33, 'arrondi : part tronquée au centime');
select is(pg_temp.saved(8, 'C'), 33.34, 'arrondi : part de C');
select is(pg_temp.saved(8, 'Épargne générale'), 0.01, 'reliquat d''arrondi → Épargne générale');
select is(pg_temp.balance(8, 'epargne'), 100.01, 'arrondi : rien de perdu');

-- Mode précis + cascade.
select pg_temp.new_user(9, 0);
select pg_temp.project(9, 'Vacances', 0, 100);
select private.distribute_savings(pg_temp.uid(9), 500, 'precis',
  (select id from public.savings_projects where user_id = pg_temp.uid(9) and name = 'Vacances'));

select is(pg_temp.saved(9, 'Vacances'), 100.00, 'précis : projet rempli jusqu''à son objectif');
select is(pg_temp.saved(9, 'Fond de sécurité'), 400.00, 'précis : excédent → Fond de sécurité');
select throws_ok(
  format($$select private.distribute_savings(%L, 10, 'precis', %L)$$,
         pg_temp.uid(9),
         (select id from public.savings_projects where user_id = pg_temp.uid(8) and name = 'A')),
  'FF003', null, 'précis : projet d''un autre utilisateur refusé');

-- §4 Rééquilibrage --------------------------------------------------------------
-- Fond insuffisant : −300, Fond 200 → retrait partiel.
select pg_temp.new_user(10, -300);
update public.savings_projects set current_amount = 200
where user_id = pg_temp.uid(10) and is_safety_fund;
update public.accounts set balance = 200 where user_id = pg_temp.uid(10) and type = 'epargne';
select set_config('test.r', public.rebalance_from_safety_fund()::text, true);

select is((current_setting('test.r')::jsonb ->> 'withdrawn')::numeric, 200.00, 'Fond insuffisant : retrait de tout le Fond');
select is((current_setting('test.r')::jsonb ->> 'remaining')::numeric, 100.00, 'Fond insuffisant : reste à couvrir = 100');
select is(pg_temp.balance(10, 'courant'), -100.00, 'Fond insuffisant : courant = −100');
select is(pg_temp.saved(10, 'Fond de sécurité'), 0.00, 'Fond insuffisant : Fond vidé');

-- Fond suffisant : −300, Fond 1 000 → courant à 0.
select pg_temp.new_user(11, -300);
update public.savings_projects set current_amount = 1000
where user_id = pg_temp.uid(11) and is_safety_fund;
update public.accounts set balance = 1000 where user_id = pg_temp.uid(11) and type = 'epargne';
select set_config('test.r', public.rebalance_from_safety_fund()::text, true);

select is(pg_temp.balance(11, 'courant'), 0.00, 'rééquilibrage : courant ramené à 0');
select is(pg_temp.balance(11, 'epargne'), 700.00, 'rééquilibrage : épargne débitée');
select is((current_setting('test.r')::jsonb ->> 'remaining')::numeric, 0::numeric, 'rééquilibrage : rien à couvrir');

-- Courant positif : rien à faire.
select pg_temp.new_user(12, 50);
select is((public.rebalance_from_safety_fund() ->> 'withdrawn')::numeric, 0::numeric, 'courant positif : aucun retrait');

-- §6 Prélèvements d'abonnements -------------------------------------------------
-- billing_day 31 en février 2027 → le 28.
select pg_temp.new_user(13, 0);
insert into public.subscriptions (user_id, name, amount, billing_day, created_at)
values (pg_temp.uid(13), 'Streaming', 12.99, 31, '2027-02-01');

-- La génération traite tous les utilisateurs : on ne compte que ceux du test.
select private.generate_subscription_charges('2027-02-27');
select is((select count(*)::int from public.transactions where user_id = pg_temp.uid(13) and subscription_id is not null), 0, 'abonnement : pas avant le jour de prélèvement');
select private.generate_subscription_charges('2027-02-28');
select is((select count(*)::int from public.transactions where user_id = pg_temp.uid(13) and subscription_id is not null), 1, 'abonnement : 31 → dernier jour de février');
select private.generate_subscription_charges('2027-02-28');
select is((select count(*)::int from public.transactions where user_id = pg_temp.uid(13) and subscription_id is not null), 1, 'abonnement : rejeu sans doublon');
select is(
  (select (date, amount, category, settled)::text from public.transactions
   where subscription_id is not null and user_id = pg_temp.uid(13)),
  '(2027-02-28,12.99,Abonnements,f)', 'abonnement : dépense non réglée du 28/02');

-- Prélèvement d'un mois déjà clôturé : réglé à la clôture suivante.
select pg_temp.new_user(14, 0);
update public.monthly_settlements set status = 'settled' where user_id = pg_temp.uid(14);
insert into public.monthly_settlements (user_id, month) values (pg_temp.uid(14), '2026-11-01');
insert into public.subscriptions (user_id, name, amount, billing_day, created_at)
values (pg_temp.uid(14), 'Salle de sport', 15, 31, '2026-10-01');
select private.generate_subscription_charges('2026-11-02');

select ok(
  exists (select 1 from public.transactions
          where user_id = pg_temp.uid(14) and subscription_id is not null and date = '2026-10-31'),
  'abonnement : prélèvement manqué d''octobre rattrapé en novembre');
select public.close_month('2026-11-01', 0, 0, true);
select is(pg_temp.settlement(14, '2026-11-01'), '(settled,15.00,0.00,t)',
  'abonnement : prélèvement d''un mois clôturé réglé à la clôture suivante');

-- Droits d'exécution --------------------------------------------------------------
select ok(has_function_privilege('authenticated', 'public.close_month(date,numeric,numeric,boolean)', 'execute'),
  'close_month appelable par un utilisateur connecté');
select ok(not has_function_privilege('anon', 'public.close_month(date,numeric,numeric,boolean)', 'execute'),
  'close_month interdit sans connexion');
select ok(not has_schema_privilege('authenticated', 'private', 'usage'),
  'fonctions internes inaccessibles au client');

select * from finish();
rollback;
