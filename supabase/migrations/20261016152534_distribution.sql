-- Lot 5 : page Distribution (historique des clôtures + Sankey).
--
-- Chaque clôture garde de quoi reconstituer ses flux : solde du courant avant
-- et après, et le lien vers les transactions qu'elle a réglées ou créées.

alter table public.monthly_settlements
  add column opening_balance numeric(12,2),
  add column closing_balance numeric(12,2);

alter table public.transactions
  add column settlement_id uuid,
  add constraint transactions_settlement_id_user_id_fkey
    foreign key (settlement_id, user_id)
    references public.monthly_settlements (id, user_id)
    on delete set null (settlement_id);
create index transactions_settlement on public.transactions (settlement_id);

-- ---------------------------------------------------------------------------
-- close_month : identique au lot 2, plus le suivi ci-dessus
-- ---------------------------------------------------------------------------
create or replace function public.close_month(
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
  v_opening numeric;
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
  v_opening := v_courant;

  -- 1. Dépenses de M (et d'avant, ex. prélèvement tardif), nettes des revenus
  --    saisis en cours de mois, hors budget inclus.
  with settled as (
    update public.transactions
    set settled = true, settlement_id = v_settlement
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

  -- Transactions créées par cette clôture (salaire, compte commun, épargne).
  update public.transactions
  set settlement_id = v_settlement
  where user_id = v_user and settlement_id is null and created_at = now();

  -- 5. Clôture de M, ouverture de M+1.
  update public.monthly_settlements
  set status = 'settled',
      total_expenses = v_expenses,
      total_savings = v_savings,
      special_month = p_special_month,
      opening_balance = v_opening,
      closing_balance = (select balance from public.accounts where id = v_courant_id)
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
-- Flux d'une clôture (Sankey)
-- ---------------------------------------------------------------------------
-- Une ligne par flux d'une clôture : entrées (in) = sorties (out).
--   in  : solde de départ, salaire, autres revenus du mois, découvert final
--   out : dépenses par catégorie, compte commun, épargne par projet,
--         courant restant, découvert de départ comblé
-- Le salaire et le compte commun sont ceux de M+1 (créés par la clôture) :
-- on les distingue des revenus / dépenses du mois par leur mois > M.
create view public.settlement_flows
with (security_invoker = true)
as
select s.id as settlement_id, s.user_id, s.month, f.side, f.kind, f.label,
       f.amount::numeric(12,2) as amount
from public.monthly_settlements s
cross join lateral (
  select 'in' as side, 'opening' as kind, 'Solde de départ' as label,
         greatest(s.opening_balance, 0) as amount
  union all
  select 'in', 'salary', 'Salaire', coalesce(sum(t.amount), 0)
  from public.transactions t
  where t.settlement_id = s.id and t.type = 'revenu' and t.month > s.month
  union all
  select 'in', 'income', 'Autres revenus', coalesce(sum(t.amount), 0)
  from public.transactions t
  where t.settlement_id = s.id and t.type = 'revenu' and t.month <= s.month
  union all
  select 'in', 'overdraft', 'Découvert', greatest(-s.closing_balance, 0)
  union all
  select 'out', 'expense', coalesce(t.category, 'Sans catégorie'), sum(t.amount)
  from public.transactions t
  where t.settlement_id = s.id and t.type = 'depense' and t.month <= s.month
  group by t.category
  union all
  select 'out', 'shared', 'Compte commun', coalesce(sum(t.amount), 0)
  from public.transactions t
  where t.settlement_id = s.id and t.type = 'depense' and t.month > s.month
  union all
  select 'out', 'savings', coalesce(p.name, 'Épargne'), sum(t.amount)
  from public.transactions t
  left join public.savings_projects p on p.id = t.savings_project_id
  where t.settlement_id = s.id and t.type = 'transfert_epargne'
  group by p.name
  union all
  select 'out', 'remaining', 'Courant restant', greatest(s.closing_balance, 0)
  union all
  select 'out', 'opening_overdraft', 'Découvert comblé',
         greatest(-s.opening_balance, 0)
) f
where s.status = 'settled'
  and s.opening_balance is not null
  and f.amount > 0;

revoke all on public.settlement_flows from anon;
grant select on public.settlement_flows to authenticated;
