import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_page.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/placeholder_page.dart';

GoRouter createRouter(GoTrueClient auth) {
  return GoRouter(
    initialLocation: appDestinations.first.path,
    refreshListenable: _AuthRefresh(auth.onAuthStateChange),
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return appDestinations.first.path;
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          for (final destination in appDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: destination.path,
                  builder: (context, state) =>
                      PlaceholderPage(title: destination.label),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Réévalue les redirections à chaque connexion / déconnexion.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
