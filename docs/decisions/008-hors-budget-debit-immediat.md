# 008 — Hors budget ignoré, débit immédiat, fin de « Frais externes »
*2026-11-03, révisé le 2026-11-04 : l'échelonnement ne touche plus le courant, et le hors budget est de nouveau déduit (ADR 010).*
**Contexte :** à l'usage, trois règles ne collaient pas à la réalité du compte. Une dépense hors budget (payée par ailleurs, avancée pour quelqu'un) était quand même déduite du courant à la clôture. Une dépense payée en plusieurs fois (paiement en 4×) sortait en entier à la clôture de son mois, alors que la banque n'en prélève qu'une fraction par mois. Et une dépense réglée par virement ou prélèvement sort du courant tout de suite, pas avec le débit différé de la carte. La catégorie « Frais externes » ne servait plus qu'au virement compte commun.
**Décision :**
- hors budget = ignoré : réglé à la clôture (figé) sans être déduit, récap dans la modale ;
- `transactions.immediate` : un trigger débite le courant à la saisie et suit modifications et suppressions tant que la dépense n'est pas réglée ; la clôture la compte dans le mois sans la redébiter ;
- ~~une dépense échelonnée n'est débitée que par mensualités~~ : abandonné le 2026-11-04. La dépense est faite une fois et sort en entier ; l'échelonnement n'étale que son poids sur le budget. Les dépenses réglées entre-temps par mensualités ont été corrigées (reste débité du courant, totaux et soldes des clôtures recalés) et `installment_charges` supprimée ;
- le virement compte commun devient un `transfert` sans catégorie et le budget « Frais externes » est supprimé.
**Conséquence :** `transactions.deducted` distingue ce qu'une clôture a vraiment déduit ; tout ce qui a été réglé avant ce lot l'a été en entier (`deducted = true`). Les flux (Sankey) restent équilibrés pour l'historique.
