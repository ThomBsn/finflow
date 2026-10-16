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

/// Utilisateur connecté ; au démarrage, avant le premier événement du flux,
/// la session déjà restaurée fait foi.
String? _watchUser(Ref ref) =>
    ref.watch(userIdProvider.select((u) => u.value)) ??
    (ref.read(userIdProvider).isLoading
        ? Supabase.instance.client.auth.currentUser?.id
        : null);

final currentMonthProvider = FutureProvider<DateTime?>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).currentMonth();
});

final monthSummaryProvider = FutureProvider<MonthSummary?>((ref) async {
  // Écouté en permanence par le widget : rien à charger hors connexion.
  if (_watchUser(ref) == null) return null;
  return ref.watch(repositoryProvider).monthSummary();
});

final settingsProvider = FutureProvider<Settings>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).settings();
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

final subscriptionsProvider = FutureProvider<List<Subscription>>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).subscriptions();
});

final installmentPlansProvider = FutureProvider<List<InstallmentPlan>>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).installmentPlans();
});

final savingsProjectsProvider = FutureProvider<List<SavingsProject>>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).savingsProjects();
});

final budgetLinesProvider = FutureProvider.family<List<BudgetLine>, String>((
  ref,
  budgetId,
) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).budgetLines(budgetId);
});

final closedMonthsProvider = FutureProvider<List<ClosedMonth>>((ref) {
  _watchUser(ref);
  return ref.watch(repositoryProvider).closedMonths();
});

final settlementFlowsProvider =
    FutureProvider.family<List<SettlementFlow>, String>((ref, settlementId) {
      _watchUser(ref);
      return ref.watch(repositoryProvider).settlementFlows(settlementId);
    });

/// À appeler après toute écriture : transactions, budgets, abonnements,
/// échelonnements ou épargne (tout peut changer le résumé du mois).
void invalidateMonthData(WidgetRef ref) {
  ref.invalidate(transactionsProvider);
  ref.invalidate(subscriptionsProvider);
  ref.invalidate(installmentPlansProvider);
  ref.invalidate(savingsProjectsProvider);
  ref.invalidate(budgetStatusProvider);
  ref.invalidate(budgetLinesProvider);
  ref.invalidate(budgetsProvider);
  ref.invalidate(monthSummaryProvider);
}

/// À appeler après une transition ou un rééquilibrage : le mois en cours et
/// les soldes changent.
void invalidateAll(WidgetRef ref) {
  invalidateMonthData(ref);
  ref.invalidate(currentMonthProvider);
  ref.invalidate(monthsProvider);
  ref.invalidate(closedMonthsProvider);
}
