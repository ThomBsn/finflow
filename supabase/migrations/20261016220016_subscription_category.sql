-- Catégorie par abonnement (révise ADR 003) : un prélèvement automatique
-- peut appartenir à n'importe quel budget (ex. assurance moto → Véhicule).
-- « Abonnements » reste la catégorie par défaut, et son alloué reste calculé
-- à partir des abonnements qui y sont rangés.
--
-- Chaque budget expose une part « réservée » : les abonnements de sa
-- catégorie pas encore prélevés ce mois-ci. L'épargne prévue « budgets
-- épuisés » la compte même si l'enveloppe est trop petite pour la couvrir.

alter table public.subscriptions
  add column category text not null default 'Abonnements';

-- ---------------------------------------------------------------------------
-- Prélèvements : catégorie et « hors budget » de l'abonnement
-- ---------------------------------------------------------------------------
create or replace function private.generate_subscription_charges(p_date date default current_date)
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
    select s.id, s.user_id, s.name, s.amount, s.category, s.created_at,
           m.first_day + least(
             s.billing_day,
             extract(day from m.first_day + interval '1 month - 1 day')::int
           ) - 1 as charge_date
    from public.subscriptions s
    cross join months m
    where s.active
      and (s.last_charge_date is null
           or m.first_day > date_trunc('month', s.last_charge_date::timestamp)::date)
  ),
  inserted as (
    insert into public.transactions (
      user_id, date, type, amount, label, category, hors_budget, subscription_id
    )
    select d.user_id, d.charge_date, 'depense', d.amount, d.name, d.category,
           coalesce(b.hors_budget, false), d.id
    from due d
    left join public.budgets b on b.user_id = d.user_id and b.category = d.category
    where d.charge_date <= p_date
      and d.charge_date >= d.created_at::date
    on conflict (subscription_id, date) do nothing
    returning subscription_id, date
  ),
  marked as (
    update public.subscriptions s
    set last_charge_date = i.last_date
    from (select subscription_id, max(date) as last_date from inserted group by subscription_id) i
    where s.id = i.subscription_id
    returning 1
  )
  select count(*) into v_count from inserted;

  return v_count;
end;
$$;

revoke execute on function private.generate_subscription_charges(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Renommer / supprimer un budget : ses abonnements suivent
-- ---------------------------------------------------------------------------
create or replace function public.budget_category_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_trigger_depth() = 1
     and old.category in ('Abonnements', 'Frais externes')
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

-- ---------------------------------------------------------------------------
-- Budgets du mois : part réservée aux abonnements à venir
-- ---------------------------------------------------------------------------
-- reserved : abonnements actifs de la catégorie dont le prélèvement du mois
-- en cours n'a pas encore eu lieu (et qui existaient à leur date de
-- prélèvement). Colonne ajoutée en fin de vue.
create or replace view public.budget_status_current_month
with (security_invoker = true)
as
select
  b.id,
  b.user_id,
  b.category,
  b.icon,
  b.hors_budget,
  m.month,
  a.allocated,
  s.spent,
  a.allocated - s.spent as remaining,
  r.reserved
from public.budgets b
join public.monthly_settlements m
  on m.user_id = b.user_id and m.status = 'pending'
cross join lateral (
  select case
    when b.category = 'Abonnements' then coalesce((
      select sum(sub.amount) from public.subscriptions sub
      where sub.user_id = b.user_id and sub.active and sub.category = 'Abonnements'
    ), 0)
    else b.monthly_amount
  end::numeric(12,2) as allocated
) a
cross join lateral (
  select coalesce(sum(l.amount), 0)::numeric(12,2) as spent
  from public.budget_lines_current_month l
  where l.budget_id = b.id
) s
cross join lateral (
  select coalesce(sum(sub.amount), 0)::numeric(12,2) as reserved
  from public.subscriptions sub
  cross join lateral (
    select m.month + least(
      sub.billing_day,
      extract(day from m.month + interval '1 month - 1 day')::int
    ) - 1 as charge_date
  ) d
  where sub.user_id = b.user_id
    and sub.active
    and sub.category = b.category
    and d.charge_date >= sub.created_at::date
    and (sub.last_charge_date is null or sub.last_charge_date < m.month)
) r;

-- ---------------------------------------------------------------------------
-- Épargne prévue : le reste d'un budget couvre au moins ses abonnements
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
    as projected_savings_budgets
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
  select coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end), 0)::numeric(12,2) as net
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
