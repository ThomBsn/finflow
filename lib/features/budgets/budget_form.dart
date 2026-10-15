import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<void> showBudgetForm(BuildContext context, {Budget? budget}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => BudgetForm(budget: budget),
    );

class BudgetForm extends ConsumerStatefulWidget {
  const BudgetForm({super.key, this.budget});

  final Budget? budget;

  @override
  ConsumerState<BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _category;
  late final TextEditingController _amount;
  late String _icon;
  late bool _horsBudget;
  bool _saving = false;
  String? _error;

  Budget? get _budget => widget.budget;
  bool get _isSystem => _budget?.isSystem ?? false;
  bool get _computedAmount => _budget?.hasComputedAmount ?? false;

  @override
  void initState() {
    super.initState();
    _category = TextEditingController(text: _budget?.category ?? '');
    _amount = TextEditingController(
      text: amountInput(_budget?.monthlyAmount ?? 0),
    );
    _icon = _budget?.icon ?? 'category';
    _horsBudget = _budget?.horsBudget ?? false;
  }

  @override
  void dispose() {
    _category.dispose();
    _amount.dispose();
    super.dispose();
  }

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
    await _run(
      () => ref
          .read(repositoryProvider)
          .saveBudget(
            id: _budget?.id,
            category: _category.text.trim(),
            monthlyAmount: _computedAmount ? 0 : parseAmount(_amount.text)!,
            icon: _icon,
            horsBudget: _horsBudget,
          ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer « ${_budget!.category} » ?'),
        content: const Text(
          'Les transactions de cette catégorie sont conservées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _run(() => ref.read(repositoryProvider).deleteBudget(_budget!.id));
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
              Text(
                _budget == null ? 'Nouveau budget' : 'Modifier le budget',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _category,
                enabled: !_isSystem,
                decoration: InputDecoration(
                  labelText: 'Catégorie',
                  helperText: _isSystem
                      ? 'Catégorie utilisée par l\'app, non renommable'
                      : (_budget != null
                            ? 'Renommer met aussi à jour les transactions'
                            : null),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                label: 'Montant mensuel',
                allowZero: true,
                enabled: !_computedAmount && !_horsBudget,
                helperText: _computedAmount
                    ? 'Calculé : somme des abonnements actifs'
                    : null,
              ),
              const SizedBox(height: 16),
              Text('Icône', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in categoryIcons.entries)
                    IconButton(
                      isSelected: entry.key == _icon,
                      icon: Icon(entry.value),
                      style: IconButton.styleFrom(
                        backgroundColor: entry.key == _icon
                            ? theme.colorScheme.primaryContainer
                            : null,
                      ),
                      onPressed: () => setState(() => _icon = entry.key),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hors budget'),
                subtitle: const Text(
                  'Pas d\'enveloppe : seules les dépenses sont affichées',
                ),
                value: _horsBudget,
                onChanged: _isSystem
                    ? null
                    : (v) => setState(() => _horsBudget = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_budget != null && !_isSystem)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
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
