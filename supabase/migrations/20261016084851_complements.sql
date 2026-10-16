-- Lot 4 : abonnements (pg_cron), échelonnements, projets d'épargne.

-- ---------------------------------------------------------------------------
-- Abonnements : un prélèvement par mois au plus, jamais recréé
-- ---------------------------------------------------------------------------
-- last_charge_date mémorise le dernier prélèvement généré : un prélèvement
-- supprimé par l'utilisateur n'est pas recréé, et changer le jour de
-- prélèvement ne déclenche pas un second prélèvement le même mois.
alter table public.subscriptions add column last_charge_date date;

update public.subscriptions s
set last_charge_date = (
  select max(t.date) from public.transactions t where t.subscription_id = s.id
);

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
    select s.id, s.user_id, s.name, s.amount, s.created_at,
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
    insert into public.transactions (user_id, date, type, amount, label, category, subscription_id)
    select user_id, charge_date, 'depense', amount, name, 'Abonnements', id
    from due
    where charge_date <= p_date
      and charge_date >= created_at::date
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

-- Passage quotidien, date du jour à Paris.
create extension if not exists pg_cron;
select cron.schedule(
  'finflow-subscription-charges',
  '0 4 * * *',
  $$select private.generate_subscription_charges((now() at time zone 'Europe/Paris')::date)$$
);

-- ---------------------------------------------------------------------------
-- Échelonnements : étalement d'une dépense sur son budget (spec §6)
-- ---------------------------------------------------------------------------
-- Une dépense échelonnée sort du courant en une fois (réglée à la clôture de
-- son mois) mais ne pèse sur le budget de sa catégorie que d'une mensualité
-- par mois, pendant N mois à partir du mois de la dépense. Montant, catégorie
-- et mois de départ viennent de la dépense : la modifier met le plan à jour.
-- Remplace le modèle du lot 1 (plan autonome + N transactions).
drop policy "update own unsettled" on public.transactions;
drop policy "delete own unsettled" on public.transactions;
alter table public.transactions drop column installment_plan_id;
drop table public.installment_plans;

create policy "update own unsettled" on public.transactions
  for update to authenticated
  using (user_id = (select auth.uid()) and not settled)
  with check (user_id = (select auth.uid()) and type in ('depense', 'revenu'));
create policy "delete own unsettled" on public.transactions
  for delete to authenticated
  using (user_id = (select auth.uid()) and not settled);

create table public.installment_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  transaction_id uuid not null,
  installments int not null check (installments between 2 and 120),
  unique (id, user_id),
  unique (transaction_id, user_id),
  foreign key (transaction_id, user_id)
    references public.transactions (id, user_id) on delete cascade
);

-- Seule une dépense comptée dans un budget peut être étalée.
create function public.check_installment_plan()
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

create trigger installment_plans_check
  before insert or update on public.installment_plans
  for each row execute function public.check_installment_plan();

alter table public.installment_plans enable row level security;
revoke all on public.installment_plans from anon;
revoke insert, update, delete on public.installment_plans from authenticated;
grant insert (transaction_id, installments), update (installments), delete
  on public.installment_plans to authenticated;
create policy "own rows" on public.installment_plans
  for select to authenticated using (user_id = (select auth.uid()));
create policy "write own" on public.installment_plans
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Rang (0, 1, …) du mois p_month dans un étalement commençant en p_start.
create function public.month_index(p_start date, p_month date)
returns int
language sql
immutable
set search_path = ''
as $$
  select ((extract(year from p_month) - extract(year from p_start)) * 12
          + extract(month from p_month) - extract(month from p_start))::int
$$;

-- Mensualité de rang p_index : montant / N tronqué au centime, reliquat
-- d'arrondi sur la dernière, 0 hors de l'étalement.
create function public.installment_share(p_amount numeric, p_installments int, p_index int)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when p_index < 0 or p_index >= p_installments then 0
    when p_index = p_installments - 1
      then p_amount - trunc(p_amount / p_installments, 2) * (p_installments - 1)
    else trunc(p_amount / p_installments, 2)
  end
