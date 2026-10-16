import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/router.dart';

/// Affichée quand le serveur Supabase ne répond pas au démarrage.
class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  /// Version de développement branchée sur le Supabase local du Mac.
  static final _isLocal = Env.supabaseUrl.contains('127.0.0.1');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Serveur injoignable',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLocal
                      ? 'Vérifie que Docker et Supabase tournent sur le Mac, et '
                            'sur téléphone que le tunnel USB est actif '
                            '(adb reverse tcp:54321 tcp:54321).'
                      : 'Vérifie ta connexion internet.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.read(onboardingGateProvider).retry(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
