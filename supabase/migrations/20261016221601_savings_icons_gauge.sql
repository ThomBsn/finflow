-- Projets d'épargne : icône et correction du montant ; jauge des budgets :
-- part des mensualités d'étalement.

-- ---------------------------------------------------------------------------
-- Icône d'un projet (mêmes noms d'icônes que les budgets)
-- ---------------------------------------------------------------------------
alter table public.savings_projects add column icon text not null default 'flag';
update public.savings_projects set icon = 'shield' where is_safety_fund;
update public.savings_projects set icon = 'account_balance' where is_default;

grant insert (icon), update (icon) on public.savings_projects to authenticated;

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

  insert into public.budgets (user_id, category, icon, hors_budget) values
    (p_user_id, 'Courses', 'shopping_cart', false),
    (p_user_id, 'Logement', 'home', false),
    (p_user_id, 'Transport', 'directions_car', false),
    (p_user_id, 'Restaurants', 'restaurant', false),
    (p_user_id, 'Loisirs', 'sports_esports', false),
    (p_user_id, 'Santé', 'medical_services', false),
    (p_user_id, 'Shopping', 'shopping_bag', false),
    (p_user_id, 'Abonnements', 'subscriptions', false),
    (p_user_id, 'Frais externes', 'call_split', true)
  on conflict do nothing;
end;
$$;

revoke execute on function public.init_user_data(uuid) from public, anon, authenticated;

drop function public.create_savings_project(text, numeric, numeric, numeric);

create function public.create_savings_project(
  p_name text,
  p_percentage numeric default 0,
  p_target numeric default null,
  p_initial_amount numeric default 0,
  p_icon text default 'flag'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_project uuid;
begin
  if v_user is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;
  if coalesce(p_initial_amount, 0) < 0 then
    raise exception 'Montant invalide' using errcode = 'FF004';
  end if;

  insert into public.savings_projects (
    user_id, name, percentage, target_amount, current_amount, icon
  )
  values (
    v_user, p_name, coalesce(p_percentage, 0), p_target,
    coalesce(p_initial_amount, 0), coalesce(p_icon, 'flag')
  )
  returning id into v_project;

  update public.accounts set balance = balance + coalesce(p_initial_amount, 0)
  where user_id = v_user and type = 'epargne';

  return v_project;
end;
$$;

-- ---------------------------------------------------------------------------
-- Correction du montant d'un projet (Fond de sécurité et Épargne générale
-- compris) : recalage sur la banque, sans mouvement du courant. Le compte
-- épargne suit, pour garder compte épargne = Σ projets.
-- ---------------------------------------------------------------------------
create function public.adjust_savings_project(p_project_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_current numeric;
begin
  if v_user is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'Montant invalide' using errcode = 'FF004';
  end if;

  select current_amount into v_current
  from public.savings_projects
  where id = p_project_id and user_id = v_user
  for update;
  if not found then
    raise exception 'Projet d''épargne inconnu' using errcode = 'FF003';
  end if;

  update public.savings_projects set current_amount = p_amount where id = p_project_id;
  update public.accounts set balance = balance + (p_amount - v_current)
  where user_id = v_user and type = 'epargne';
end;
$$;

revoke execute on function
  public.create_savings_project(text, numeric, numeric, numeric, text),
  public.adjust_savings_project(uuid, numeric)
from public, anon;
grant execute on function
  public.create_savings_project(text, numeric, numeric, numeric, text),
  public.adjust_savings_project(uuid, numeric)
to authenticated;

-- ---------------------------------------------------------------------------
-- Jauge des budgets : part des mensualités d'étalement dans le dépensé
-- ---------------------------------------------------------------------------
-- installment_spent : mensualités du mois des dépenses étalées, déjà
-- engagées. Colonne ajoutée en fin de vue.
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
  r.reserved,
  s.installment_spent
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
  select
    coalesce(sum(l.amount), 0)::numeric(12,2) as spent,
    coalesce(sum(l.amount) filter (where l.installment_number is not null), 0)::numeric(12,2)
      as installment_spent
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
