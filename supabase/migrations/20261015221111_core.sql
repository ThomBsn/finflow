-- Lot 2 : cœur métier (docs/spec-metier.md §3 à §6).
--
-- Seules ces fonctions modifient soldes, montants épargnés et `settled`.
-- Fonctions internes dans le schéma `private`, non exposé par l'API.
-- Codes d'erreur métier (SQLSTATE) :
--   FF001 mois à clôturer pas en cours   FF002 mois suivant déjà existant
--   FF003 projet d'épargne inconnu       FF004 montant invalide
--
-- Sens des transferts : transfert_epargne courant → épargne,
-- retrait_epargne épargne → courant (account_id → target_account_id).

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Épargne (§5)
-- ---------------------------------------------------------------------------

-- Crédite un projet dans la limite de son objectif ; renvoie le reste non
-- crédité. Ne touche pas aux soldes des comptes (voir distribute_savings).
create function private.credit_project(
  p_user uuid,
  p_project uuid,
  p_amount numeric,
  p_mode public.distribution_mode,
  p_date date
)
returns numeric
language plpgsql
set search_path = ''
as $$
declare
  v_name text;
  v_target numeric;
  v_current numeric;
  v_credit numeric;
begin
  if p_amount <= 0 then
    return 0;
  end if;

  select name, target_amount, current_amount
  into v_name, v_target, v_current
  from public.savings_projects
  where id = p_project and user_id = p_user
  for update;
  if not found then
    raise exception 'Projet d''épargne inconnu' using errcode = 'FF003';
  end if;

  v_credit := case
    when v_target is null then p_amount
    else least(p_amount, greatest(v_target - v_current, 0))
  end;

  if v_credit > 0 then
    update public.savings_projects
    set current_amount = current_amount + v_credit
    where id = p_project;

    insert into public.transactions (
      user_id, date, type, amount, label, account_id, target_account_id,
      settled, savings_project_id, distribution_mode
    )
    select p_user, p_date, 'transfert_epargne', v_credit, v_name, c.id, e.id,
           true, p_project, p_mode
    from public.accounts c, public.accounts e
    where c.user_id = p_user and c.type = 'courant'
      and e.user_id = p_user and e.type = 'epargne';
  end if;

  return p_amount - v_credit;
end;
$$;

