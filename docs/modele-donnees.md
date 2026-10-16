# Modèle de données — Supabase / Postgres

Toutes les tables : `id uuid pk default gen_random_uuid()`, `user_id uuid not null default auth.uid() references auth.users`, `created_at timestamptz default now()`, RLS `user_id = auth.uid()`.
Montants : `numeric(12,2)`. Mois : `date` = premier jour du mois (check `extract(day from month) = 1`).
Clés étrangères composites `(fk, user_id) → (id, user_id)` : une ligne ne peut pas référencer une ligne d'un autre utilisateur.
Schéma : [supabase/migrations/](../supabase/migrations/) · tests : [supabase/tests/database/](../supabase/tests/database/).

## Droits d'écriture du client
Lecture : ses propres lignes. Écriture accordée colonne par colonne ; tout le reste passe par les RPC.
| Table | Le client peut |
|---|---|
| settings | modifier salaire, virement commun, marge |
| accounts | renommer (jamais `balance`) |
| budgets, subscriptions | tout |
| savings_projects | créer / modifier nom, pourcentage, objectif ; supprimer un projet vide, sauf Fond de sécurité et Épargne générale |
| transactions | créer / modifier / supprimer des `depense` et `revenu` non réglées (jamais `settled`) |
| installment_plans | étaler une dépense (créer, changer le nombre de mois, supprimer) |
| monthly_settlements | lire seulement |

## Données par défaut
Créées à l'inscription (trigger sur `auth.users` → `init_user_data`) : settings, comptes courant + épargne, Fond de sécurité, Épargne générale, budgets Courses, Logement, Transport, Restaurants, Loisirs, Santé, Shopping, Abonnements, Frais externes (hors budget).

## Enums
- `account_type` : `courant`, `epargne` (pas de compte commun : le virement est une dépense « Frais externes »)
- `transaction_type` : `depense`, `revenu`, `transfert_epargne`, `retrait_epargne`, `transfert`
- `distribution_mode` : `automatique`, `precis`
- `settlement_status` : `pending`, `settled`

## settings (1 ligne par utilisateur, pk = user_id)
| Champ | Type | Note |
|---|---|---|
| default_salary | numeric | |
| default_shared_transfer | numeric | prérempli, modifiable à chaque transition |
| safety_margin | numeric | défaut 200 |

## accounts
| Champ | Type | Note |
|---|---|---|
| name | text | |
| type | account_type | un seul compte par type et par utilisateur |
| balance | numeric | modifié **uniquement** par les RPC |

## budgets
| Champ | Type | Note |
|---|---|---|
| category | text | unique (user_id, category) |
| monthly_amount | numeric | ≥ 0 ; ignoré pour « Abonnements » (alloué calculé dans la vue) |
| icon | text | |
| hors_budget | bool | true pour « Frais externes » |

## transactions
| Champ | Type | Note |
|---|---|---|
| date | date | |
| month | date | `generated always as (date_trunc('month', date::timestamp)::date) stored` — le `::timestamp` est obligatoire : sans lui Postgres choisit la variante `timestamptz` de `date_trunc`, non immuable, refusée dans une colonne générée |
| type | transaction_type | |
| amount | numeric | > 0, le sens dépend du type |
| label | text | |
| category | text | |
| account_id | uuid → accounts | compte courant si non renseigné (trigger) |
| target_account_id | uuid → accounts | null sauf transferts |
| hors_budget | bool | défaut false |
| settled | bool | défaut false |
| savings_project_id | uuid → savings_projects | null |
| subscription_id | uuid → subscriptions | null sauf prélèvement d'abonnement |
| settlement_id | uuid → monthly_settlements | clôture qui a réglé ou créé la transaction (salaire, compte commun, épargne) |
| distribution_mode | distribution_mode | null sauf `transfert_epargne` |

Index : (user_id, month), (user_id, category, month), unique (subscription_id, date) — permet de rejouer la génération des prélèvements sans doublon.

## savings_projects
| Champ | Type | Note |
|---|---|---|
| name | text | |
| percentage | numeric(5,2) | 0–100, somme ≤ 100 (vérifiée par trigger) |
| target_amount | numeric | null = sans plafond |
| current_amount | numeric | ≥ 0 |
| is_default | bool | Épargne générale, un seul (index unique partiel) ; pourcentage 0 et sans plafond |
| is_safety_fund | bool | Fond de sécurité, un seul (index unique partiel) |
| icon | text | nom d'icône (mêmes noms que les budgets) |

## subscriptions
| Champ | Type | Note |
|---|---|---|
| name | text | |
| amount | numeric | > 0 |
| billing_day | int | 1–31 ; ramené au dernier jour du mois si besoin |
| category | text | budget du prélèvement, défaut « Abonnements » ; suit le renommage du budget, revient à « Abonnements » s'il est supprimé |
| last_charge_date | date | dernier prélèvement généré : un par mois au plus, jamais recréé |
| active | bool | |

