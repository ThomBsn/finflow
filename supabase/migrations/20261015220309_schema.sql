-- Lot 1 : schéma FinFlow (docs/modele-donnees.md).
--
-- Conventions :
-- - chaque table porte user_id (défaut auth.uid()) et unique (id, user_id) ;
--   les clés étrangères sont composites (fk, user_id) pour qu'une ligne ne
--   puisse jamais référencer une ligne d'un autre utilisateur ;
-- - RLS partout, droits d'écriture accordés colonne par colonne : les soldes,
--   montants épargnés et indicateurs « réglé » ne bougent que via les RPC.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.account_type as enum ('courant', 'epargne');
create type public.transaction_type as enum (
  'depense', 'revenu', 'transfert_epargne', 'retrait_epargne', 'transfert'
);
create type public.distribution_mode as enum ('automatique', 'precis');
create type public.settlement_status as enum ('pending', 'settled');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.settings (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  default_salary numeric(12,2) not null default 0 check (default_salary >= 0),
  default_shared_transfer numeric(12,2) not null default 0 check (default_shared_transfer >= 0),
  safety_margin numeric(12,2) not null default 200 check (safety_margin >= 0)
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  name text not null,
  type public.account_type not null,
  balance numeric(12,2) not null default 0,
  unique (id, user_id)
);
-- Un seul compte courant et un seul compte épargne par utilisateur.
create unique index accounts_one_per_type on public.accounts (user_id, type);

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  category text not null,
  monthly_amount numeric(12,2) not null default 0 check (monthly_amount >= 0),
  icon text not null default 'category',
  hors_budget boolean not null default false,
  unique (id, user_id),
  unique (user_id, category)
);

create table public.savings_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  name text not null,
  percentage numeric(5,2) not null default 0 check (percentage between 0 and 100),
  target_amount numeric(12,2) check (target_amount > 0),
  current_amount numeric(12,2) not null default 0 check (current_amount >= 0),
  is_default boolean not null default false,
  is_safety_fund boolean not null default false,
  unique (id, user_id),
  check (not (is_default and is_safety_fund)),
  -- Épargne générale reçoit le complément à 100 % et n'a pas de plafond.
  check (not is_default or (percentage = 0 and target_amount is null))
);
create unique index savings_projects_one_default
  on public.savings_projects (user_id) where is_default;
create unique index savings_projects_one_safety_fund
  on public.savings_projects (user_id) where is_safety_fund;

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  name text not null,
  amount numeric(12,2) not null check (amount > 0),
  billing_day int not null check (billing_day between 1 and 31),
  active boolean not null default true,
  unique (id, user_id)
);

create table public.installment_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  label text not null,
  total_amount numeric(12,2) not null check (total_amount > 0),
  installments int not null check (installments >= 2),
  start_month date not null check (extract(day from start_month) = 1),
  category text not null,
  unique (id, user_id)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  date date not null default current_date,
  -- `::timestamp` obligatoire : date_trunc(text, timestamptz) n'est pas
  -- immuable et serait refusé dans une colonne générée.
  month date not null generated always as (date_trunc('month', date::timestamp)::date) stored,
  type public.transaction_type not null,
  amount numeric(12,2) not null check (amount > 0),
  label text not null default '',
  category text,
  account_id uuid not null,
  target_account_id uuid,
  hors_budget boolean not null default false,
  settled boolean not null default false,
  installment_plan_id uuid,
  savings_project_id uuid,
  subscription_id uuid,
  distribution_mode public.distribution_mode,
  unique (id, user_id),
  foreign key (account_id, user_id) references public.accounts (id, user_id),
  foreign key (target_account_id, user_id) references public.accounts (id, user_id),
  foreign key (installment_plan_id, user_id) references public.installment_plans (id, user_id),
  foreign key (savings_project_id, user_id)
    references public.savings_projects (id, user_id) on delete set null (savings_project_id),
  foreign key (subscription_id, user_id)
    references public.subscriptions (id, user_id) on delete set null (subscription_id),
  check (type <> 'depense' or category is not null),
  check (distribution_mode is null or type = 'transfert_epargne')
);
create index transactions_user_month on public.transactions (user_id, month);
create index transactions_user_category_month on public.transactions (user_id, category, month);
-- Rejeu sans doublon de la génération des prélèvements d'abonnements.
create unique index transactions_subscription_date on public.transactions (subscription_id, date);