-- Vire p_amount du courant vers l'épargne et le répartit entre les projets :
-- - automatique : percentage de chaque projet (tronqué au centime) ;
-- - precis : tout sur p_project_id.
-- Débordement d'un projet plein → Fond de sécurité → Épargne générale, qui
-- reçoit aussi le complément à 100 % et le reliquat d'arrondi.
create function private.distribute_savings(
  p_user uuid,
  p_amount numeric,
  p_mode public.distribution_mode,
  p_project_id uuid default null,
  p_date date default current_date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_project record;
  v_share numeric;
  v_allocated numeric := 0;
  v_overflow numeric := 0;
  v_default uuid;
  v_safety uuid;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Montant d''épargne invalide' using errcode = 'FF004';
  end if;

  select id into v_default
  from public.savings_projects where user_id = p_user and is_default;
  select id into v_safety
  from public.savings_projects where user_id = p_user and is_safety_fund;

  if p_mode = 'precis' then
    if p_project_id is null then
      raise exception 'Projet d''épargne requis en mode précis' using errcode = 'FF003';
    end if;
    v_overflow := private.credit_project(p_user, p_project_id, p_amount, p_mode, p_date);
    v_allocated := p_amount;
  else
    for v_project in
      select id, percentage
      from public.savings_projects
      where user_id = p_user and percentage > 0
      order by created_at, id
    loop
      v_share := trunc(p_amount * v_project.percentage / 100, 2);
      v_allocated := v_allocated + v_share;
      v_overflow := v_overflow
        + private.credit_project(p_user, v_project.id, v_share, p_mode, p_date);
    end loop;
  end if;

  v_overflow := private.credit_project(p_user, v_safety, v_overflow, p_mode, p_date);
  perform private.credit_project(
    p_user, v_default, v_overflow + (p_amount - v_allocated), p_mode, p_date
  );

  update public.accounts set balance = balance - p_amount
  where user_id = p_user and type = 'courant';
  update public.accounts set balance = balance + p_amount
  where user_id = p_user and type = 'epargne';
end;
$$;

-- ---------------------------------------------------------------------------
-- Transition « Passer au mois suivant » (§3)
-- ---------------------------------------------------------------------------
create function public.close_month(
  p_month date,
  p_salary numeric,
  p_shared_transfer numeric,
  p_special_month boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_next date := (p_month + interval '1 month')::date;
  v_settlement uuid;
  v_courant_id uuid;
  v_courant numeric;
  v_margin numeric;
  v_expenses numeric;
  v_savings numeric := 0;
begin
  if v_user is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;
  if p_salary < 0 or p_shared_transfer < 0 then
    raise exception 'Montant invalide' using errcode = 'FF004';
  end if;

  -- Le mois passé en paramètre doit être le mois en cours : un second appel
  -- (double clic) est refusé au lieu de clôturer aussi le mois suivant.
  select id into v_settlement
  from public.monthly_settlements
  where user_id = v_user and month = p_month and status = 'pending'
  for update;
  if not found then
    raise exception 'Le mois % n''est pas en cours', to_char(p_month, 'MM/YYYY')
      using errcode = 'FF001';
  end if;
  if exists (
    select 1 from public.monthly_settlements
    where user_id = v_user and month = v_next
  ) then
    raise exception 'Le mois % existe déjà', to_char(v_next, 'MM/YYYY')
      using errcode = 'FF002';
  end if;

  select id, balance into v_courant_id, v_courant
  from public.accounts
  where user_id = v_user and type = 'courant'
  for update;
  select safety_margin into v_margin
  from public.settings where user_id = v_user;

  -- 1. Dépenses de M (et d'avant, ex. prélèvement tardif), nettes des revenus
  --    saisis en cours de mois, hors budget inclus.
  with settled as (
    update public.transactions
    set settled = true
    where user_id = v_user
      and month <= p_month
      and not settled
      and type in ('depense', 'revenu')
    returning type, amount
  )
  select coalesce(sum(case when type = 'depense' then amount else -amount end), 0)
  into v_expenses
  from settled;
  v_courant := v_courant - v_expenses;

  -- 2. Salaire de M+1.
  if p_salary > 0 then
    insert into public.transactions (user_id, date, type, amount, label, account_id, settled)
    values (v_user, v_next, 'revenu', p_salary, 'Salaire', v_courant_id, true);
    v_courant := v_courant + p_salary;
  end if;

  -- 3. Virement compte commun de M+1 (exclu de total_expenses).
  if p_shared_transfer > 0 then
    insert into public.transactions (
      user_id, date, type, amount, label, category, account_id, hors_budget, settled
    )
    values (
      v_user, v_next, 'depense', p_shared_transfer, 'Virement compte commun',
      'Frais externes', v_courant_id, true, true
    );
    v_courant := v_courant - p_shared_transfer;
  end if;

  update public.accounts set balance = v_courant where id = v_courant_id;

  -- 4. Épargne : tout ce qui dépasse la marge de sécurité.
  if not p_special_month and v_courant > v_margin then
    v_savings := v_courant - v_margin;
    perform private.distribute_savings(v_user, v_savings, 'automatique', null, v_next);
  end if;

  -- 5. Clôture de M, ouverture de M+1.
  update public.monthly_settlements
  set status = 'settled',
      total_expenses = v_expenses,
      total_savings = v_savings,
      special_month = p_special_month
  where id = v_settlement;

  insert into public.monthly_settlements (user_id, month, salary, shared_transfer)
  values (v_user, v_next, p_salary, p_shared_transfer);

  return jsonb_build_object(
    'month', p_month,
    'total_expenses', v_expenses,
    'total_savings', v_savings,
    'courant', (select balance from public.accounts where id = v_courant_id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Rééquilibrage depuis le Fond de sécurité (§4)
-- ---------------------------------------------------------------------------
-- Ramène le courant vers 0 ; retrait partiel si le Fond ne suffit pas.
create function public.rebalance_from_safety_fund()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_courant_id uuid;
  v_epargne_id uuid;
  v_balance numeric;
  v_safety uuid;
  v_available numeric;
  v_withdrawn numeric := 0;
begin
  if v_user is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;

  select id, balance into v_courant_id, v_balance
  from public.accounts where user_id = v_user and type = 'courant'
  for update;

  if v_balance < 0 then
    select id into v_epargne_id
    from public.accounts where user_id = v_user and type = 'epargne'
    for update;
    select id, current_amount into v_safety, v_available
    from public.savings_projects where user_id = v_user and is_safety_fund
    for update;

    v_withdrawn := least(-v_balance, v_available);

    if v_withdrawn > 0 then
      update public.savings_projects
      set current_amount = current_amount - v_withdrawn where id = v_safety;
      update public.accounts set balance = balance - v_withdrawn where id = v_epargne_id;
      update public.accounts set balance = balance + v_withdrawn where id = v_courant_id;

      insert into public.transactions (
        user_id, type, amount, label, account_id, target_account_id,
        settled, savings_project_id
      )
      values (
        v_user, 'retrait_epargne', v_withdrawn, 'Rééquilibrage', v_epargne_id,
        v_courant_id, true, v_safety
      );
    end if;
  end if;

  return jsonb_build_object(
    'withdrawn', v_withdrawn,
    'remaining', greatest(-v_balance - v_withdrawn, 0)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Prélèvements des abonnements (§6), appelée chaque jour par pg_cron
-- ---------------------------------------------------------------------------
-- Pour tous les utilisateurs : crée les prélèvements dus du mois de p_date
-- et du mois précédent (rattrape un passage manqué en fin de mois). Jamais
-- avant la création de l'abonnement ; idempotent grâce à l'index unique
-- (subscription_id, date). Renvoie le nombre de prélèvements créés.
create function private.generate_subscription_charges(p_date date default current_date)
returns int
language plpgsql
set search_path = ''
as $$
declare
  v_count int;
begin
  with months as (
    select date_trunc('month', p_date::timestamp - interval '1 month')::date as first_day
    union all
    select date_trunc('month', p_date::timestamp)::date
  ),
  due as (
    select s.id, s.user_id, s.name, s.amount, s.created_at,
           m.first_day + least(
             s.billing_day,
             extract(day from m.first_day + interval '1 month - 1 day')::int
           ) - 1 as charge_date
    from public.subscriptions s
    cross join months m
    where s.active
  )
  insert into public.transactions (user_id, date, type, amount, label, category, subscription_id)
  select user_id, charge_date, 'depense', amount, name, 'Abonnements', id
  from due
  where charge_date <= p_date
    and charge_date >= created_at::date
  on conflict (subscription_id, date) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------------
revoke all on schema private from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

revoke execute on function public.close_month(date, numeric, numeric, boolean) from public, anon;
revoke execute on function public.rebalance_from_safety_fund() from public, anon;
grant execute on function public.close_month(date, numeric, numeric, boolean) to authenticated;
grant execute on function public.rebalance_from_safety_fund() to authenticated;
