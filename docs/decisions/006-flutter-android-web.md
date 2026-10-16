# 006 — Client Flutter, Android d'abord, web en complément
**Contexte :** usage principal sur téléphone Android, avec un widget d'écran d'accueil natif. Une version web pour l'ordinateur est un plus. Pas d'iPhone.
**Décision :** une seule app Flutter ciblant Android et le web, avec `supabase_flutter`. Le widget est écrit en Kotlin et reçoit ses données de l'app via le paquet `home_widget`.
**Révisé le 2026-10-16 :** widget en `RemoteViews` (layout XML + `HomeWidgetProvider`) plutôt qu'en Jetpack Glance : pour un affichage de quelques textes, Glance imposait d'ajouter Compose au build Android sans rien apporter.
**Alternatives écartées :**
- Kotlin / Compose seul : meilleure intégration Android, mais pas de version web mûre.
- React + Capacitor : excellent web, mais rendu mobile moins natif et widget plus artisanal.
**Conséquences :**
- Toute la logique de solde reste dans les RPC Postgres ; le client ne fait qu'afficher et appeler.
- Le Sankey (page Distribution) sera peut-être dessiné à la main (`CustomPainter`).
- La version web de Flutter est plus lourde au chargement, ce qui est acceptable pour un usage perso.
