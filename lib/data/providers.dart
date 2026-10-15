import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

final repositoryProvider = Provider(
  (ref) => FinflowRepository(Supabase.instance.client),
);

/// Utilisateur connecté : les données sont rechargées quand il change, pour
/// ne jamais afficher le cache d'un compte précédent.
final userIdProvider = StreamProvider<String?>(
  (ref) => Supabase.instance.client.auth.onAuthStateChange.map(
    (state) => state.session?.user.id,
  ),
);

String? _watchUser(Ref ref) => ref.watch(userIdProvider.select((u) => u.value));

final currentMonthProvider = FutureProvider<DateTime?>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).currentMonth();
});

final monthsProvider = FutureProvider<List<DateTime>>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).months();
});

final budgetsProvider = FutureProvider<List<Budget>>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).budgets();
});

final budgetStatusProvider = FutureProvider<List<BudgetStatus>>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).budgetStatus();
});

typedef TransactionFilter = ({DateTime month, String? category});

final transactionsProvider =
    FutureProvider.family<List<Transaction>, TransactionFilter>((ref, filter) {
      _watchUser(ref);
      return ref
          .watch(repositoryProvider)
          .transactions(month: filter.month, category: filter.category);
    });

/// À appeler après toute écriture sur les transactions ou les budgets.
void invalidateMonthData(WidgetRef ref) {
  ref.invalidate(transactionsProvider);
  ref.invalidate(budgetStatusProvider);
  ref.invalidate(budgetsProvider);
}
