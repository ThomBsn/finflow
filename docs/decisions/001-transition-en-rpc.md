# 001 — La transition de mois est une RPC Postgres
**Contexte :** la transition modifie 5 entités et plusieurs soldes. Un échec à mi-chemin laisserait des données incohérentes.
**Décision :** une fonction `close_month` en SQL, exécutée dans une transaction, protégée par l'unicité de `monthly_settlements(user_id, month)`.
**Conséquence :** le front n'appelle qu'une RPC puis invalide ses requêtes.
