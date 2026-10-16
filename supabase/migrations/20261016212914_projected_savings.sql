-- Épargne prévue en direct (spec §2), à la place du « disponible estimé ».
--
-- Avec une carte à débit différé, les dépenses du mois sortent toutes le 3 du
-- mois suivant, après le salaire : les comparer au courant (la marge de
-- 200 €) n'a pas de sens. L'indicateur utile est ce que la prochaine clôture
-- mettra en épargne, recalculé à chaque dépense :
--
--   projected_savings = courant + salaire − virement commun
--                       − dépenses non réglées − marge de sécurité
--
-- avec le salaire et le virement commun habituels (settings), sinon ceux du
-- mois en cours. Négatif : la clôture n'épargnera rien et le courant passera
-- sous la marge d'autant.
--
-- projected_savings_budgets : même calcul si l'on dépense encore tout ce qui
-- reste dans les enveloppes (abonnements pas encore prélevés compris).

drop view public.current_month_summary;

create view public.current_month_summary
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
  select coalesce(sum(greatest(b.remaining, 0)), 0)::numeric(12,2) as remaining
  from public.budget_status_current_month b
  where b.user_id = m.user_id and not b.hors_budget
) r
where m.status = 'pending';

revoke all on public.current_month_summary from anon;
grant select on public.current_month_summary to authenticated;
