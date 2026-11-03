-- Hors budget ignoré, débit immédiat, échelonnements débités par mensualité,
-- fin de la catégorie « Frais externes » (ADR 008).
--
-- - Une transaction hors budget n'est plus déduite du courant : la clôture la
--   règle (elle est figée) sans la compter, et la modale en fait le récap.
-- - Une dépense « débit immédiat » sort du courant dès sa saisie (trigger) ;
--   la clôture la compte dans les dépenses du mois sans la redébiter.
-- - Une dépense échelonnée est payée en N fois : chaque clôture ne débite que
--   les mensualités dues jusqu'à son mois (installment_charges).
-- - Le virement compte commun n'est plus une dépense « Frais externes » mais
--   un `transfert` sans catégorie ; le budget Frais externes disparaît.
--
-- transactions.deducted : posé par la clôture, vrai si le montant entier de
-- la transaction est sorti du courant à ce moment-là (ou avant, débit
-- immédiat). Toutes les transactions réglées avant ce lot l'ont été en entier.

-- ---------------------------------------------------------------------------
-- Frais externes
-- ---------------------------------------------------------------------------
create or replace function public.budget_category_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_trigger_depth() = 1
     and old.category = 'Abonnements'
     and (tg_op = 'DELETE' or new.category <> old.category) then
    raise exception 'Le budget « % » ne peut être ni renommé ni supprimé', old.category
      using errcode = 'FF006';
  end if;

  if tg_op = 'DELETE' then
    -- Les abonnements d'un budget supprimé reviennent dans « Abonnements »
    -- (pas lors de la suppression en cascade du compte utilisateur).
    if pg_trigger_depth() = 1 then
      update public.subscriptions
      set category = 'Abonnements'
      where user_id = old.user_id and category = old.category;
    end if;
    return old;
  end if;

  if new.category <> old.category then
    update public.transactions
    set category = new.category
    where user_id = old.user_id and category = old.category;
    update public.subscriptions
    set category = new.category
    where user_id = old.user_id and category = old.category;
  end if;
  return new;
end;
$$;

update public.transactions
set type = 'transfert', category = null, hors_budget = false
where type = 'depense' and category = 'Frais externes'
  and label = 'Virement compte commun' and settled;

delete from public.budgets where category = 'Frais externes';

create or replace function public.init_user_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.settings (user_id) values (p_user_id)
  on conflict do nothing;

  insert into public.accounts (user_id, name, type) values
    (p_user_id, 'Compte courant', 'courant'),
    (p_user_id, 'Épargne', 'epargne')
  on conflict do nothing;

  insert into public.savings_projects (user_id, name, is_safety_fund, is_default, icon) values
    (p_user_id, 'Fond de sécurité', true, false, 'shield'),
    (p_user_id, 'Épargne générale', false, true, 'account_balance')
  on conflict do nothing;

  insert into public.budgets (user_id, category, icon) values
    (p_user_id, 'Courses', 'shopping_cart'),
    (p_user_id, 'Logement', 'home'),
    (p_user_id, 'Transport', 'directions_car'),
    (p_user_id, 'Restaurants', 'restaurant'),
    (p_user_id, 'Loisirs', 'sports_esports'),
    (p_user_id, 'Santé', 'medical_services'),
    (p_user_id, 'Shopping', 'shopping_bag'),
    (p_user_id, 'Abonnements', 'subscriptions')
  on conflict do nothing;
end;
$$;

revoke execute on function public.init_user_data(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Colonnes : débit immédiat, montant déduit à la clôture
-- ---------------------------------------------------------------------------
alter table public.transactions
  add column immediate boolean not null default false,
  add column deducted boolean,
  add constraint transactions_immediate_check
    check (not immediate or (type = 'depense' and not hors_budget));

update public.transactions set deducted = true
where settled and type in ('depense', 'revenu');

grant insert (immediate), update (immediate) on public.transactions to authenticated;

-- ---------------------------------------------------------------------------
-- Mensualités débitées des dépenses échelonnées
-- ---------------------------------------------------------------------------
-- Une ligne par mensualité sortie du courant, rattachée à la clôture qui l'a
-- débitée (null : dépense réglée en entier avant ce lot).
create table public.installment_charges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  transaction_id uuid not null,
  number int not null check (number >= 1),
  amount numeric(12,2) not null check (amount >= 0),
  settlement_id uuid,
  unique (id, user_id),
  unique (transaction_id, number),
  foreign key (transaction_id, user_id)
    references public.transactions (id, user_id) on delete cascade,
  foreign key (settlement_id, user_id)
    references public.monthly_settlements (id, user_id) on delete set null (settlement_id)
);
create index installment_charges_settlement on public.installment_charges (settlement_id);

