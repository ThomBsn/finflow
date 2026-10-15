import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'close_month_sheet.dart';

/// Dashboard minimal : disponible estimé, soldes, alerte découvert,
/// transition de mois.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

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
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (s) => s == null
            ? const Center(child: Text('Aucun mois en cours'))
            : RefreshIndicator(
                onRefresh: () => ref.refresh(monthSummaryProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (s.courant < 0) ...[
                      _OverdraftAlert(summary: s),
                      const SizedBox(height: 12),
                    ],
                    _AvailableCard(summary: s),
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
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _closeMonth(context, s),
                      icon: const Icon(Icons.event_repeat),
                      label: const Text('Passer au mois suivant'),
                    ),
                  ],
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

class _AvailableCard extends StatelessWidget {
  const _AvailableCard({required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final negative = s.available < 0;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Disponible estimé',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              euro(s.available),
              style: theme.textTheme.displaySmall?.copyWith(
                color: negative
                    ? theme.colorScheme.error
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Courant ${euro(s.courant)} − dépenses du mois '
              '${euro(s.unsettledExpenses)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
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
