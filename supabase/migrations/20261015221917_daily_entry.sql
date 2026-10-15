-- Lot 3 : onboarding, budgets du mois en cours, renommage des catégories.
-- Codes d'erreur ajoutés : FF005 onboarding déjà fait, FF006 budget système.

-- ---------------------------------------------------------------------------
-- Catégories de budget
-- ---------------------------------------------------------------------------
-- Les transactions référencent leur catégorie par son nom : renommer un
-- budget renomme aussi ses transactions (réglées comprises).
-- « Abonnements » et « Frais externes » sont utilisés par les RPC : ni
-- renommables ni supprimables, sauf suppression en cascade du compte
-- utilisateur (pg_trigger_depth() > 1).
create function public.budget_category_change()
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
    return old;
  end if;

  if new.category <> old.category then
    update public.transactions
    set category = new.category
    where user_id = old.user_id and category = old.category;
  end if;
  return new;
end;
$$;

create trigger budgets_category_change
  before update of category or delete on public.budgets
  for each row execute function public.budget_category_change();

revoke execute on function public.budget_category_change() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Onboarding (spec §9)
-- ---------------------------------------------------------------------------
-- Démarrage en cours de mois : le courant vaut son niveau d'après transition
-- (par défaut la marge de sécurité) et l'utilisateur saisit ensuite les
-- dépenses depuis le début du mois. Ouvre le mois en cours (heure de Paris).
create function public.complete_onboarding(
  p_courant numeric,
  p_safety_fund numeric default 0,
  p_general_savings numeric default 0
)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_month date := date_trunc('month', (now() at time zone 'Europe/Paris'))::date;
begin
  if v_user is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;
  if exists (select 1 from public.monthly_settlements where user_id = v_user) then
    raise exception 'Onboarding déjà fait' using errcode = 'FF005';
  end if;
  if p_courant is null or p_safety_fund < 0 or p_general_savings < 0 then
    raise exception 'Montant invalide' using errcode = 'FF004';
  end if;

  update public.accounts set balance = p_courant
  where user_id = v_user and type = 'courant';
  update public.savings_projects set current_amount = p_safety_fund
  where user_id = v_user and is_safety_fund;
  update public.savings_projects set current_amount = p_general_savings
  where user_id = v_user and is_default;
  update public.accounts
  set balance = (select coalesce(sum(current_amount), 0)
                 from public.savings_projects where user_id = v_user)
  where user_id = v_user and type = 'epargne';

  insert into public.monthly_settlements (user_id, month) values (v_user, v_month);
  return v_month;
end;
$$;

revoke execute on function public.complete_onboarding(numeric, numeric, numeric) from public, anon;
grant execute on function public.complete_onboarding(numeric, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- Budgets du mois en cours (spec §6)
-- ---------------------------------------------------------------------------
-- Mois en cours = mois `pending`, pas le mois calendaire.
-- allocated : monthly_amount, ou Σ abonnements actifs pour « Abonnements ».
-- spent : dépenses − revenus de la catégorie, hors transactions hors budget
--         (sauf pour un budget lui-même hors budget, ex. Frais externes).
create view public.budget_status_current_month
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
  select coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end), 0)::numeric(12,2) as spent
  from public.transactions t
  where t.user_id = b.user_id
    and t.category = b.category
    and t.month = m.month
    and t.type in ('depense', 'revenu')
    and (b.hors_budget or not t.hors_budget)
) s;

revoke all on public.budget_status_current_month from anon;
grant select on public.budget_status_current_month to authenticated;
