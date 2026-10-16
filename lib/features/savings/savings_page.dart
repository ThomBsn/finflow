import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'project_form.dart';
import 'save_sheet.dart';

/// Page Épargne : projets, pourcentages, progression vers les objectifs.
class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(savingsProjectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Épargne')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouveau projet',
        onPressed: () => showProjectForm(context),
        child: const Icon(Icons.add),
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(savingsProjectsProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            children: [
              _SummaryCard(projects: items),
              const SizedBox(height: 8),
              for (final p in items) _ProjectCard(project: p),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.projects});

  final List<SavingsProject> projects;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = projects.fold<double>(0, (s, p) => s + p.currentAmount);
    final shared = projects.fold<double>(0, (s, p) => s + p.percentage);
    final onColor = theme.colorScheme.onPrimaryContainer;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total épargné',
              style: theme.textTheme.labelLarge?.copyWith(color: onColor),
            ),
            const SizedBox(height: 8),
            Text(
              euro(total),
              style: theme.textTheme.displaySmall?.copyWith(color: onColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Répartition automatique : ${_pct(shared)} vers les projets, '
              '${_pct(100 - shared)} vers Épargne générale',
              style: theme.textTheme.bodySmall?.copyWith(color: onColor),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showSaveSheet(context, projects: projects),
              icon: const Icon(Icons.savings),
              label: const Text('Épargner maintenant'),
            ),
          ],
        ),
      ),
    );
  }
}

String _pct(double value) =>
    '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2).replaceAll('.', ',')} %';

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final SavingsProject project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = project;
    final target = p.targetAmount;

    final role = p.isSafetyFund
        ? 'Reçoit les excédents · sert au rééquilibrage'
        : p.isDefault
        ? 'Reçoit le complément et le reste'
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showProjectForm(context, project: p),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    p.isSafetyFund
                        ? Icons.shield
                        : (p.isDefault ? Icons.account_balance : Icons.flag),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p.name, style: theme.textTheme.titleMedium),
                  ),
                  if (p.percentage > 0)
                    Chip(
                      label: Text(_pct(p.percentage)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (role != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(role, style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              Text(
                target == null
                    ? euro(p.currentAmount)
                    : '${euro(p.currentAmount)} / ${euro(target)}',
                style: theme.textTheme.bodyLarge,
              ),
              if (target != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (p.currentAmount / target).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                if (p.isFull)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Objectif atteint : l\'excédent part vers le Fond de '
                      'sécurité',
                      style: theme.textTheme.bodySmall,
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
