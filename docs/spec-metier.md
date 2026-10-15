# Spécification métier — FinFlow

## 1. Principe
Le salaire arrive en début de mois. Les dépenses sont **suivies** au fil du mois sans toucher le solde du compte courant. Une action unique, **« Passer au mois suivant »**, clôture le mois et ouvre le suivant.

Constante : `SAFETY_MARGIN = 200 €` (stockée dans `settings.safety_margin`).

## 2. Pendant le mois
- L'utilisateur saisit dépenses et revenus. Une dépense a `settled = false` tant que le mois n'est pas clôturé.
- Un **revenu** saisi en cours de mois (remboursement, prime…) vient **en déduction des dépenses** : il augmente d'autant l'épargne du mois.
- Le solde affiché du compte courant ne bouge pas avec les dépenses.
- Le dashboard affiche en plus un **« disponible estimé »** = solde courant − dépenses non réglées du mois.

## 3. Transition « Passer au mois suivant » (RPC `close_month`)
Paramètres (préremplis depuis `settings`, modifiables dans la modale) :
- `month` : le mois à clôturer (le mois en cours affiché) — rend l'appel idempotent
- `salary` : salaire du nouveau mois
- `shared_transfer` : virement compte commun du nouveau mois (variable chaque mois)
- `special_month` : booléen « Mois particulier »

Étapes, **dans cet ordre**, dans une seule transaction :
1. **Dépenses du mois M** : `courant -= (dépenses − revenus) non réglés avec month ≤ M` (hors budget inclus), puis `settled = true`.
   Le `≤` rattrape une dépense datée d'un mois déjà clôturé (ex. prélèvement d'abonnement créé par la tâche planifiée après une clôture anticipée).
2. **Salaire M+1** : création d'une transaction `revenu`, `courant += salary`.
3. **Compte commun M+1** : création d'une `depense` catégorie « Frais externes », `hors_budget = true`, `settled = true`, `courant -= shared_transfer`.
4. **Épargne** (sauté si `special_month`) :
   `savings = courant − SAFETY_MARGIN`
   - si `savings > 0` : transfert vers l'épargne, distribué selon §5 → `courant = 200`
   - si `savings ≤ 0` : aucun transfert, le courant reste tel quel (peut être < 200 ou négatif)
5. **Clôture** : `monthly_settlements` de M → `settled` (avec totaux), création de M+1 en `pending`.
   `total_expenses` = montant net réglé à l'étape 1 (dépenses − revenus). Le virement compte commun (déjà `settled = true`, stocké dans `shared_transfer`) n'y est **pas** compté.

Garde-fous : refus si M n'est pas `pending` (`FF001`, ex. double clic) ou si M+1 existe déjà (`FF002`).
Le salaire et le virement commun de M+1 sont créés réglés : ils ne repassent pas à la clôture suivante.

### Exemple chiffré (à transformer en test)
Courant avant transition = 350 · dépenses M = 1 400 · salaire = 2 500 · commun = 600
→ après 1 : −1 050 · après 2 : 1 450 · après 3 : 850 · épargne = 850 − 200 = **650** · courant final = **200**
(Formule équivalente : `salary − (dépenses + commun + (200 − courant_avant))` = 2 500 − (2 000 − 150) = 650.)

### Exemple négatif
Courant avant = 100 · dépenses M = 2 300 · salaire = 2 500 · commun = 600
→ 100 − 2 300 + 2 500 − 600 = **−300** · épargne = 0 · courant final = **−300** → alerte.

## 4. Solde négatif et rééquilibrage
- Le compte courant **peut être négatif**.
- **Alerte dashboard** dès que `courant < 0`, avec un bouton **« Rétablir l'équilibre »**.
- RPC `rebalance_from_safety_fund()` : crée un `retrait_epargne` depuis le projet **Fond de sécurité** d'un montant `= −courant` → courant = **0**.
- Si le Fond de sécurité ne suffit pas : **retrait partiel** de ce qui est disponible, message indiquant le reste à couvrir. Aucun retrait automatique sur un autre projet ; l'alerte reste affichée tant que `courant < 0`.
- La RPC renvoie le montant retiré et le reste à couvrir.

