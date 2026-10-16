import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'sankey_chart.dart';

/// Page Distribution : historique des clôtures et répartition de l'argent
/// de chaque mois clôturé (Sankey + tableau).
class DistributionPage extends ConsumerStatefulWidget {
  const DistributionPage({super.key});

  @override
  ConsumerState<DistributionPage> createState() => _DistributionPageState();
}

class _DistributionPageState extends ConsumerState<DistributionPage> {
  String? _selectedId; // null : dernier mois clôturé

  @override
  Widget build(BuildContext context) {
    final months = ref.watch(closedMonthsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Distribution')),
      body: months.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (items) {
          if (items.isEmpty) return const _Empty();
          final selected = items.firstWhere(
            (m) => m.id == _selectedId,
            orElse: () => items.first,
          );

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(closedMonthsProvider);
              ref.invalidate(settlementFlowsProvider);
              await ref.read(closedMonthsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final m in items)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(monthLabel(m.month)),
                            selected: m.id == selected.id,
                            onSelected: (_) =>
                                setState(() => _selectedId = m.id),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _MonthDetail(month: selected),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        'Aucun mois clôturé pour l\'instant. Après ta première clôture '
        '(« Passer au mois suivant »), tu verras ici d\'où vient et où est '
        'parti l\'argent du mois.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _MonthDetail extends ConsumerWidget {
  const _MonthDetail({required this.month});

  final ClosedMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final flows = ref.watch(settlementFlowsProvider(month.id));
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat('Dépenses du mois', month.totalExpenses),
            _Stat('Épargne virée', month.totalSavings),
            if (month.closingBalance != null)
              _Stat('Courant ensuite', month.closingBalance!),
            if (month.specialMonth)
              const Chip(
                avatar: Icon(Icons.info_outline, size: 18),
                label: Text('Mois particulier'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        flows.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Chargement impossible : $e'),
          data: (items) {
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Le détail des flux n\'est pas disponible pour ce mois '
                  '(clôturé avant leur suivi).',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Où est parti l\'argent',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          'Touche un flux pour le mettre en évidence',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        SankeyChart(flows: items, height: wide ? 440 : 340),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _FlowTable(flows: items),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            Text(
              euro(value),
              style: theme.textTheme.titleMedium?.copyWith(
                color: value < 0 ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vue tableau des flux : chaque ligne avec sa part du total.
class _FlowTable extends StatelessWidget {
  const _FlowTable({required this.flows});

  final List<SettlementFlow> flows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incoming = sortFlows(flows.where((f) => f.incoming));
    final outgoing = sortFlows(flows.where((f) => !f.incoming));
    final total = incoming.fold<double>(0, (s, f) => s + f.amount);

    Widget section(String title, List<SettlementFlow> rows) => Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final f in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: flowColor(f.kind, theme.brightness),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(f.label)),
                    Text(euro(f.amount)),
                    SizedBox(
                      width: 52,
                      child: Text(
                        total > 0
                            ? '${(f.amount / total * 100).round()} %'
                            : '',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('D\'où vient l\'argent', incoming),
        section('Où il est allé', outgoing),
      ],
    );
  }
}
