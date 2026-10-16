import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Onglet Échelonnements : dépenses étalées sur leur budget. On en crée un
/// depuis la dépense elle-même (« Étaler sur le budget »).
class InstallmentsTab extends ConsumerWidget {
  const InstallmentsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(installmentPlansProvider);

    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Chargement impossible : $e')),
      data: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(installmentPlansProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text(
                'Une grosse dépense est payée en une fois, mais son budget '
                'n\'en compte qu\'une mensualité par mois. Pour étaler une '
                'dépense, ouvre-la dans Transactions et active « Étaler sur '
                'le budget ».',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune dépense étalée',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final p in items) _PlanCard(plan: p),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});

  final InstallmentPlan plan;

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Ne plus étaler « ${plan.label} » ?',
      content:
          'La dépense comptera en entier dans le budget ${plan.category} de '
          '${monthLabel(plan.date).toLowerCase()}.',
      action: 'Ne plus étaler',
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).deleteInstallmentPlan(plan.id);
      invalidateMonthData(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = plan;
    final title = p.label.isEmpty ? p.category : p.label;
    final current = p.currentNumber.clamp(0, p.installments);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(euro(p.totalAmount), style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
              ],
            ),
            Text(
              '${p.category} · payée le ${dayLabel(p.date).toLowerCase()}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LinearProgressIndicator(
                value: current / p.installments,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.finished
                        ? 'Terminé · ${p.installments} × ${euro(p.monthlyAmount)}'
                        : 'Mensualité $current/${p.installments} : '
                              '${euro(p.monthlyAmount)} · encore '
                              '${euro(p.remainingAmount)} sur les mois suivants',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Ne plus étaler',
                  icon: const Icon(Icons.link_off),
                  onPressed: () => _stop(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
