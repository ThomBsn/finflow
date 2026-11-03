# Spécification métier — FinFlow

## 1. Principe
Le salaire arrive en début de mois. Les dépenses sont **suivies** au fil du mois sans toucher le solde du compte courant. Une action unique, **« Passer au mois suivant »**, clôture le mois et ouvre le suivant.

Constante : `SAFETY_MARGIN = 200 €` (stockée dans `settings.safety_margin`).

## 2. Pendant le mois
- L'utilisateur saisit dépenses et revenus. Une dépense a `settled = false` tant que le mois n'est pas clôturé.
- Un **revenu** saisi en cours de mois (remboursement, prime…) vient **en déduction des dépenses** : il augmente d'autant l'épargne du mois.
- Le solde affiché du compte courant ne bouge pas avec les dépenses, sauf une dépense en **débit immédiat** (virement, prélèvement… hors carte à débit différé) : elle sort du courant dès sa saisie (et y revient si on la modifie ou la supprime avant la clôture).
- La page Dépenses montre le mois en cours ; décocher « Mois en cours » affiche l'historique (tous les mois ou un mois choisi), y compris les dépenses du mois suivant saisies avant la clôture.
- Banque : carte à **débit différé**. Les dépenses carte sont cumulées et prélevées en une fois le 4 du mois suivant, mais la période cumulée ne suit pas le calendrier (ex. du 29/09 au 28/10 pour le débit du 4/11) et sa date de coupure varie. Le salaire arrive vers le 27/28 ; la marge de 200 € n'absorbe que les prélèvements immédiats (abonnements). On clôture donc le mois **le 4**, une fois le débit différé passé.
- Chaque dépense ou revenu porte son **mois de débit** (`month`) : le mois dont la clôture le réglera. Il est prérempli avec le mois en cours (même pour une dépense datée du mois suivant, saisie avant la bascule) et se change à la saisie, typiquement pour reporter au mois suivant une dépense des derniers jours, hors de la période déjà cumulée. Budgets, filtres et clôture suivent ce mois, pas la date.
- Le dashboard et le widget affichent l'**épargne prévue** = ce que la prochaine clôture mettra de côté, recalculée à chaque saisie :
  `courant + salaire habituel − virement commun habituel − dépenses non réglées − marge`.
  Négative : aucune épargne et le courant passera sous la marge d'autant. Une seconde valeur suppose les budgets dépensés jusqu'au bout (reste des enveloppes, abonnements à venir compris).
- Salaire et virement commun habituels se règlent dans **Réglages** (sinon ceux du mois en cours) et préremplissent la clôture.

## 3. Transition « Passer au mois suivant » (RPC `close_month`)
Paramètres (préremplis depuis `settings`, modifiables dans la modale) :
- `month` : le mois à clôturer (le mois en cours affiché) — rend l'appel idempotent
- `salary` : salaire du nouveau mois
- `shared_transfer` : virement compte commun du nouveau mois (variable chaque mois)
- `special_month` : booléen « Mois particulier »

