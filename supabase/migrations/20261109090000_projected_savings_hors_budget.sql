-- Épargne prévue : les dépenses hors budget seront remboursées depuis
-- l'épargne, elles ne la diminuent pas.
--
-- On n'en retire que la part déjà remboursée (le remboursement a crédité le
-- courant) : l'épargne prévue est la même avant et après le remboursement.
-- hors_budget_pending (colonne ajoutée) : ce qui reste à rembourser. La
-- clôture, elle, déduit toujours tout ce que la carte débite : sans
-- remboursement, l'épargne virée sera plus basse d'autant.

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
    coalesce(sum(t.amount) filter (where t.immediate), 0)::numeric(12,2) as immediate,
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
