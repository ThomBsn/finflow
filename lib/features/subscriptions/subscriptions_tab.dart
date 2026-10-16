import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'subscription_form.dart';

/// Onglet Abonnements : leur total forme l'alloué du budget « Abonnements ».
class SubscriptionsTab extends ConsumerWidget {
  const SubscriptionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouvel abonnement',
        onPressed: () => showSubscriptionForm(context),
        child: const Icon(Icons.add),
      ),
      body: subscriptions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (items) {
          final active = items.where((s) => s.active).toList();
          final total = active.fold<double>(0, (sum, s) => sum + s.amount);

          return RefreshIndicator(
            onRefresh: () => ref.refresh(subscriptionsProvider.future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                ListTile(
                  title: const Text('Total mensuel'),
                  subtitle: Text(
                    '${active.length} actif${active.length > 1 ? 's' : ''} · '
                    'alloué du budget Abonnements',
                  ),
                  trailing: Text(
                    euro(total),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aucun abonnement. Chaque abonnement crée sa dépense '
                      'automatiquement le jour du prélèvement.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final s in items) _SubscriptionTile(subscription: s),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    final theme = Theme.of(context);
    final muted = s.active ? null : theme.disabledColor;

    return ListTile(
      leading: CircleAvatar(
        child: Icon(s.active ? Icons.subscriptions : Icons.pause, size: 20),
      ),
      title: Text(s.name, style: TextStyle(color: muted)),
      subtitle: Text(
        s.active ? 'Le ${s.billingDay} du mois' : 'Suspendu',
        style: TextStyle(color: muted),
      ),
      trailing: Text(
        euro(s.amount),
        style: theme.textTheme.bodyLarge?.copyWith(color: muted),
      ),
      onTap: () => showSubscriptionForm(context, subscription: s),
    );
  }
}