alter table public.installment_charges enable row level security;
revoke all on public.installment_charges from anon;
revoke insert, update, delete on public.installment_charges from authenticated;
create policy "own rows" on public.installment_charges
  for select to authenticated using (user_id = (select auth.uid()));

-- Étalements déjà réglés : la dépense est sortie en entier, plus rien à débiter.
insert into public.installment_charges (user_id, transaction_id, number, amount)
select p.user_id, p.transaction_id, g.i + 1,
       public.installment_share(t.amount, p.installments, g.i)
from public.installment_plans p
join public.transactions t on t.id = p.transaction_id
cross join generate_series(0, p.installments - 1) g(i)
where t.settled;

-- Mensualités dues jusqu'au mois p_month et pas encore débitées.
create function public.installments_due(p_user uuid, p_month date)
returns table (transaction_id uuid, number int, amount numeric)
language sql
stable
set search_path = ''
as $$
  select p.transaction_id, g.i + 1,
         public.installment_share(t.amount, p.installments, g.i)
  from public.installment_plans p
  join public.transactions t on t.id = p.transaction_id
  cross join generate_series(0, p.installments - 1) g(i)
  where p.user_id = p_user
    and g.i <= public.month_index(t.month, p_month)
    and not exists (
      select 1 from public.installment_charges c
      where c.transaction_id = p.transaction_id and c.number = g.i + 1
    )
$$;

revoke execute on function public.installments_due(uuid, date) from public, anon;
grant execute on function public.installments_due(uuid, date) to authenticated;

-- Seule une dépense non réglée, comptée dans un budget et sans débit
-- immédiat peut être étalée ; une fois réglée, son étalement est figé
-- (sauf suppression en cascade : pg_trigger_depth() > 1).
create or replace function public.check_installment_plan()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() = 1 and exists (
      select 1 from public.transactions where id = old.transaction_id and settled
    ) then
      raise exception 'L''étalement d''une dépense réglée ne peut plus changer'
        using errcode = 'FF004';
    end if;
    return old;
  end if;

  if not exists (
    select 1 from public.transactions
    where id = new.transaction_id and user_id = new.user_id
      and type = 'depense' and category is not null
      and not hors_budget and not immediate and not settled
  ) then
    raise exception 'Seule une dépense non réglée, comptée dans un budget et sans débit immédiat peut être échelonnée'
      using errcode = 'FF004';
  end if;
  return new;
end;
$$;

drop trigger installment_plans_check on public.installment_plans;
create trigger installment_plans_check
  before insert or update or delete on public.installment_plans
  for each row execute function public.check_installment_plan();

-- ---------------------------------------------------------------------------
-- Débit immédiat : le courant suit la saisie, la modification et la
-- suppression d'une dépense non réglée. Une transaction réglée est figée :
-- la clôture qui la règle ne touche pas au solde ici.
-- ---------------------------------------------------------------------------
create function public.apply_immediate_expense()
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
    if exists (select 1 from public.installment_plans where transaction_id = new.id) then
      raise exception 'Une dépense échelonnée ne peut pas être en débit immédiat'
        using errcode = 'FF004';
    end if;
    update public.accounts set balance = balance - new.amount where id = new.account_id;
  end if;
  return null;
end;
$$;

create trigger transactions_immediate
  after insert or update or delete on public.transactions
  for each row execute function public.apply_immediate_expense();