Étapes, **dans cet ordre**, dans une seule transaction :
1. **Dépenses du mois M** : toutes les dépenses et revenus non réglés de mois de débit `month = M` (les « Dépenses nettes » du mois dans la page Dépenses) passent `settled = true`, et
   `courant -= (dépenses − revenus)` hors budget compris (§7), en excluant les **débits immédiats** (déjà sortis du courant). Une dépense échelonnée est déduite **en entier** (l'échelonnement ne concerne que le budget, §6).
   Une transaction non réglée d'un mois déjà clôturé (antérieure au mois de débit saisi) n'est ni comptée ni réglée ; un prélèvement d'abonnement tardif prend le mois en cours comme mois de débit.
   La modale affiche le récap des transactions hors budget du mois, avec leur remboursement depuis l'épargne (bouton « Rembourser » sur celles qui ne le sont pas).
2. **Salaire M+1** : création d'une transaction `salaire` (pas un revenu du mois), `courant += salary`.
3. **Compte commun M+1** : création d'un `transfert` « Virement compte commun » sans catégorie, `settled = true`, `courant -= shared_transfer`.
4. **Épargne** (sauté si `special_month`) :
   `savings = courant − SAFETY_MARGIN`
   - si `savings > 0` : transfert vers l'épargne, distribué selon §5 → `courant = 200`
   - si `savings ≤ 0` : aucun transfert, le courant reste tel quel (peut être < 200 ou négatif)
5. **Clôture** : `monthly_settlements` de M → `settled` (avec totaux), création de M+1 en `pending`.
   `total_expenses` = dépenses comptées dans le mois : montant net déduit à l'étape 1, plus les débits immédiats réglés (et `opening_balance` les rajoute au courant de départ, pour que les flux les montrent). Le virement compte commun (déjà `settled = true`, stocké dans `shared_transfer`) n'y est **pas** compté.

Garde-fous : refus si M n'est pas `pending` (`FF001`, ex. double clic) ou si M+1 existe déjà (`FF002`).
Le salaire et le virement commun de M+1 sont créés réglés : ils ne repassent pas à la clôture suivante.

### Exemple chiffré (à transformer en test)
Courant avant transition = 350 · dépenses M = 1 400 · salaire = 2 500 · commun = 600
→ après 1 : −1 050 · après 2 : 1 450 · après 3 : 850 · épargne = 850 − 200 = **650** · courant final = **200**
(Formule équivalente : `salary − (dépenses + commun + (200 − courant_avant))` = 2 500 − (2 000 − 150) = 650.)

### Exemple négatif
Courant avant = 100 · dépenses M = 2 300 · salaire = 2 500 · commun = 600
→ 100 − 2 300 + 2 500 − 600 = **−300** · épargne = 0 · courant final = **−300** → alerte.

Salaire, virement compte commun et virements d'épargne (versements, retraits, remboursements) sont des **mouvements**, pas des dépenses : ils n'entrent dans aucun total de dépenses. La page Dépenses les masque par défaut (puce « Salaire et virements ») ; la page Distribution en fait le récap par clôture.

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
- **Mode `precis`** : tout va au projet choisi (`savings_project_id`).
- **Versement manuel** (« Épargner maintenant », ou « Virement » courant → épargne à la saisie d'une transaction ; RPC `save_to_savings`) : débite le courant tout de suite, en mode automatique ou précis.
- **Retrait** (« Virement » épargne → courant à la saisie d'une transaction ; RPC `withdraw_from_savings`) : crédite le courant tout de suite. Depuis un projet choisi, dans la limite de son montant ; sans projet, Épargne générale d'abord, puis les autres projets, le Fond de sécurité en dernier. Refusé si l'épargne ne suffit pas. Ce qui n'est pas dépensé repart en épargne à la clôture suivante.
- **Nouveau projet** : un montant « déjà épargné » peut être repris (projet existant ailleurs) ; il crédite le compte épargne sans toucher au courant.
- **Correction du montant** d'un projet (y compris Fond de sécurité et Épargne générale), pour le caler sur la banque : le compte épargne suit, le courant ne bouge pas. Chaque projet a une icône.
- **Débordement en cascade** (dans les deux modes) : si un projet atteint `target_amount`, l'excédent va au **Fond de sécurité** ; s'il est plein, à **Épargne générale** (sans plafond).
- Invariant : solde du compte épargne = somme des `current_amount` des projets.

## 6. Budgets
- Un budget = une catégorie + un montant mensuel alloué + une icône.
- Le mois affiché est le mois en cours (`pending`), pas le mois calendaire.
- Consommé du mois = dépenses − revenus de la catégorie sur le mois, **hors `hors_budget`** (un budget lui-même hors budget affiche ses propres dépenses sans enveloppe).
- Renommer un budget renomme aussi ses transactions. « Abonnements » est utilisé par l'app : ni renommable ni supprimable.
- À la saisie d'une dépense, chaque catégorie montre une mini-jauge de son budget du mois et ce qu'il reste.
- **Abonnements** (prélèvements automatiques à montant fixe) : chacun est rangé dans un budget, **« Abonnements »** par défaut (ex. assurance moto → Véhicule).
  - Alloué du budget « Abonnements » = somme de ses abonnements actifs (calculé, non saisi) ; les autres budgets gardent leur montant saisi.
  - Chaque budget **réserve** les abonnements de sa catégorie pas encore prélevés ce mois-ci ; l'épargne prévue « budgets épuisés » les compte même si l'enveloppe est trop petite.
  - Le jour `billing_day` de chaque mois, une tâche planifiée crée une `depense` (catégorie et « hors budget » de son budget, `settled = false`, `subscription_id` renseigné). Si ce jour n'existe pas dans le mois (ex. 31 en février), on prend le dernier jour du mois.
  - Au plus un prélèvement par abonnement et par mois ; un prélèvement supprimé n'est pas recréé, et un abonnement créé après son jour de prélèvement démarre le mois suivant.
  - Ces dépenses comptent dans le consommé du budget Abonnements.
  - Création, modification et suppression depuis l'onglet Abonnements de la page Dépenses.
- **Échelonnements** : étalement d'une dépense **sur son budget**, pour qu'une grosse dépense ne bloque pas l'enveloppe d'un mois entier.
  - La dépense est faite une fois : elle est déduite **en entier** du courant à la clôture de son mois de débit (ou tout de suite en débit immédiat).
  - Le budget de sa catégorie ne compte qu'une mensualité par mois pendant N mois à partir de son mois de débit : montant / N tronqué au centime, reliquat sur la dernière.
  - Activé depuis la dépense (« Étaler sur le budget »), uniquement pour une dépense comptée dans un budget (ni revenu, ni hors budget). Modifier la dépense met l'étalement à jour ; la supprimer le supprime ; « ne plus étaler » la fait compter en entier dans son mois.
- **Jauge d'un budget** : mensualités d'étalement (orange, déjà engagées), autres dépenses (bleu), abonnements à venir (vert d'eau), puis le disponible ; au-delà de l'enveloppe, un trait marque l'alloué.
- **Composition d'un budget** : pour le mois en cours, chaque dépense, revenu déduit ou mensualité qui compose le consommé, avec sa part de l'enveloppe.

## 7. Hors budget
- `hors_budget = true` : exclue des **enveloppes** seulement. La dépense sort bien du compte : elle est déduite du courant à la transition (ou tout de suite en débit immédiat) et comptée dans l'épargne prévue.
- Cas typique : une avance (cadeau commun payé par carte) qu'on se rembourse depuis l'épargne. Bouton **« Rembourser depuis l'épargne »** sur la dépense (et dans le récap de clôture) : retrait d'épargne vers le courant, depuis un projet ou en cascade (§5), relié à la dépense (`reimburses_id`) ; la dépense affiche « remboursée ».
- Incompatible avec l'étalement sur le budget.
- Il n'y a plus de catégorie « Frais externes » : le virement compte commun est un transfert (§3).

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
| Dépenses | Onglets transactions / abonnements / échelonnements (CRUD), filtres « Mois en cours » (ou historique : tous les mois ou un mois) + catégorie |
| Budgets | Alloué vs dépensé vs reste par catégorie |
| Épargne | Projets, pourcentages, progression vers objectifs |
| Distribution | Par mois clôturé : dépenses, épargne, courant ensuite ; Sankey « d'où vient / où est allé l'argent » (salaire, revenus, solde de départ → dépenses par catégorie, compte commun, épargne par projet, courant restant) et tableau des flux |
