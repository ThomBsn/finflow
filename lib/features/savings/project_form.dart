import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/icon_picker.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<void> showProjectForm(BuildContext context, {SavingsProject? project}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ProjectForm(project: project),
    );

class ProjectForm extends ConsumerStatefulWidget {
  const ProjectForm({super.key, this.project});

  final SavingsProject? project;

  @override
  ConsumerState<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends ConsumerState<ProjectForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _percentage;
  late final TextEditingController _target;
  late final TextEditingController _amount;
  late String _icon;
  bool _saving = false;
  String? _error;

  SavingsProject? get _project => widget.project;
  bool get _isNew => _project == null;

  /// Épargne générale : pourcentage et objectif fixés par la base.
  bool get _isDefault => _project?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    final p = _project;
    _name = TextEditingController(text: p?.name ?? '');
    _percentage = TextEditingController(text: amountInput(p?.percentage ?? 0));
    _target = TextEditingController(
      text: p?.targetAmount == null ? '' : amountInput(p!.targetAmount!),
    );
    _amount = TextEditingController(text: amountInput(p?.currentAmount ?? 0));
    _icon = p?.icon ?? 'flag';
  }

  @override
  void dispose() {
    _name.dispose();
    _percentage.dispose();
    _target.dispose();
    _amount.dispose();
    super.dispose();
  }

  double? get _targetValue =>
      _target.text.trim().isEmpty ? null : parseAmount(_target.text);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      invalidateMonthData(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(repositoryProvider);
    final name = _name.text.trim();
    final percentage = _isDefault ? 0.0 : parseAmount(_percentage.text)!;
    final target = _isDefault ? null : _targetValue;
    final amount = parseAmount(_amount.text)!;

    await _run(() async {
      if (_isNew) {
        await repo.createSavingsProject(
          name: name,
          percentage: percentage,
          target: target,
          initialAmount: amount,
          icon: _icon,
        );
        return;
      }
      final p = _project!;
      await repo.updateSavingsProject(
        id: p.id,
        name: name,
        percentage: percentage,
        target: target,
        icon: _icon,
      );
      if (amount != p.currentAmount) {
        await repo.adjustSavingsProject(p.id, amount);
      }
    });
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Supprimer « ${_project!.name} » ?',
      action: 'Supprimer',
    );
    if (ok) {
      await _run(
        () => ref.read(repositoryProvider).deleteSavingsProject(_project!.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _project;
    final canDelete = p != null && !p.isSystem;

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
              Text(
                _isNew ? 'Nouveau projet' : 'Modifier le projet',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom'),
                textCapitalization: TextCapitalization.sentences,
                autofocus: _isNew,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _percentage,
                enabled: !_isDefault,
                decoration: InputDecoration(
                  labelText: 'Part de l\'épargne automatique',
                  suffixText: '%',
                  helperText: _isDefault
                      ? 'Reçoit automatiquement le complément à 100 %'
                      : 'Somme de tous les projets : 100 % maximum',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _isDefault
                    ? null
                    : (v) {
                        final pct = parseAmount(v ?? '');
                        return pct == null || pct < 0 || pct > 100
                            ? 'Entre 0 et 100'
                            : null;
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _target,
                enabled: !_isDefault,
                decoration: InputDecoration(
                  labelText: 'Objectif',
                  suffixText: '€',
                  helperText: _isDefault
                      ? 'Sans plafond'
                      : 'Vide : sans objectif. Une fois atteint, l\'excédent '
                            'part vers le Fond de sécurité.',
                  helperMaxLines: 3,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _isDefault
                    ? null
                    : (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final target = parseAmount(v);
                        return target == null || target <= 0
                            ? 'Montant positif ou vide'
                            : null;
                      },
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                label: _isNew ? 'Déjà épargné' : 'Montant actuel',
                allowZero: true,
                helperText: _isNew
                    ? 'Pour reprendre un projet existant : ajouté au compte '
                          'épargne sans toucher au compte courant.'
                    : 'Correction, pour caler le projet sur ta banque : le '
                          'compte épargne suit, le compte courant ne bouge pas.',
              ),
              const SizedBox(height: 16),
              IconPicker(
                selected: _icon,
                onChanged: (icon) => setState(() => _icon = icon),
              ),
              if (p != null && !p.isSystem && p.currentAmount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Un projet ne peut être supprimé que vide.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (canDelete)
                    TextButton.icon(
                      onPressed: _saving || p.currentAmount > 0
                          ? null
                          : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
