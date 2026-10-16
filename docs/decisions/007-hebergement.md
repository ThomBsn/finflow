# 007 — Hébergement
**Contexte :** un serveur perso capable de faire tourner des conteneurs est disponible ; Supabase couvre déjà base, auth et logique métier.
**Décision :**
- **Supabase Cloud** (offre gratuite) en production : Postgres, Auth, RPC, pg_cron. Projet `ewesrsdeqiuimnvtmdrt` (ancien test « myfinance » réutilisé, eu-central-1), mis en service le 2026-10-16. Le développement se fait sur le Supabase local (CLI).
- **Inscriptions fermées** sur le projet cloud : la clé publishable est embarquée dans l'APK et le site, n'importe qui pourrait sinon créer un compte.
- **Serveur perso** (VPS Oracle, alias SSH `oracle`) : un conteneur Caddy sert le build Flutter web sur `127.0.0.1:8081`, publié **uniquement sur le tailnet** par `tailscale serve` : https://oracle.tail7f1a74.ts.net. Rien n'est exposé sur internet ; la version web sert depuis l'ordinateur, le téléphone utilise l'app.
- **Pas d'API maison** tant qu'aucun besoin réel n'apparaît (ex. appel à un service tiers).
- **Pas de SMTP perso** : le SMTP par défaut de Supabase suffit pour un seul utilisateur (envoi limité, réservé aux membres du projet).
**Conséquences :**
- Un projet gratuit est mis en pause après 7 jours sans activité ; un usage quotidien l'évite.
- Connexion par mot de passe : aucune URL de redirection Auth n'est nécessaire (elle le deviendrait pour les e-mails de réinitialisation).
- Si l'app s'ouvre à d'autres utilisateurs, brancher un SMTP sur le serveur perso.
