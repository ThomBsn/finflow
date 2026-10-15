# 005 — Fond de sécurité insuffisant au rééquilibrage
**Contexte :** « Rétablir l'équilibre » retire `−courant` du Fond de sécurité, qui peut ne pas suffire.
**Décision :** retrait partiel de ce qui est disponible ; la RPC renvoie le reste à couvrir, affiché à l'utilisateur. Pas de retrait automatique sur Épargne générale ni sur un autre projet.
**Conséquence :** le courant peut rester négatif après rééquilibrage ; l'alerte reste affichée et l'utilisateur couvre le reste lui-même.
