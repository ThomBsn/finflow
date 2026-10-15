import 'package:supabase_flutter/supabase_flutter.dart';

/// Message affichable pour une erreur Supabase. Les erreurs métier (FF00x)
/// portent déjà un message en français, levé par les RPC.
String errorMessage(Object error) => switch (error) {
  PostgrestException(code: '23505') => 'Ce nom est déjà utilisé',
  PostgrestException(code: '42501') => 'Action non autorisée',
  PostgrestException(:final code?, :final message) when code.startsWith('FF') =>
    message,
  AuthException(:final message) => message,
  _ => 'Erreur inattendue, réessaie',
};
