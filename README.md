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

## Production (Supabase Cloud)

Projet `ewesrsdeqiuimnvtmdrt` (« myfinance », région eu-central-1), lié au repo par `supabase link`.
La config client est dans `env/prod.json` (non versionné) : URL du projet + clé publishable
(`supabase projects api-keys --project-ref ewesrsdeqiuimnvtmdrt`).

Migrations : tester en local (`supabase test db`), puis

```sh
supabase db push --linked --dry-run   # vérifier la liste
supabase db push --linked
```

APK pour le téléphone (signé avec la clé de debug du Mac, suffisant hors Play Store) :

```sh
flutter build apk --release --dart-define-from-file=env/prod.json
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Le Supabase local ne sert plus qu'au développement : les vraies données sont dans le cloud.