create table public.monthly_settlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  month date not null check (extract(day from month) = 1),
  status public.settlement_status not null default 'pending',
  salary numeric(12,2) not null default 0,
  shared_transfer numeric(12,2) not null default 0,
  total_expenses numeric(12,2),
  total_savings numeric(12,2),
  special_month boolean not null default false,
  unique (id, user_id),
  unique (user_id, month)
);
create unique index monthly_settlements_one_pending
  on public.monthly_settlements (user_id) where status = 'pending';

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
create function public.check_savings_percentages()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
    select coalesce(sum(percentage), 0)
    from public.savings_projects
    where user_id = new.user_id
  ) > 100 then
    raise exception 'La somme des pourcentages d''épargne dépasse 100 %%'
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;

create trigger savings_percentages_max_100
  after insert or update of percentage on public.savings_projects
  for each row execute function public.check_savings_percentages();

-- Une transaction saisie sans compte va sur le compte courant.
create function public.default_transaction_account()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.account_id is null then
    select id into new.account_id
    from public.accounts
    where user_id = new.user_id and type = 'courant';
  end if;
  return new;
end;
$$;

create trigger transactions_default_account
  before insert on public.transactions
  for each row execute function public.default_transaction_account();

-- ---------------------------------------------------------------------------
-- Données par défaut d'un utilisateur (créées à l'inscription)
-- ---------------------------------------------------------------------------
create function public.init_user_data(p_user_id uuid)
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

  insert into public.savings_projects (user_id, name, is_safety_fund, is_default) values
    (p_user_id, 'Fond de sécurité', true, false),
    (p_user_id, 'Épargne générale', false, true)
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

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.init_user_data(new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

revoke execute on function public.init_user_data(uuid) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Utilisateurs déjà inscrits avant cette migration.
select public.init_user_data(id) from auth.users;

-- ---------------------------------------------------------------------------
-- Droits et RLS
-- ---------------------------------------------------------------------------
alter table public.settings enable row level security;
alter table public.accounts enable row level security;
alter table public.budgets enable row level security;
alter table public.savings_projects enable row level security;
alter table public.subscriptions enable row level security;
alter table public.installment_plans enable row level security;
alter table public.transactions enable row level security;
alter table public.monthly_settlements enable row level security;

-- Rien pour anon ; pour authenticated, on repart de la lecture seule et on
-- n'accorde que les écritures prévues par le modèle.
revoke all on
  public.settings, public.accounts, public.budgets, public.savings_projects,
  public.subscriptions, public.installment_plans, public.transactions,
  public.monthly_settlements
from anon;
revoke insert, update, delete on
  public.settings, public.accounts, public.budgets, public.savings_projects,
  public.subscriptions, public.installment_plans, public.transactions,
  public.monthly_settlements
from authenticated;

grant update (default_salary, default_shared_transfer, safety_margin)
  on public.settings to authenticated;
grant update (name) on public.accounts to authenticated;
grant insert, update, delete on public.budgets to authenticated;
grant insert (name, percentage, target_amount), update (name, percentage, target_amount), delete
  on public.savings_projects to authenticated;
grant insert, update, delete on public.subscriptions to authenticated;
grant insert (date, type, amount, label, category, account_id, hors_budget),
      update (date, type, amount, label, category, account_id, hors_budget),
      delete
  on public.transactions to authenticated;

-- Lecture : ses propres lignes uniquement.
create policy "own rows" on public.settings
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows" on public.accounts
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows" on public.budgets
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows" on public.savings_projects
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows" on public.subscriptions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows" on public.installment_plans
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows" on public.transactions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows" on public.monthly_settlements
  for select to authenticated using (user_id = (select auth.uid()));

-- Écritures.
create policy "update own" on public.settings
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "update own" on public.accounts
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "write own" on public.budgets
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "write own" on public.subscriptions
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "insert own" on public.savings_projects
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "update own" on public.savings_projects
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
-- Fond de sécurité et Épargne générale sont permanents ; un projet ne se
-- supprime que vide, sinon l'invariant compte épargne = Σ projets casse.
create policy "delete own empty" on public.savings_projects
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    and not is_default and not is_safety_fund
    and current_amount = 0
  );

-- Le client ne saisit que des dépenses / revenus non réglés, hors
-- échelonnements (gérés par RPC). Une transaction réglée est figée.
create policy "insert own" on public.transactions
  for insert to authenticated
  with check (user_id = (select auth.uid()) and type in ('depense', 'revenu'));
create policy "update own unsettled" on public.transactions
  for update to authenticated
  using (user_id = (select auth.uid()) and not settled and installment_plan_id is null)
  with check (user_id = (select auth.uid()) and type in ('depense', 'revenu'));
create policy "delete own unsettled" on public.transactions
  for delete to authenticated
  using (user_id = (select auth.uid()) and not settled and installment_plan_id is null);
