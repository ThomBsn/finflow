# Roadmap — FinFlow

Règle : un lot n'est terminé que si ses critères de fin sont tous cochés. Mettre à jour ce fichier en fin de lot.

## Lot 0 — Socle
- [x] Projet Flutter (cibles Android + web), analyse stricte, thème Material 3 (DM Sans / Inter, mode sombre)
- [x] Supabase local (CLI), `supabase_flutter` configuré, variables d'env (`--dart-define`)
- [x] Auth email + page de connexion, routes protégées
**Fin :** connexion fonctionne sur Android et sur le web, navigation vers les 5 pages vides.

## Lot 1 — Données
- [x] Migrations : enums, tables, contraintes, index, RLS
- [x] Trigger : somme des pourcentages ≤ 100
- [x] Colonne calculée `transactions.month`
- [x] Données par défaut à l'inscription (trigger) : comptes, Fond de sécurité, Épargne générale, catégories, « Frais externes » hors budget, budget « Abonnements »
**Fin :** les migrations s'appliquent sur une base vierge, un 2e utilisateur ne voit rien des données du 1er (`supabase test db`).

## Lot 2 — Cœur métier (tests d'abord)
- [x] Tests des exemples chiffrés de la spec (§3 normal, négatif, mois particulier)
- [x] `distribute_savings` + tests de cascade (projet plein → Fond → Épargne générale, complément à 100 %, reliquat d'arrondi → Épargne générale, cascade en mode précis)
- [x] `close_month` + tests d'idempotence + `total_expenses` hors virement commun
- [x] `rebalance_from_safety_fund` + test Fond insuffisant (retrait partiel, reste à couvrir renvoyé)
- [x] `generate_subscription_charges` + tests (31 en février, rejeu sans doublon, mois déjà clôturé)
**Fin :** tous les tests passent, aucune logique de solde côté client.

## Lot 3 — Saisie quotidienne
- [x] Modèles Dart des tables utilisées (écrits à la main : le CLI Supabase ne génère pas de types Dart)
- [x] Onboarding : RPC `complete_onboarding` + écran
- [x] CRUD transactions, filtres mois / catégorie
- [x] CRUD budgets, vue `budget_status_current_month`
**Fin :** on peut tenir un mois complet à la main.

## Lot 3 bis — Transition (avancé du lot 5, nécessaire au 1er novembre)
- [x] Modale « Passer au mois suivant » : salaire et virement commun préremplis avec les valeurs du mois précédent, case « Mois particulier », aperçu calculé par la base
- [x] Dashboard minimal : soldes, disponible estimé, bouton de transition, alerte négatif + rééquilibrage

## Lot 4 — Compléments
- [x] Abonnements : CRUD, budget « Abonnements » calculé, job pg_cron quotidien
- [x] Échelonnements : étalement d'une dépense sur son budget, suivi des mensualités
- [x] Composition d'un budget du mois (part de chaque dépense / mensualité)
- [x] Projets d'épargne (CRUD, pourcentages, objectifs)
**Fin :** parité fonctionnelle des entités avec Base44.

## Lot 5 — Pages
- [ ] Dashboard complet + alerte négatif + bouton rééquilibrage + modale de transition
- [ ] Pages Budgets, Épargne
- [ ] Distribution : historique + Sankey
- [ ] Reprise des données Base44 : à la main dans l'app (dépenses, budgets, projets)
- [ ] Mise en production : projet Supabase Cloud (migrations + job pg_cron), web servi par un conteneur sur le serveur perso, APK release sur le téléphone
**Fin :** l'app remplace Base44 au quotidien.

## Lot 6 — Bonus
- [ ] Widget Android natif (Kotlin / Jetpack Glance) via `home_widget`, basé sur `current_month_summary`
