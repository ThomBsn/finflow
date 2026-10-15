# Roadmap — FinFlow

Règle : un lot n'est terminé que si ses critères de fin sont tous cochés. Mettre à jour ce fichier en fin de lot.

## Lot 0 — Socle
- [ ] Projet Flutter (cibles Android + web), analyse stricte, thème Material 3 (DM Sans / Inter, mode sombre)
- [ ] Supabase local (CLI), `supabase_flutter` configuré, variables d'env (`--dart-define`)
- [ ] Auth email + page de connexion, routes protégées
**Fin :** connexion fonctionne sur Android et sur le web, navigation vers les 5 pages vides.

## Lot 1 — Données
- [ ] Migrations : enums, tables, contraintes, index, RLS
- [ ] Trigger : somme des pourcentages ≤ 100
- [ ] Colonne calculée `transactions.month`
- [ ] Seed : comptes, Fond de sécurité, Épargne générale, catégories, « Frais externes » hors budget, budget « Abonnements »
- [ ] Types TS générés
**Fin :** `supabase db reset` passe, un 2e utilisateur ne voit rien des données du 1er.

## Lot 2 — Cœur métier (tests d'abord)
- [ ] Tests des exemples chiffrés de la spec (§3 normal, négatif, mois particulier)
- [ ] `distribute_savings` + tests de cascade (projet plein → Fond → Épargne générale, complément à 100 %, reliquat d'arrondi → Épargne générale, cascade en mode précis)
- [ ] `close_month` + tests d'idempotence + `total_expenses` hors virement commun
- [ ] `rebalance_from_safety_fund` + test Fond insuffisant (retrait partiel, reste à couvrir renvoyé)
- [ ] `generate_subscription_charges` + tests (31 en février, rejeu sans doublon, mois déjà clôturé)
**Fin :** tous les tests passent, aucune logique de solde côté client.

## Lot 3 — Saisie quotidienne
- [ ] Onboarding : RPC `complete_onboarding` + écran
- [ ] CRUD transactions, filtres mois / catégorie
- [ ] CRUD budgets, vue `budget_status_current_month`
**Fin :** on peut tenir un mois complet à la main.

## Lot 4 — Compléments
- [ ] Abonnements : CRUD, budget « Abonnements » calculé, job pg_cron quotidien
- [ ] Échelonnements (RPC + affichage des mensualités restantes)
- [ ] Projets d'épargne (CRUD, pourcentages, objectifs)
**Fin :** parité fonctionnelle des entités avec Base44.

## Lot 5 — Pages
- [ ] Dashboard complet + alerte négatif + bouton rééquilibrage + modale de transition
- [ ] Pages Budgets, Épargne
- [ ] Distribution : historique + Sankey
- [ ] Reprise des données Base44 (export manuel → script d'import)
**Fin :** l'app remplace Base44 au quotidien.

## Lot 6 — Bonus
- [ ] Widget Android natif (Kotlin / Jetpack Glance) via `home_widget`, basé sur `current_month_summary`