revoke execute on function public.apply_immediate_expense() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- close_month
-- ---------------------------------------------------------------------------
-- total_expenses : dépenses comptées dans le mois = déduites (nettes des
-- revenus) + mensualités + débits immédiats. opening_balance : courant avant
-- clôture, débits immédiats réglés ce jour rajoutés, pour que les flux
-- (Sankey) les montrent comme des dépenses du mois.
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
  v_installments numeric;
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

  -- 1. Transactions de M (et d'avant, ex. prélèvement tardif) :
  --    a. débit immédiat : déjà sorties du courant ;
  with settled as (
    update public.transactions
    set settled = true, settlement_id = v_settlement, deducted = true
    where user_id = v_user and month <= p_month and not settled
      and type in ('depense', 'revenu') and immediate
    returning amount
  )
  select coalesce(sum(amount), 0) into v_immediate from settled;

  --    b. hors budget et échelonnées : figées, sans être déduites en entier ;
  update public.transactions t
  set settled = true, settlement_id = v_settlement, deducted = false
  where t.user_id = v_user and t.month <= p_month and not t.settled
    and t.type in ('depense', 'revenu')
    and (t.hors_budget
         or exists (select 1 from public.installment_plans p where p.transaction_id = t.id));

  --    c. les autres, nettes des revenus saisis en cours de mois ;
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

  --    d. mensualités des dépenses échelonnées dues jusqu'à M.
  with charged as (
    insert into public.installment_charges (user_id, transaction_id, number, amount, settlement_id)
    select v_user, d.transaction_id, d.number, d.amount, v_settlement
    from public.installments_due(v_user, p_month) d
    returning amount
  )
  select coalesce(sum(amount), 0) into v_installments from charged;

  v_expenses := v_expenses + v_installments;
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
-- Résumé du mois : ce que la clôture déduira vraiment
-- ---------------------------------------------------------------------------
-- unsettled_expenses : dépenses − revenus non réglés jusqu'au mois en cours,
-- hors budget et débits immédiats exclus, échelonnées remplacées par leurs
-- mensualités dues. Colonnes ajoutées en fin de vue : immediate_expenses
-- (débits immédiats que la clôture comptera) et hors_budget_expenses.
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
  o.immediate as immediate_expenses,
  o.hors_budget as hors_budget_expenses
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
  select (
    coalesce((
      select sum(case when t.type = 'depense' then t.amount else -t.amount end)
      from public.transactions t
      where t.user_id = m.user_id
        and t.month <= m.month
        and not t.settled
        and t.type in ('depense', 'revenu')
        and not t.hors_budget
        and not t.immediate
        and not exists (select 1 from public.installment_plans p where p.transaction_id = t.id)
    ), 0)
    + coalesce((select sum(d.amount) from public.installments_due(m.user_id, m.month) d), 0)
  )::numeric(12,2) as net
) u
cross join lateral (
  select
    coalesce(sum(t.amount) filter (where t.immediate), 0)::numeric(12,2) as immediate,
    coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end)
             filter (where t.hors_budget), 0)::numeric(12,2) as hors_budget
  from public.transactions t
  where t.user_id = m.user_id
    and t.month <= m.month
    and not t.settled
    and t.type in ('depense', 'revenu')
) o
cross join lateral (
  select coalesce(sum(greatest(b.remaining, b.reserved, 0)), 0)::numeric(12,2) as remaining
  from public.budget_status_current_month b
  where b.user_id = m.user_id and not b.hors_budget
) r
where m.status = 'pending';

-- Aperçu : mêmes totaux que close_month (débits immédiats compris).
create or replace function public.preview_close_month(
  p_salary numeric,
  p_shared_transfer numeric,
  p_special_month boolean default false
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_summary public.current_month_summary;
  v_courant numeric;
  v_savings numeric := 0;
begin
  select * into v_summary from public.current_month_summary;
  if not found then
    raise exception 'Aucun mois en cours' using errcode = 'FF001';
  end if;

  v_courant := v_summary.courant - v_summary.unsettled_expenses
             + coalesce(p_salary, 0) - coalesce(p_shared_transfer, 0);
  if not p_special_month and v_courant > v_summary.safety_margin then
    v_savings := v_courant - v_summary.safety_margin;
  end if;

  return jsonb_build_object(
    'month', v_summary.month,
    'total_expenses', v_summary.unsettled_expenses + v_summary.immediate_expenses,
    'total_savings', v_savings,
    'courant', v_courant - v_savings
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Flux d'une clôture : transactions déduites et mensualités débitées
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
  select 'out', 'expense', coalesce(x.category, 'Sans catégorie'), sum(x.amount)
  from (
    select t.category, t.amount
    from public.transactions t
    where t.settlement_id = s.id and t.type = 'depense' and t.month <= s.month and t.deducted
    union all
    select t.category, c.amount
    from public.installment_charges c
    join public.transactions t on t.id = c.transaction_id
    where c.settlement_id = s.id
  ) x
  group by x.category
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
-- Échelonnements : dépense réglée (étalement figé) et montant déjà débité
-- ---------------------------------------------------------------------------
create or replace view public.installment_plans_status
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
   end)::numeric(12,2) as remaining_amount,
  t.settled,
  (select coalesce(sum(c.amount), 0) from public.installment_charges c
   where c.transaction_id = p.transaction_id)::numeric(12,2) as charged_amount
from public.installment_plans p
join public.transactions t on t.id = p.transaction_id and t.user_id = p.user_id
left join public.monthly_settlements m on m.user_id = p.user_id and m.status = 'pending'
cross join lateral (
  select public.month_index(t.month, coalesce(m.month, t.month)) as i
) k;