$$;

-- ---------------------------------------------------------------------------
-- Composition des budgets du mois en cours
-- ---------------------------------------------------------------------------
-- Une ligne par contribution au consommé d'un budget : dépense (+), revenu
-- (−), ou mensualité d'une dépense étalée (installment_number / installments).
create view public.budget_lines_current_month
with (security_invoker = true)
as
select
  b.id as budget_id,
  b.user_id,
  t.id as transaction_id,
  t.date,
  t.label,
  t.type,
  (case
    when p.id is not null
      then public.installment_share(t.amount, p.installments, public.month_index(t.month, m.month))
    when t.type = 'depense' then t.amount
    else -t.amount
  end)::numeric(12,2) as amount,
  t.amount as transaction_amount,
  case when p.id is not null then public.month_index(t.month, m.month) + 1 end as installment_number,
  p.installments
from public.budgets b
join public.monthly_settlements m
  on m.user_id = b.user_id and m.status = 'pending'
join public.transactions t
  on t.user_id = b.user_id
  and t.category = b.category
  and t.type in ('depense', 'revenu')
  and (b.hors_budget or not t.hors_budget)
left join public.installment_plans p
  on p.transaction_id = t.id and t.type = 'depense'
where (p.id is null and t.month = m.month)
   or (p.id is not null
       and public.month_index(t.month, m.month) between 0 and p.installments - 1);

revoke all on public.budget_lines_current_month from anon;
grant select on public.budget_lines_current_month to authenticated;

-- Le consommé d'un budget est la somme de ses lignes.
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
  a.allocated - s.spent as remaining
from public.budgets b
join public.monthly_settlements m
  on m.user_id = b.user_id and m.status = 'pending'
cross join lateral (
  select case
    when b.category = 'Abonnements' then coalesce((
      select sum(sub.amount) from public.subscriptions sub
      where sub.user_id = b.user_id and sub.active
    ), 0)
    else b.monthly_amount
  end::numeric(12,2) as allocated
) a
cross join lateral (
  select coalesce(sum(l.amount), 0)::numeric(12,2) as spent
  from public.budget_lines_current_month l
  where l.budget_id = b.id
) s;

-- Échelonnements avec leur avancement au mois en cours.
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

-- ---------------------------------------------------------------------------
-- Projets d'épargne (spec §5)
-- ---------------------------------------------------------------------------
-- Création avec un montant déjà épargné (reprise d'un projet existant) :
-- crédite le compte épargne sans toucher au courant ni créer de transfert.
create function public.create_savings_project(
  p_name text,
  p_percentage numeric default 0,
  p_target numeric default null,
  p_initial_amount numeric default 0
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

  insert into public.savings_projects (user_id, name, percentage, target_amount, current_amount)
  values (v_user, p_name, coalesce(p_percentage, 0), p_target, coalesce(p_initial_amount, 0))
  returning id into v_project;

  update public.accounts set balance = balance + coalesce(p_initial_amount, 0)
  where user_id = v_user and type = 'epargne';

  return v_project;
end;
$$;

-- Versement manuel en cours de mois : débite le courant et répartit
-- (automatique selon les pourcentages, ou précis vers un projet).
create function public.save_to_savings(
  p_amount numeric,
  p_mode public.distribution_mode,
  p_project_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;
  perform private.distribute_savings(
    v_user, p_amount, p_mode, p_project_id, (now() at time zone 'Europe/Paris')::date
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------------
revoke execute on function
  public.create_savings_project(text, numeric, numeric, numeric),
  public.save_to_savings(numeric, public.distribution_mode, uuid)
from public, anon;
grant execute on function
  public.create_savings_project(text, numeric, numeric, numeric),
  public.save_to_savings(numeric, public.distribution_mode, uuid)
to authenticated;
