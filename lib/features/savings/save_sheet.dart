import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<void> showSaveSheet(
  BuildContext context, {
  required List<SavingsProject> projects,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => SaveSheet(projects: projects),
);

/// Versement manuel du courant vers l'épargne (spec §5).
class SaveSheet extends ConsumerStatefulWidget {
  const SaveSheet({super.key, required this.projects});

  final List<SavingsProject> projects;

  @override
  ConsumerState<SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends ConsumerState<SaveSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  DistributionMode _mode = DistributionMode.automatique;
  String? _projectId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final amount = parseAmount(_amount.text)!;
    try {
      await ref
          .read(repositoryProvider)
          .saveToSavings(
            amount: amount,
            mode: _mode,
            projectId: _mode == DistributionMode.precis ? _projectId : null,
          );
      invalidateAll(ref);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${euro(amount)} mis de côté')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Épargner maintenant', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Le montant est débité du compte courant tout de suite.',
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                label: 'Montant',
                autofocus: true,
              ),
              const SizedBox(height: 16),
              SegmentedButton<DistributionMode>(
                segments: const [
                  ButtonSegment(
                    value: DistributionMode.automatique,
                    label: Text('Automatique'),
                    icon: Icon(Icons.call_split),
                  ),
                  ButtonSegment(
                    value: DistributionMode.precis,
                    label: Text('Un projet'),
                    icon: Icon(Icons.flag),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 8),
              if (_mode == DistributionMode.automatique)
                Text(
                  'Réparti selon les pourcentages des projets, le reste vers '
                  'Épargne générale.',
                  style: theme.textTheme.bodySmall,
                )
              else ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _projectId,
                  decoration: const InputDecoration(labelText: 'Projet'),
                  isExpanded: true,
                  items: [
                    for (final p in widget.projects)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  validator: (id) => id == null ? 'Projet requis' : null,
                  onChanged: (id) => setState(() => _projectId = id),
                ),
                const SizedBox(height: 8),
                Text(
                  'Si l\'objectif du projet est atteint, l\'excédent part vers '
                  'le Fond de sécurité.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Épargner'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
