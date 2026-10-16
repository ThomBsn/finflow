import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../installments/installments_tab.dart';
import '../subscriptions/subscriptions_tab.dart';
import 'transaction_form.dart';

/// Page Dépenses : transactions, abonnements, échelonnements.
class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dépenses'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Transactions'),
              Tab(text: 'Abonnements'),
              Tab(text: 'Échelonnements'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [TransactionsTab(), SubscriptionsTab(), InstallmentsTab()],
        ),
      ),
    );
  }
}

/// Transactions d'un mois, filtrables par catégorie.
class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  DateTime? _month; // null : mois en cours
  String? _category; // null : toutes

  @override
  Widget build(BuildContext context) {
    final currentMonth = ref.watch(currentMonthProvider).value;
    final months = ref.watch(monthsProvider).value ?? const <DateTime>[];
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    final month = _month ?? currentMonth;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ajouter',
        onPressed: budgets.isEmpty
            ? null
            : () => showTransactionForm(context, budgets: budgets),
        child: const Icon(Icons.add),
      ),
      body: month == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<DateTime>(
                          initialValue: month,
                          decoration: const InputDecoration(
                            labelText: 'Mois',
                            isDense: true,
                          ),
                          items: [
                            for (final m
                                in months.contains(month)
                                    ? months
                                    : [month, ...months])
                              DropdownMenuItem(
                                value: m,
                                child: Text(monthLabel(m)),
                              ),
                          ],
                          onChanged: (m) => setState(() => _month = m),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _category,
                          decoration: const InputDecoration(
                            labelText: 'Catégorie',
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(child: Text('Toutes')),
                            for (final b in budgets)
                              DropdownMenuItem(
                                value: b.category,
                                child: Text(
                                  b.category,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (c) => setState(() => _category = c),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _TransactionList(
                    filter: (month: month, category: _category),
                    budgets: budgets,
                  ),
                ),
              ],
            ),
    );
  }
}

class _TransactionList extends ConsumerWidget {
  const _TransactionList({required this.filter, required this.budgets});

  final TransactionFilter filter;
  final List<Budget> budgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionsProvider(filter));

    return transactions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Chargement impossible : $e')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('Aucune transaction ce mois-ci'));
        }

        final net = items
            .where(
              (t) =>
                  t.type == TransactionType.depense ||
                  t.type == TransactionType.revenu,
            )
            .fold<double>(0, (sum, t) => sum - t.signedAmount);
        final icons = {for (final b in budgets) b.category: b.icon};

        final children = <Widget>[
          ListTile(
            title: const Text('Dépenses nettes'),
            subtitle: const Text('Dépenses − revenus saisis'),
            trailing: Text(
              euro(net),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
        ];
        DateTime? day;
        for (final t in items) {
          if (t.date != day) {
            day = t.date;
            children.add(_DayHeader(day));
          }
          children.add(
            _TransactionTile(
              transaction: t,
              icon: icons[t.category],
              onTap: t.editable
                  ? () => showTransactionForm(
                      context,
                      budgets: budgets,
                      existing: t,
                    )
                  : null,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.refresh(transactionsProvider(filter).future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: children,
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.day);

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        dayLabel(day),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.icon,
    required this.onTap,
  });

  final Transaction transaction;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final theme = Theme.of(context);
    final positive = t.signedAmount > 0;

    final leading = switch (t.type) {
      TransactionType.transfertEpargne => Icons.savings,
      TransactionType.retraitEpargne => Icons.savings_outlined,
      TransactionType.revenu when t.category == null => Icons.payments,
      _ => categoryIcon(icon),
    };
    final title = t.label.isNotEmpty ? t.label : (t.category ?? 'Revenu');
    final details = [
      ?t.category,
      if (t.horsBudget) 'hors budget',
      if (t.installments != null) 'étalée sur ${t.installments} mois',
      if (t.settled) 'réglée',
    ];

    return ListTile(
      leading: CircleAvatar(child: Icon(leading, size: 20)),
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: Text(
        '${positive ? '+' : '−'} ${euro(t.amount)}',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: positive ? Colors.green.shade600 : null,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
