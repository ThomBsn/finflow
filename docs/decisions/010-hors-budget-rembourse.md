# 010 — Hors budget déduit, remboursé depuis l'épargne
*2026-11-04. Révise ADR 008 sur le hors budget.*
**Contexte :** « hors budget = ignoré » (ADR 008) ne collait pas au vrai usage : une dépense hors budget est le plus souvent une avance payée par carte (ex. cadeau commun), qu'on se rembourse ensuite par un virement depuis l'épargne. La carte la débite ; l'ignorer surestimait le courant et l'épargne virée à la clôture, et le remboursement la compensait une seconde fois.
**Décision :** une dépense hors budget est exclue des budgets seulement ; elle est déduite du courant à la clôture comme les autres (et peut être en débit immédiat). Le remboursement est un retrait d'épargne (`withdraw_from_savings`, projet au choix ou cascade) relié à la dépense par `transactions.reimburses_id`, lancé depuis la dépense ou le récap de clôture.
**Conséquence :** `deducted` est de nouveau toujours vrai à la clôture. Le récap de clôture montre chaque hors budget avec son remboursement.
