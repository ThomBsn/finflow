-- Virement de l'épargne vers le courant (spec §5).
--
-- Avec un projet : retiré de ce projet, dans la limite de son montant.
-- Sans projet : Épargne générale d'abord, puis les autres projets (ordre de
-- création), le Fond de sécurité en dernier recours. Le courant est crédité
-- tout de suite ; un `retrait_epargne` par projet entamé.

create function public.withdraw_from_savings(
  p_amount numeric,
  p_project_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_date date := (now() at time zone 'Europe/Paris')::date;
  v_courant uuid;
  v_epargne uuid;
  v_left numeric := p_amount;
  v_take numeric;
  v_project record;
begin
  if v_user is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Montant invalide' using errcode = 'FF004';
  end if;
  if p_project_id is not null and not exists (
    select 1 from public.savings_projects where id = p_project_id and user_id = v_user
  ) then
    raise exception 'Projet d''épargne inconnu' using errcode = 'FF003';
  end if;

  select id into v_courant from public.accounts
  where user_id = v_user and type = 'courant' for update;
  select id into v_epargne from public.accounts
  where user_id = v_user and type = 'epargne' for update;

  for v_project in
    select id, name, current_amount
    from public.savings_projects
    where user_id = v_user and current_amount > 0
      and (p_project_id is null or id = p_project_id)
    order by is_default desc, is_safety_fund, created_at, id
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, v_project.current_amount);
    update public.savings_projects
    set current_amount = current_amount - v_take where id = v_project.id;
    insert into public.transactions (
      user_id, date, type, amount, label, account_id, target_account_id,
      settled, savings_project_id
    )
    values (
      v_user, v_date, 'retrait_epargne', v_take, v_project.name, v_epargne,
      v_courant, true, v_project.id
    );
    v_left := v_left - v_take;
  end loop;

  if v_left > 0 then
    raise exception 'Épargne insuffisante : il manque %', to_char(v_left, 'FM999G990D00')
      using errcode = 'FF004';
  end if;

  update public.accounts set balance = balance - p_amount where id = v_epargne;
  update public.accounts set balance = balance + p_amount where id = v_courant;
end;
$$;

revoke execute on function public.withdraw_from_savings(numeric, uuid) from public, anon;
grant execute on function public.withdraw_from_savings(numeric, uuid) to authenticated;
