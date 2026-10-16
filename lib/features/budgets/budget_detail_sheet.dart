import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'budget_form.dart';

Future<void> showBudgetDetail(
  BuildContext context, {
  required BudgetStatus status,
  required Budget? budget,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, controller) => BudgetDetailSheet(
      status: status,
      budget: budget,
      scrollController: controller,
    ),
  ),
);

/// Ce qui compose le consommé d'un budget ce mois-ci : chaque dépense ou
/// mensualité, et sa part de l'enveloppe.
class BudgetDetailSheet extends ConsumerWidget {
  const BudgetDetailSheet({
    super.key,
    required this.status,
    required this.budget,
    required this.scrollController,
  });

  final BudgetStatus status;
  final Budget? budget;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = status;
    final lines = ref.watch(budgetLinesProvider(s.id));
    final over = !s.horsBudget && s.remaining < 0;
    // Référence des pourcentages : l'enveloppe, ou le total dépensé si
    // le budget n'a pas d'enveloppe (hors budget ou montant à 0).
    final base = !s.horsBudget && s.allocated > 0 ? s.allocated : s.spent;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Row(
          children: [
            Icon(categoryIcon(s.icon), color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.category, style: theme.textTheme.titleLarge),
            ),
            if (budget != null)
              IconButton(
                tooltip: 'Modifier le budget',
                icon: const Icon(Icons.edit),
                onPressed: () {
                  // Le contexte de la feuille disparaît en la fermant : on rouvre
                  // depuis celui du Navigator.
                  final navigator = Navigator.of(context)..pop();
                  showBudgetForm(navigator.context, budget: budget);
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (s.horsBudget)
          Text('Dépensé ${euro(s.spent)} · hors budget, sans enveloppe')
        else ...[
          Text(
            '${euro(s.spent)} dépensés sur ${euro(s.allocated)}'
            '${s.allocated > 0 ? ' · ${_percent(s.spent / s.allocated)} utilisés' : ''}',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: s.allocated > 0
                ? (s.spent / s.allocated).clamp(0, 1).toDouble()
                : (s.spent > 0 ? 1 : 0),
            color: over ? theme.colorScheme.error : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            '${over ? 'Dépassement de ${euro(-s.remaining)}' : 'Reste ${euro(s.remaining)}'}'
            '${s.reserved > 0 ? ' · dont ${euro(s.reserved)} d\'abonnements à venir' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: over ? theme.colorScheme.error : null,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Ce qui compose ce budget', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        lines.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Chargement impossible : $e'),
          data: (items) => items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aucune dépense ce mois-ci'),
                )
              : Column(
                  children: [
                    for (final l in items) _LineTile(line: l, base: base),
                  ],
                ),
        ),
      ],
    );
  }
}

String _percent(double ratio) => '${(ratio * 100).round()} %';

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.base});

  final BudgetLine line;

  /// Montant de référence pour la part (enveloppe ou total dépensé).
  final double base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = line;
    final refund = l.amount < 0;
    final share = base > 0 ? l.amount / base : 0.0;

    final details = [
      dayLabel(l.date),
      if (l.isInstallment)
        'mensualité ${l.installmentNumber}/${l.installments} '
            'de ${euro(l.transactionAmount)}',
      if (refund) 'revenu déduit',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (l.isInstallment)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.event_repeat,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
              Expanded(
                child: Text(
                  l.label.isEmpty ? 'Sans libellé' : l.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                refund ? '− ${euro(-l.amount)}' : euro(l.amount),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: refund ? Colors.green.shade600 : null,
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  refund ? '' : _percent(share),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: share.clamp(0, 1).toDouble(),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            color: refund ? Colors.green.shade600 : null,
          ),
          const SizedBox(height: 4),
          Text(details.join(' · '), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
