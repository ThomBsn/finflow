-- Échelonnement = étalement sur le budget seulement (révise ADR 008).
--
-- La dépense est faite une fois : elle sort du courant en entier à la
-- clôture de son mois de débit. Seul le budget de sa catégorie n'en compte
-- qu'une mensualité par mois. Les mensualités débitées une à une
-- (installment_charges) disparaissent ; les dépenses réglées sous cette
-- règle sont corrigées : le reste est débité du courant, et les clôtures
-- concernées (totaux, soldes) sont recalées comme si la dépense était sortie
-- en entier à sa clôture.

-- ---------------------------------------------------------------------------
-- Correction des dépenses réglées partiellement
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select t.id, t.user_id, t.amount, t.settlement_id, s.month as settled_month
    from public.transactions t
    join public.monthly_settlements s on s.id = t.settlement_id
    where t.settled and t.deducted = false and not t.hors_budget
      and exists (select 1 from public.installment_plans p where p.transaction_id = t.id)
  loop
    -- Totaux : la dépense entière dans sa clôture, plus aucune mensualité ailleurs.
    update public.monthly_settlements s
    set total_expenses = s.total_expenses - c.amount
    from (
      select settlement_id, sum(amount) as amount
      from public.installment_charges
      where transaction_id = r.id and settlement_id is not null
      group by settlement_id
    ) c
    where s.id = c.settlement_id;
    update public.monthly_settlements
    set total_expenses = total_expenses + r.amount
    where id = r.settlement_id;

    -- Soldes : chaque clôture depuis celle de la dépense avait gardé sur le
    -- courant la part pas encore débitée.
    update public.monthly_settlements s
    set closing_balance = s.closing_balance - (r.amount - coalesce((
          select sum(c.amount)
          from public.installment_charges c
          join public.monthly_settlements cs on cs.id = c.settlement_id
          where c.transaction_id = r.id and cs.month <= s.month), 0)),
        opening_balance = case when s.month > r.settled_month
          then s.opening_balance - (r.amount - coalesce((
            select sum(c.amount)
            from public.installment_charges c
            join public.monthly_settlements cs on cs.id = c.settlement_id
            where c.transaction_id = r.id and cs.month < s.month), 0))
          else s.opening_balance end
    where s.user_id = r.user_id and s.status = 'settled' and s.month >= r.settled_month;

    update public.accounts
    set balance = balance - (r.amount - coalesce((
          select sum(amount) from public.installment_charges
          where transaction_id = r.id and settlement_id is not null), 0))
    where user_id = r.user_id and type = 'courant';

    update public.transactions set deducted = true where id = r.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- close_month : l'échelonnée est déduite en entier
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
  v_immediate numeric;
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

  -- 1. Transactions de mois de débit ≤ M :
  --    a. débit immédiat : déjà sorties du courant ;
  with settled as (
    update public.transactions
    set settled = true, settlement_id = v_settlement, deducted = true
    where user_id = v_user and month <= p_month and not settled
      and type in ('depense', 'revenu') and immediate
    returning amount
  )
  select coalesce(sum(amount), 0) into v_immediate from settled;

  --    b. hors budget : figées, sans être déduites ;
  update public.transactions
  set settled = true, settlement_id = v_settlement, deducted = false
  where user_id = v_user and month <= p_month and not settled
    and type in ('depense', 'revenu') and hors_budget;

  --    c. les autres (échelonnées comprises, en entier), nettes des revenus.
  with settled as (
    update public.transactions
    set settled = true, settlement_id = v_settlement, deducted = true
    where user_id = v_user and month <= p_month and not settled
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
    insert into public.transactions (user_id, date, type, amount, label, account_id, settled)
    values (v_user, v_next, 'transfert', p_shared_transfer, 'Virement compte commun',
            v_courant_id, true);
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
      total_expenses = v_expenses + v_immediate,
      total_savings = v_savings,
      special_month = p_special_month,
      opening_balance = v_opening + v_immediate,
      closing_balance = (select balance from public.accounts where id = v_courant_id)
  where id = v_settlement;

  insert into public.monthly_settlements (user_id, month, salary, shared_transfer)
  values (v_user, v_next, p_salary, p_shared_transfer);

  return jsonb_build_object(
    'month', p_month,
    'total_expenses', v_expenses + v_immediate,
    'total_savings', v_savings,
    'courant', (select balance from public.accounts where id = v_courant_id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Résumé du mois : l'échelonnée compte en entier
-- ---------------------------------------------------------------------------
create or replace view public.current_month_summary
with (security_invoker = true)
as
select
  m.user_id,
  m.month,
  c.balance as courant,
  e.balance as epargne,
  u.net as unsettled_expenses,
  s.safety_margin,
  k.salary as suggested_salary,
  k.shared_transfer as suggested_shared_transfer,
  r.remaining as budget_remaining,
  (c.balance + k.salary - k.shared_transfer - u.net - s.safety_margin)::numeric(12,2)
    as projected_savings,
  (c.balance + k.salary - k.shared_transfer - u.net - s.safety_margin - r.remaining)::numeric(12,2)
    as projected_savings_budgets,
  u.immediate as immediate_expenses,
  u.hors_budget as hors_budget_expenses
from public.monthly_settlements m
join public.accounts c on c.user_id = m.user_id and c.type = 'courant'
join public.accounts e on e.user_id = m.user_id and e.type = 'epargne'
join public.settings s on s.user_id = m.user_id
cross join lateral (
  select
    coalesce(nullif(s.default_salary, 0), m.salary)::numeric(12,2) as salary,
    coalesce(nullif(s.default_shared_transfer, 0), m.shared_transfer)::numeric(12,2)
      as shared_transfer
) k
cross join lateral (
  select
    coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end)
             filter (where not t.hors_budget and not t.immediate), 0)::numeric(12,2) as net,
    coalesce(sum(t.amount) filter (where t.immediate), 0)::numeric(12,2) as immediate,
    coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end)
             filter (where t.hors_budget), 0)::numeric(12,2) as hors_budget
  from public.transactions t
  where t.user_id = m.user_id
    and t.month <= m.month
    and not t.settled
    and t.type in ('depense', 'revenu')
) u
cross join lateral (
  select coalesce(sum(greatest(b.remaining, b.reserved, 0)), 0)::numeric(12,2) as remaining
  from public.budget_status_current_month b
  where b.user_id = m.user_id and not b.hors_budget
) r
where m.status = 'pending';

