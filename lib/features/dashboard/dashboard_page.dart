import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'close_month_sheet.dart';
import 'dashboard_sections.dart';

/// Dashboard : disponible estimé, soldes, alerte découvert, transition de
/// mois, puis un aperçu de chaque page (une colonne sur téléphone, deux sur
/// grand écran).
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const _twoColumns = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          summary.value == null
              ? 'Dashboard'
              : monthLabel(summary.value!.month),
        ),
        actions: [
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/reglages'),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (s) => s == null
            ? const Center(child: Text('Aucun mois en cours'))
            : RefreshIndicator(
                onRefresh: () async {
                  invalidateMonthData(ref);
                  await ref.read(monthSummaryProvider.future);
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= _twoColumns;
                    const budgets = BudgetsSection();
                    const charges = UpcomingChargesSection();
                    const installments = InstallmentsSection();
                    const savings = SavingsSection();
                    final recent = RecentTransactionsSection(month: s.month);

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (s.courant < 0) ...[
                          _OverdraftAlert(summary: s),
                          const SizedBox(height: 12),
                        ],
                        _ProjectionCard(summary: s),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _BalanceCard(
                                label: 'Compte courant',
                                value: s.courant,
                                icon: Icons.account_balance,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _BalanceCard(
                                label: 'Épargne',
                                value: s.epargne,
                                icon: Icons.savings,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _closeMonth(context, s),
                          icon: const Icon(Icons.event_repeat),
                          label: const Text('Passer au mois suivant'),
                        ),
                        const SizedBox(height: 16),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                child: Column(
                                  children: [budgets, installments],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  children: [recent, charges, savings],
                                ),
                              ),
                            ],
                          )
                        else ...[
                          budgets,
                          recent,
                          charges,
                          installments,
                          savings,
                        ],
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _closeMonth(BuildContext context, MonthSummary summary) async {
    final result = await showCloseMonthSheet(context, summary);
    if (result == null || !context.mounted) return;
    final saved = result.totalSavings > 0
        ? '${euro(result.totalSavings)} épargnés'
        : 'pas d\'épargne ce mois-ci';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${monthLabel(summary.month)} clôturé · $saved')),
    );
  }
}

/// Épargne prévue à la prochaine clôture, au rythme actuel et si les budgets
/// sont épuisés. Négatif : rien d'épargné, le courant passera sous la marge.
class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.summary});

  final MonthSummary summary;

  String _savings(double value) =>
      value >= 0 ? euro(value) : 'aucune (${euro(-value)} sous la marge)';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final onColor = theme.colorScheme.onPrimaryContainer;

    if (s.needsSalary) {
      return Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Épargne prévue',
                style: theme.textTheme.labelLarge?.copyWith(color: onColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Renseigne ton salaire habituel pour voir, à chaque dépense, '
                'ce que la prochaine clôture mettra de côté.',
                style: TextStyle(color: onColor),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push('/reglages'),
                icon: const Icon(Icons.settings),
                label: const Text('Réglages'),
              ),
            ],
          ),
        ),
      );
    }

    final negative = s.projectedSavings < 0;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Épargne prévue à la clôture',
              style: theme.textTheme.labelLarge?.copyWith(color: onColor),
            ),
            const SizedBox(height: 8),
            Text(
              euro(negative ? 0 : s.projectedSavings),
              style: theme.textTheme.displaySmall?.copyWith(
                color: negative ? theme.colorScheme.error : onColor,
              ),
            ),
            if (negative)
              Text(
                'Le courant passera ${euro(-s.projectedSavings)} sous la marge',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              s.budgetRemaining > 0
                  ? 'Si tu dépenses les ${euro(s.budgetRemaining)} restants '
                        'de tes budgets : ${_savings(s.projectedSavingsBudgets)}'
                  : 'Budgets entièrement dépensés',
              style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
            ),
            const SizedBox(height: 4),
            Text(
              'Salaire ${euro(s.suggestedSalary)} − compte commun '
              '${euro(s.suggestedSharedTransfer)} − dépensé '
              '${euro(s.unsettledExpenses)} − marge ${euro(s.safetyMargin)}'
              '${s.courant != s.safetyMargin ? ' (courant ${euro(s.courant)})' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: onColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final double value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              euro(value),
              style: theme.textTheme.titleLarge?.copyWith(
                color: value < 0 ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alerte découvert + « Rétablir l'équilibre » (spec §4).
class _OverdraftAlert extends ConsumerStatefulWidget {
  const _OverdraftAlert({required this.summary});

  final MonthSummary summary;

  @override
  ConsumerState<_OverdraftAlert> createState() => _OverdraftAlertState();
}

class _OverdraftAlertState extends ConsumerState<_OverdraftAlert> {
  bool _loading = false;

  Future<void> _rebalance() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(repositoryProvider).rebalanceFromSafetyFund();
      invalidateAll(ref);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.remaining > 0
                ? '${euro(r.withdrawn)} retirés du Fond de sécurité · '
                      'reste ${euro(r.remaining)} à couvrir'
                : 'Équilibre rétabli · ${euro(r.withdrawn)} retirés du '
                      'Fond de sécurité',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Compte courant à découvert de ${euro(-widget.summary.courant)}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Le Fond de sécurité peut le ramener à 0.',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: _loading ? null : _rebalance,
                child: const Text('Rétablir l\'équilibre'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
