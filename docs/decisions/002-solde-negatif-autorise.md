# 002 — Solde courant négatif autorisé
**Contexte :** si les dépenses dépassent le disponible, le virement épargne serait négatif.
**Décision :** pas de retrait automatique. Le virement épargne vaut 0, le courant peut passer sous 200 € voire en négatif. Alerte dashboard si `< 0`, avec bouton « Rétablir l'équilibre » qui retire depuis le **Fond de sécurité** pour ramener le courant à **0**.
**Conséquence :** l'utilisateur garde la main sur les retraits d'épargne.
