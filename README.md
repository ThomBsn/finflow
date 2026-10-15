# FinFlow

Gestion de budget mensuel perso. Client Flutter (Android + web), backend Supabase.
Docs : [spec métier](docs/spec-metier.md) · [modèle de données](docs/modele-donnees.md) · [roadmap](docs/roadmap.md) · [décisions](docs/decisions/).

## Démarrage local

Prérequis : Flutter, Docker Desktop lancé, CLI Supabase.

```sh
supabase start                       # Postgres + Auth + Studio (http://127.0.0.1:54323)
cp env/local.example.json env/local.json   # puis coller PUBLISHABLE_KEY de `supabase status`
```

Web :

```sh
flutter run -d chrome --dart-define-from-file=env/local.json
```

Téléphone Android (USB) — le téléphone joint Supabase via le tunnel adb :

```sh
adb reverse tcp:54321 tcp:54321
flutter run --dart-define-from-file=env/local.json
```

Dans VS Code, la config de lancement « FinFlow (local) » passe déjà les variables.
