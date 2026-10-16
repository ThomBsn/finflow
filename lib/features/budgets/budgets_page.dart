import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'budget_detail_sheet.dart';
import 'budget_form.dart';

/// Page Budgets : alloué / dépensé / reste du mois en cours.
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider).value;
    final status = ref.watch(budgetStatusProvider);
    final budgets = {
      for (final b in ref.watch(budgetsProvider).value ?? const <Budget>[])
        b.id: b,
    };

    void open(BudgetStatus s) =>
        showBudgetDetail(context, status: s, budget: budgets[s.id]);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          month == null ? 'Budgets' : 'Budgets · ${monthLabel(month)}',
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouveau budget',
        onPressed: () => showBudgetForm(context),
        child: const Icon(Icons.add),
      ),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (items) {
          final inBudget = items.where((s) => !s.horsBudget).toList();
          final outOfBudget = items.where((s) => s.horsBudget).toList();
          final allocated = inBudget.fold<double>(0, (s, b) => s + b.allocated);
          final spent = inBudget.fold<double>(0, (s, b) => s + b.spent);

          return RefreshIndicator(
            onRefresh: () => ref.refresh(budgetStatusProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: [
                _BudgetCard.summary(allocated, spent),
                const SizedBox(height: 8),
                for (final s in inBudget)
                  _BudgetCard(status: s, onTap: () => open(s)),
                if (outOfBudget.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text(
                      'Hors budget',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final s in outOfBudget)
                    _BudgetCard(status: s, onTap: () => open(s)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required BudgetStatus this.status, required this.onTap})
    : _allocated = 0,
      _spent = 0;

  /// Carte de total : [_allocated] et [_spent] cumulés des budgets.
  const _BudgetCard.summary(this._allocated, this._spent)
    : status = null,
      onTap = null;

  final BudgetStatus? status;
  final VoidCallback? onTap;
  final double _allocated;
  final double _spent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    final allocated = s?.allocated ?? _allocated;
    final spent = s?.spent ?? _spent;
    final remaining = allocated - spent;
    final horsBudget = s?.horsBudget ?? false;
    final over = !horsBudget && remaining < 0;

    return Card(
      color: s == null ? theme.colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    s == null
                        ? Icons.account_balance_wallet
                        : categoryIcon(s.icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s?.category ?? 'Total des budgets',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    horsBudget
                        ? euro(spent)
                        : '${euro(spent)} / ${euro(allocated)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              if (!horsBudget) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: allocated > 0
                      ? (spent / allocated).clamp(0, 1).toDouble()
                      : (spent > 0 ? 1 : 0),
                  color: over ? theme.colorScheme.error : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 8),
                Text(
                  over
                      ? 'Dépassement de ${euro(-remaining)}'
                      : 'Reste ${euro(remaining)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
