import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/category_icons.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../budgets/budget_detail_sheet.dart';
import '../transactions/transaction_form.dart';

/// Carte de section du Dashboard : titre, lien « Tout voir », contenu.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.path,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;

  /// Page complète ouverte par « Tout voir ».
  final String? path;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(trailing!, style: theme.textTheme.bodySmall),
                  ),
                if (path != null)
                  TextButton(
                    onPressed: () => context.go(path!),
                    child: const Text('Tout voir'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.only(right: 8), child: child),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// Rend une valeur asynchrone dans une section, avec chargement / erreur.
Widget _async<T>(AsyncValue<T> value, Widget Function(T data) data) =>
    value.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _Empty('Chargement impossible : $e'),
      data: data,
    );

// ---------------------------------------------------------------------------
// Budgets : les plus entamés d'abord
// ---------------------------------------------------------------------------
class BudgetsSection extends ConsumerWidget {
  const BudgetsSection({super.key});

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(budgetStatusProvider);
    final budgets = {
      for (final b in ref.watch(budgetsProvider).value ?? const <Budget>[])
        b.id: b,
    };

    return _Section(
      title: 'Budgets',
      icon: Icons.pie_chart,
      path: '/budgets',
      child: _async(status, (items) {
        double usage(BudgetStatus s) => s.allocated > 0
            ? s.spent / s.allocated
            : (s.spent > 0 ? double.infinity : 0);
        final active =
            items
                .where((s) => !s.horsBudget && (s.allocated > 0 || s.spent > 0))
                .toList()
              ..sort((a, b) => usage(b).compareTo(usage(a)));
        if (active.isEmpty) return const _Empty('Aucun budget utilisé');

        return Column(
          children: [
            for (final s in active.take(_shown))
              _BudgetRow(
                status: s,
                onTap: () =>
                    showBudgetDetail(context, status: s, budget: budgets[s.id]),
              ),
          ],
        );
      }),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.status, required this.onTap});

  final BudgetStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    final over = s.remaining < 0;
    final ratio = s.allocated > 0
        ? (s.spent / s.allocated).clamp(0, 1).toDouble()
        : 1.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(categoryIcon(s.icon), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(s.category)),
                Text(
                  '${euro(s.spent)} / ${euro(s.allocated)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ratio,
              color: over ? theme.colorScheme.error : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dernières transactions du mois
// ---------------------------------------------------------------------------
class RecentTransactionsSection extends ConsumerWidget {
  const RecentTransactionsSection({super.key, required this.month});

  final DateTime month;

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(
      transactionsProvider((month: month, category: null)),
    );
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    final icons = {for (final b in budgets) b.category: b.icon};
    final theme = Theme.of(context);

    return _Section(
      title: 'Dernières transactions',
      icon: Icons.receipt_long,
      path: '/depenses',
      child: _async(transactions, (items) {
        if (items.isEmpty) return const _Empty('Aucune transaction ce mois-ci');
        return Column(
          children: [
            for (final t in items.take(_shown))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  t.type == TransactionType.transfertEpargne
                      ? Icons.savings
                      : categoryIcon(icons[t.category]),
                  size: 20,
                ),
                title: Text(
                  t.label.isNotEmpty ? t.label : (t.category ?? 'Revenu'),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(dayLabel(t.date)),
                trailing: Text(
                  '${t.signedAmount > 0 ? '+' : '−'} ${euro(t.amount)}',
                  style: TextStyle(
                    color: t.signedAmount > 0 ? Colors.green.shade600 : null,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: t.editable
                    ? () => showTransactionForm(
                        context,
                        budgets: budgets,
                        existing: t,
                      )
                    : null,
              ),
            if (items.length > _shown)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+ ${items.length - _shown} autres',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Prochains prélèvements d'abonnements
// ---------------------------------------------------------------------------
class UpcomingChargesSection extends ConsumerWidget {
  const UpcomingChargesSection({super.key});

  static const _shown = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionsProvider);
    final active = subscriptions.value?.where((s) => s.active).toList();
    final total = active?.fold<double>(0, (sum, s) => sum + s.amount);

    return _Section(
      title: 'Prochains prélèvements',
      icon: Icons.subscriptions,
      path: '/depenses',
      trailing: total == null ? null : '${euro(total)} / mois',
      child: _async(subscriptions, (_) {
        if (active!.isEmpty) return const _Empty('Aucun abonnement actif');
        final today = DateTime.now();
        final upcoming = [
          for (final s in active) (sub: s, date: s.nextCharge(today)),
        ]..sort((a, b) => a.date.compareTo(b.date));

        return Column(
          children: [
            for (final u in upcoming.take(_shown))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(u.sub.name),
                subtitle: Text(dayLabel(u.date)),
                trailing: Text(euro(u.sub.amount)),
              ),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Dépenses étalées en cours
// ---------------------------------------------------------------------------
class InstallmentsSection extends ConsumerWidget {
  const InstallmentsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(installmentPlansProvider);
    final theme = Theme.of(context);

    return _Section(
      title: 'Dépenses étalées',
      icon: Icons.event_repeat,
      path: '/depenses',
      child: _async(plans, (items) {
        final running = items.where((p) => !p.finished).toList();
        if (running.isEmpty) {
          return const _Empty('Aucune dépense étalée en cours');
        }
        return Column(
          children: [
            for (final p in running)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(p.label.isEmpty ? p.category : p.label),
                        ),
                        Text(
                          '${euro(p.monthlyAmount)} / mois',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value:
                          p.currentNumber.clamp(0, p.installments) /
                          p.installments,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.category} · mensualité '
                      '${p.currentNumber.clamp(0, p.installments)}/${p.installments}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Projets d'épargne
// ---------------------------------------------------------------------------
class SavingsSection extends ConsumerWidget {
  const SavingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(savingsProjectsProvider);
    final theme = Theme.of(context);

    return _Section(
      title: 'Épargne',
      icon: Icons.savings,
      path: '/epargne',
      child: _async(projects, (items) {
        if (items.isEmpty) return const _Empty('Aucun projet');
        return Column(
          children: [
            for (final p in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(p.name)),
                        Text(
                          savingsProgress(p.currentAmount, p.targetAmount),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (p.targetAmount != null) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (p.currentAmount / p.targetAmount!)
                            .clamp(0, 1)
                            .toDouble(),
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}
