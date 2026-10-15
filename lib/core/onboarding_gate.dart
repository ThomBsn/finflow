import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repository.dart';

/// Sait si l'utilisateur connecté a fait son onboarding (un mois existe).
/// Notifie le routeur à chaque connexion / déconnexion et à la fin de
/// l'onboarding pour qu'il réévalue ses redirections.
class OnboardingGate extends ChangeNotifier {
  OnboardingGate(GoTrueClient auth, this._repository) {
    _subscription = auth.onAuthStateChange.listen((state) {
      if (state.event != AuthChangeEvent.tokenRefreshed) {
        _onboarded = null;
        notifyListeners();
      }
    });
  }

  final FinflowRepository _repository;
  late final StreamSubscription<AuthState> _subscription;
  Future<bool>? _onboarded;

  Future<bool> isOnboarded() async {
    try {
      return await (_onboarded ??= _repository.isOnboarded());
    } catch (_) {
      _onboarded = null;
      rethrow;
    }
  }

  void markOnboarded() {
    _onboarded = Future.value(true);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
