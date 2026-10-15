# 007 — Hébergement
**Contexte :** un serveur perso capable de faire tourner des conteneurs est disponible ; Supabase couvre déjà base, auth et logique métier.
**Décision :**
- **Supabase Cloud** (offre gratuite) en production : Postgres, Auth, RPC, pg_cron. Le développement se fait sur le Supabase local (CLI).
- **Serveur perso** : un conteneur statique (nginx ou Caddy) sert le build Flutter web.
- **Pas d'API maison** tant qu'aucun besoin réel n'apparaît (ex. appel à un service tiers).
- **Pas de SMTP perso** : le SMTP par défaut de Supabase suffit pour un seul utilisateur (envoi limité, réservé aux membres du projet).
**Conséquences :**
- Un projet gratuit est mis en pause après 7 jours sans activité ; un usage quotidien l'évite.
- L'URL du site web devra être ajoutée aux URLs de redirection Auth du projet Supabase.
- Si l'app s'ouvre à d'autres utilisateurs, brancher un SMTP sur le serveur perso.
