/// Configuration injectée au build via `--dart-define-from-file=env/local.json`.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static void ensureConfigured() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY manquants : '
        'lancer avec --dart-define-from-file=env/local.json',
      );
    }
  }
}
