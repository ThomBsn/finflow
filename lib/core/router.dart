import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/providers.dart';
import '../features/auth/login_page.dart';
import '../features/budgets/budgets_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/placeholder_page.dart';
import '../features/transactions/transactions_page.dart';
import 'onboarding_gate.dart';

final onboardingGateProvider = Provider((ref) {
  final gate = OnboardingGate(
    Supabase.instance.client.auth,
    ref.watch(repositoryProvider),
  );
  ref.onDispose(gate.dispose);
  return gate;
});

final routerProvider = Provider((ref) {
  final router = createRouter(
    Supabase.instance.client.auth,
    ref.watch(onboardingGateProvider),
  );
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createRouter(GoTrueClient auth, OnboardingGate gate) {
  final home = appDestinations.first.path;

  return GoRouter(
    initialLocation: home,
    refreshListenable: gate,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      if (auth.currentSession == null) {
        return location == '/login' ? null : '/login';
      }

      final bool onboarded;
      try {
        onboarded = await gate.isOnboarded();
      } catch (_) {
        return null; // Réseau indisponible : on réessaiera à la navigation suivante.
      }
      if (!onboarded) {
        return location == '/onboarding' ? null : '/onboarding';
      }
      if (location == '/login' || location == '/onboarding') return home;
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          for (final destination in appDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: destination.path,
                  builder: (context, state) => _pageFor(destination),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

Widget _pageFor(AppDestination destination) => switch (destination.path) {
  '/depenses' => const TransactionsPage(),
  '/budgets' => const BudgetsPage(),
  _ => PlaceholderPage(title: destination.label),
};