## installment_plans
| Champ | Type | Note |
|---|---|---|
| transaction_id | uuid → transactions | unique ; supprimé avec la dépense |
| installments | int | 2–120 |

Étalement d'une dépense sur son budget (spec §6) : montant, catégorie et mois de départ viennent de la transaction. Mensualité de rang i : `installment_share(montant, N, i)` = montant / N tronqué au centime, **reliquat d'arrondi sur la dernière**. Trigger `check_installment_plan` : seule une `depense` avec catégorie et hors `hors_budget` (`FF004`).

## monthly_settlements
| Champ | Type | Note |
|---|---|---|
| month | date | unique (user_id, month) |
| status | settlement_status | un seul `pending` par utilisateur (index unique partiel) |
| salary | numeric | |
| shared_transfer | numeric | |
| total_expenses | numeric | |
| total_savings | numeric | |
| opening_balance | numeric | courant avant la clôture (null avant le lot 5) |
| closing_balance | numeric | courant après la clôture |
| special_month | bool | |

## RPC
| Fonction | Rôle |
|---|---|
| `close_month(p_month, p_salary, p_shared_transfer, p_special_month)` | Transition complète (spec §3) ; renvoie totaux et solde courant |
| `preview_close_month(p_salary, p_shared_transfer, p_special_month)` | Aperçu de la transition sans écriture, mêmes formules (testé contre `close_month`) |
| `rebalance_from_safety_fund()` | Ramène le courant vers 0 depuis le Fond de sécurité, retrait partiel si insuffisant ; renvoie montant retiré et reste à couvrir (spec §4) |
| `create_savings_project(p_name, p_percentage, p_target, p_initial_amount, p_icon)` | Crée un projet, avec reprise d'un montant déjà épargné |
| `save_to_savings(p_amount, p_mode, p_project_id)` | Versement manuel du courant vers l'épargne |
| `adjust_savings_project(p_project_id, p_amount)` | Correction du montant d'un projet (recalage sur la banque) : le compte épargne suit, le courant ne bouge pas |
| `private.distribute_savings(p_user, p_amount, p_mode, p_project_id, p_date)` | Interne : vire du courant vers l'épargne et répartit (spec §5) ; appelée par `close_month` et la future saisie manuelle |
| `private.generate_subscription_charges(p_date)` | Interne, tous utilisateurs : crée les prélèvements dus du mois de `p_date` et du mois précédent, jamais avant la création de l'abonnement ; idempotent via l'index unique |
| `complete_onboarding(p_courant, p_safety_fund, p_general_savings)` | Soldes de départ, ouvre le mois en cours ; une seule fois (spec §9) |

Le schéma `private` n'est pas exposé par l'API ; seules les fonctions de `public` listées ci-dessus sont appelables par le client.
Erreurs métier (SQLSTATE) : `FF001` mois pas en cours · `FF002` mois suivant existant · `FF003` projet d'épargne inconnu · `FF004` montant invalide · `FF005` onboarding déjà fait · `FF006` budget système (Abonnements, Frais externes) non renommable ni supprimable.
Renommer un budget renomme ses transactions (trigger `budget_category_change`).
Sens des transferts : `transfert_epargne` courant → épargne, `retrait_epargne` épargne → courant (`account_id` → `target_account_id`).

## Tâches planifiées (pg_cron)
- `finflow-subscription-charges`, chaque jour à 4 h UTC : `private.generate_subscription_charges` (date du jour à Paris)

## Vues
- `budget_lines_current_month` (security invoker) : par budget, chaque contribution du mois `pending` au consommé → dépense (+), revenu (−), ou mensualité d'une dépense étalée (`installment_number` / `installments`)
- `budget_status_current_month` (security invoker) : par budget → alloué (pour « Abonnements » : somme de ses abonnements actifs), dépensé (Σ des lignes), reste, `reserved` (abonnements de la catégorie pas encore prélevés ce mois-ci), `installment_spent` (part du dépensé due aux mensualités d'étalement)
- `settlement_flows` (security invoker) : par mois clôturé, chaque flux entrant (solde de départ, salaire, autres revenus, découvert final) et sortant (dépenses par catégorie, compte commun, épargne par projet, courant restant, découvert comblé) ; Σ entrées = Σ sorties
- `installment_plans_status` (security invoker) : par dépense étalée → mensualité, rang au mois en cours, mensualités restantes, montant restant à imputer
- `current_month_summary` (security invoker) : mois en cours, soldes, dépenses − revenus non réglés (ce que réglera la transition), marge, salaire et virement commun habituels (`settings`, sinon ceux du mois en cours), reste des budgets, `projected_savings` (épargne prévue à la clôture) et `projected_savings_budgets` (si budgets épuisés) — base du widget
