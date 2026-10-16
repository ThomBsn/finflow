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

  /// Échoue au bout de [_timeout] si le serveur ne répond pas, pour que le
  /// routeur affiche l'écran « serveur injoignable » au lieu d'un écran noir.
  static const _timeout = Duration(seconds: 5);

  /// Vrai après un échec : le routeur reste sur l'écran hors ligne sans
  /// réinterroger le serveur, jusqu'à [retry].
  bool get offline => _offline;
  bool _offline = false;

  Future<bool> isOnboarded() async {
    try {
      return await (_onboarded ??= _repository.isOnboarded().timeout(_timeout));
    } catch (_) {
      _onboarded = null;
      _offline = true;
      rethrow;
    }
  }

  void markOnboarded() {
    _onboarded = Future.value(true);
    notifyListeners();
  }

  /// Relance la vérification (bouton « Réessayer »).
  void retry() {
    _onboarded = null;
    _offline = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
