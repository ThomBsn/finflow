-- Lot 3 bis : résumé du mois en cours et aperçu de la transition.

-- ---------------------------------------------------------------------------
-- Résumé du mois en cours (Dashboard, futur widget Android)
-- ---------------------------------------------------------------------------
-- unsettled_expenses : dépenses − revenus non réglés jusqu'au mois en cours,
--   exactement ce que close_month réglera à l'étape 1.
-- available : « disponible estimé » (spec §2).
-- suggested_* : valeurs proposées dans la modale de transition, celles du
--   mois en cours (saisies à la transition précédente) ou à défaut settings.
create view public.current_month_summary
with (security_invoker = true)
as
select
  m.user_id,
  m.month,
  c.balance as courant,
  e.balance as epargne,
  u.net as unsettled_expenses,
  (c.balance - u.net)::numeric(12,2) as available,
  s.safety_margin,
  coalesce(nullif(m.salary, 0), s.default_salary) as suggested_salary,
  coalesce(nullif(m.shared_transfer, 0), s.default_shared_transfer) as suggested_shared_transfer
from public.monthly_settlements m
join public.accounts c on c.user_id = m.user_id and c.type = 'courant'
join public.accounts e on e.user_id = m.user_id and e.type = 'epargne'
join public.settings s on s.user_id = m.user_id
cross join lateral (
  select coalesce(sum(case when t.type = 'depense' then t.amount else -t.amount end), 0)::numeric(12,2) as net
  from public.transactions t
  where t.user_id = m.user_id
    and t.month <= m.month
    and not t.settled
    and t.type in ('depense', 'revenu')
) u
where m.status = 'pending';

revoke all on public.current_month_summary from anon;
grant select on public.current_month_summary to authenticated;

-- ---------------------------------------------------------------------------
-- Aperçu de close_month, sans écriture (spec §3)
-- ---------------------------------------------------------------------------
-- Mêmes formules que close_month ; le test 04 vérifie que les deux
-- concordent sur les exemples de la spec.
create function public.preview_close_month(
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
    'total_expenses', v_summary.unsettled_expenses,
    'total_savings', v_savings,
    'courant', v_courant - v_savings
  );
end;
$$;

revoke execute on function public.preview_close_month(numeric, numeric, boolean) from public, anon;
grant execute on function public.preview_close_month(numeric, numeric, boolean) to authenticated;
