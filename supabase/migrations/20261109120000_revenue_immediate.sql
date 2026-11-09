-- Un revenu saisi (remboursement, prime…) est crédité sur le courant dès sa
-- saisie, comme une dépense en débit immédiat : `immediate` toujours vrai
-- pour un revenu. La clôture le compte toujours en déduction des dépenses du
-- mois, sans le recréditer. immediate_expenses et le v_immediate de la
-- clôture deviennent nets (débits − revenus immédiats).

alter table public.transactions drop constraint transactions_immediate_check;
alter table public.transactions
  add constraint transactions_immediate_check
    check (not immediate or type in ('depense', 'revenu'));

-- Mouvement du courant signé : − pour une dépense, + pour un revenu.
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
    update public.accounts
    set balance = balance + case when old.type = 'revenu' then -old.amount else old.amount end
    where id = old.account_id;
  end if;

  if tg_op in ('INSERT', 'UPDATE') and new.immediate and not new.settled then
    update public.accounts
    set balance = balance + case when new.type = 'revenu' then new.amount else -new.amount end
    where id = new.account_id;
  end if;
  return null;
end;
$$;

-- Un revenu saisi est toujours immédiat.
create function public.revenue_always_immediate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.type = 'revenu' and not new.settled then
    new.immediate := true;
  end if;
  return new;
end;
$$;

create trigger transactions_revenue_immediate
  before insert or update on public.transactions
  for each row execute function public.revenue_always_immediate();

-- Revenus déjà saisis, pas encore réglés : crédités maintenant (le trigger
-- ci-dessus et apply_immediate_expense s'en chargent).
update public.transactions
set immediate = true
where type = 'revenu' and not settled and not immediate;

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

  -- 1. Transactions de mois de débit M :
  --    a. immédiates (débits, revenus) : déjà passées sur le courant ;
  --       v_immediate est net (dépenses − revenus) ;
  with settled as (
    update public.transactions
    set settled = true, settlement_id = v_settlement, deducted = true
    where user_id = v_user and month = p_month and not settled
      and type in ('depense', 'revenu') and immediate
    returning type, amount
  )
  select coalesce(sum(case when type = 'depense' then amount else -amount end), 0)
  into v_immediate
  from settled;

  --    b. les autres (hors budget et échelonnées comprises, en entier),
  --       nettes des revenus saisis en cours de mois.
  with settled as (
    update public.transactions
    set settled = true, settlement_id = v_settlement, deducted = true
    where user_id = v_user and month = p_month and not settled
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
    values (v_user, v_next, 'salaire', p_salary, 'Salaire', v_courant_id, true);
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
  (c.balance + k.salary - k.shared_transfer - u.net + h.pending - s.safety_margin)::numeric(12,2)
    as projected_savings,
  (c.balance + k.salary - k.shared_transfer - u.net + h.pending - s.safety_margin
   - r.remaining)::numeric(12,2)
    as projected_savings_budgets,
  u.immediate as immediate_expenses,
  u.hors_budget as hors_budget_expenses,
  h.pending as hors_budget_pending
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
             filter (where not t.immediate), 0)::numeric(12,2) as net,
    coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end)
             filter (where t.immediate), 0)::numeric(12,2) as immediate,
    coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end)
             filter (where t.hors_budget), 0)::numeric(12,2) as hors_budget
  from public.transactions t
  where t.user_id = m.user_id
    and t.month = m.month
    and not t.settled
    and t.type in ('depense', 'revenu')
) u
cross join lateral (
  -- Hors budget pas encore remboursés (débit différé seulement : un débit
  -- immédiat est déjà sorti du courant).
  select coalesce(sum(greatest(t.amount - coalesce((
           select sum(x.amount) from public.transactions x where x.reimburses_id = t.id
         ), 0), 0)), 0)::numeric(12,2) as pending
  from public.transactions t
  where t.user_id = m.user_id
    and t.month = m.month
    and not t.settled
    and t.type = 'depense'
    and t.hors_budget
    and not t.immediate
) h
cross join lateral (
  select coalesce(sum(greatest(b.remaining, b.reserved, 0)), 0)::numeric(12,2) as remaining
  from public.budget_status_current_month b
  where b.user_id = m.user_id and not b.hors_budget
) r
where m.status = 'pending';