-- ---------------------------------------------------------------------------
-- Flux : plus de mensualités débitées à part
-- ---------------------------------------------------------------------------
create or replace view public.settlement_flows
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
  where t.settlement_id = s.id and t.type = 'revenu' and t.month <= s.month and t.deducted
  union all
  select 'in', 'overdraft', 'Découvert', greatest(-s.closing_balance, 0)
  union all
  select 'out', 'expense', coalesce(t.category, 'Sans catégorie'), sum(t.amount)
  from public.transactions t
  where t.settlement_id = s.id and t.type = 'depense' and t.month <= s.month and t.deducted
  group by t.category
  union all
  select 'out', 'shared', 'Compte commun', coalesce(sum(t.amount), 0)
  from public.transactions t
  where t.settlement_id = s.id and t.type = 'transfert'
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

-- ---------------------------------------------------------------------------
-- Échelonnements : vue d'origine, plan modifiable à tout moment
-- ---------------------------------------------------------------------------
drop view public.installment_plans_status;
create view public.installment_plans_status
with (security_invoker = true)
as
select
  p.id,
  p.user_id,
  p.transaction_id,
  t.label,
  t.category,
  t.date,
  t.amount as total_amount,
  p.installments,
  public.installment_share(t.amount, p.installments, 0)::numeric(12,2) as monthly_amount,
  k.i + 1 as current_number,
  greatest(p.installments - (k.i + 1), 0) as remaining_count,
  (case when k.i + 1 >= p.installments then 0
        else t.amount - trunc(t.amount / p.installments, 2) * greatest(k.i + 1, 0)
   end)::numeric(12,2) as remaining_amount
from public.installment_plans p
join public.transactions t on t.id = p.transaction_id and t.user_id = p.user_id
left join public.monthly_settlements m on m.user_id = p.user_id and m.status = 'pending'
cross join lateral (
  select public.month_index(t.month, coalesce(m.month, t.month)) as i
) k;

revoke all on public.installment_plans_status from anon;
grant select on public.installment_plans_status to authenticated;

-- Seule une dépense comptée dans un budget s'étale (débit immédiat compris :
-- l'étalement ne touche que le budget).
create or replace function public.check_installment_plan()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.transactions
    where id = new.transaction_id and user_id = new.user_id
      and type = 'depense' and category is not null and not hors_budget
  ) then
    raise exception 'Seule une dépense comptée dans un budget peut être échelonnée'
      using errcode = 'FF004';
  end if;
  return new;
end;
$$;

drop trigger installment_plans_check on public.installment_plans;
create trigger installment_plans_check
  before insert or update on public.installment_plans
  for each row execute function public.check_installment_plan();

create or replace function public.apply_immediate_expense()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and (old.settled or new.settled) then
    return null;
  end if;

  if tg_op in ('UPDATE', 'DELETE') and old.immediate and not old.settled then
    update public.accounts set balance = balance + old.amount where id = old.account_id;
  end if;

  if tg_op in ('INSERT', 'UPDATE') and new.immediate and not new.settled then
    update public.accounts set balance = balance - new.amount where id = new.account_id;
  end if;
  return null;
end;
$$;

drop function public.installments_due(uuid, date);
drop table public.installment_charges;