## 5. Distribution de l'épargne
- **Mode `automatique`** : répartition selon `savings_projects.percentage`.
  - La somme des pourcentages doit être **≤ 100**. Le complément à 100 % va à **Épargne générale** (`is_default`).
  - Montants arrondis au centime ; le **reliquat d'arrondi** va à **Épargne générale**.
  - Mode utilisé par `close_month`.
- **Mode `precis`** : saisie manuelle d'un versement d'épargne, tout va au projet choisi (`savings_project_id`).
- **Débordement en cascade** (dans les deux modes) : si un projet atteint `target_amount`, l'excédent va au **Fond de sécurité** ; s'il est plein, à **Épargne générale** (sans plafond).
- Invariant : solde du compte épargne = somme des `current_amount` des projets.

## 6. Budgets
- Un budget = une catégorie + un montant mensuel alloué + une icône.
- Le mois affiché est le mois en cours (`pending`), pas le mois calendaire.
- Consommé du mois = dépenses − revenus de la catégorie sur le mois, **hors `hors_budget`** (un budget lui-même hors budget, comme Frais externes, affiche ses propres dépenses sans enveloppe).
- Renommer un budget renomme aussi ses transactions. « Abonnements » et « Frais externes » sont utilisés par l'app : ni renommables ni supprimables.
- **Abonnements** : tous dans la catégorie unique **« Abonnements »** (budget créé par le seed).
  - Alloué du budget = somme des `amount` des abonnements actifs (calculé, non saisi).
  - Le jour `billing_day` de chaque mois, une tâche planifiée crée une `depense` (catégorie Abonnements, `settled = false`, `subscription_id` renseigné). Si ce jour n'existe pas dans le mois (ex. 31 en février), on prend le dernier jour du mois.
  - Ces dépenses comptent dans le consommé du budget Abonnements.
  - Création, modification et suppression depuis l'onglet Abonnements de la page Dépenses.
- **Échelonnements** : une grosse dépense répartie sur N mois. Chaque mensualité est une transaction du mois concerné et **compte dans le budget de ce mois**.
  Génération : les N transactions sont créées à la création du plan (une par mois, à partir de `start_month`).

## 7. Hors budget
- `hors_budget = true` : exclu des enveloppes, mais déduit du courant à la transition (ce qui réduit d'autant l'épargne du mois).
- La catégorie **« Frais externes »** (dont le compte commun) est toujours hors budget.

## 8. Mois particulier
Case à cocher dans la modale de transition : étapes 1, 2, 3 et 5 normales, **étape 4 sautée**. Le surplus reste sur le courant pour ajustement manuel.

## 9. Onboarding
Au premier lancement, en cours de mois (RPC `complete_onboarding`) :
- solde du courant **après** la transition du mois (prérempli avec la marge de sécurité, modifiable) ;
- soldes du Fond de sécurité et d'Épargne générale (les autres projets viendront avec la reprise Base44) ;
- ouverture du mois en cours (heure de Paris) en `pending`.

Pas de salaire demandé : il est saisi dans la modale de transition. Ensuite, l'utilisateur saisit les dépenses faites depuis le début du mois, **sauf** le virement compte commun et l'épargne du mois, déjà inclus dans le solde de départ.

## 10. Pages
| Page | Contenu |
|---|---|
| Onboarding | Soldes de départ (premier lancement uniquement) |
| Dashboard | Soldes, alerte négatif + rééquilibrage, résumé du mois, budgets, abonnements, échelonnements, projets d'épargne, transactions récentes, bouton de transition |
| Dépenses | Onglets transactions / abonnements (CRUD), filtres mois + catégorie |
| Budgets | Alloué vs dépensé vs reste par catégorie |
| Épargne | Projets, pourcentages, progression vers objectifs |
| Distribution | Historique des clôtures, Sankey de répartition du salaire |
