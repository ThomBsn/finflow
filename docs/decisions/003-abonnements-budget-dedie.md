# 003 — Les abonnements ont un budget dédié et génèrent leurs transactions
*Révisé le 2026-10-15.*
**Contexte :** la décision initiale (un abonnement réserve son montant dans le budget de sa catégorie, sans transaction) faisait que l'argent ne sortait jamais du courant à la transition : l'épargne calculée était surestimée.
**Décision :** tous les abonnements sont dans la catégorie « Abonnements », dont l'alloué = somme des abonnements actifs. Une tâche pg_cron quotidienne crée une `depense` le `billing_day` de chaque mois (dernier jour du mois si ce jour n'existe pas).
**Conséquence :** les abonnements suivent le cycle normal des dépenses (non réglées puis réglées à `close_month`). La génération doit être idempotente (unique `subscription_id, date`).
