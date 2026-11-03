-- Mois de débit choisi à la saisie (ADR 009).
--
-- La carte à débit différé cumule les dépenses sur une période qui ne suit
-- pas le calendrier (ex. du 29/09 au 28/10, débitée le 4/11), et dont la
-- date de coupure varie. Plutôt que de suivre ces dates, chaque dépense ou
-- revenu porte le mois dont il sera réglé : `transactions.month` n'est plus
-- calculé à partir de la date mais saisi, prérempli avec le mois en cours
-- (`pending`). Clôture, budgets et filtres utilisent déjà `month`.

alter table public.transactions alter column month drop expression;
alter table public.transactions
  add constraint transactions_month_first_day check (extract(day from month) = 1);

-- Sans mois précisé : le mois en cours pour une dépense / un revenu saisi
-- (non réglé), le mois de la date pour le reste (salaire, compte commun et
-- épargne créés par la clôture, rééquilibrage), ou faute de mois en cours.
create function public.default_transaction_month()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.month is null then
    if new.type in ('depense', 'revenu') and not new.settled then
      select month into new.month
      from public.monthly_settlements
      where user_id = new.user_id and status = 'pending';
    end if;
    new.month := coalesce(new.month, date_trunc('month', new.date::timestamp)::date);
  end if;
  return new;
end;
$$;

create trigger transactions_default_month
  before insert on public.transactions
  for each row execute function public.default_transaction_month();

grant insert (month), update (month) on public.transactions to authenticated;

-- Dépenses déjà saisies d'un mois postérieur au mois en cours : rattachées
-- au mois en cours (à corriger à la main pour les quelques-unes à reporter).
update public.transactions t
set month = m.month
from public.monthly_settlements m
where m.user_id = t.user_id and m.status = 'pending'
  and t.month > m.month and not t.settled
  and t.type in ('depense', 'revenu');
