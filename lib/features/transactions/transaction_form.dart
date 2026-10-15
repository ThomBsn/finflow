import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<void> showTransactionForm(
  BuildContext context, {
  required List<Budget> budgets,
  Transaction? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => TransactionForm(budgets: budgets, existing: existing),
);

/// Saisie ou modification d'une dépense / d'un revenu.
class TransactionForm extends ConsumerStatefulWidget {
  const TransactionForm({super.key, required this.budgets, this.existing});

  final List<Budget> budgets;
  final Transaction? existing;

  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _label;
  late TransactionType _type;
  late DateTime _date;
  String? _category;
  late bool _horsBudget;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _amount = TextEditingController(
      text: t == null ? '' : amountInput(t.amount),
    );
    _label = TextEditingController(text: t?.label ?? '');
    _type = t?.type ?? TransactionType.depense;
    final now = DateTime.now();
    _date = t?.date ?? DateTime(now.year, now.month, now.day);
    _category = t?.category;
    _horsBudget = t?.horsBudget ?? false;
  }

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  void _selectCategory(String? category) {
    setState(() {
      _category = category;
      // « Hors budget » suit la catégorie (ex. Frais externes), modifiable ensuite.
      _horsBudget = widget.budgets.any(
        (b) => b.category == category && b.horsBudget,
      );
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked != null) setState(() => _date = picked);
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
          .saveTransaction(
            TransactionDraft(
              id: widget.existing?.id,
              date: _date,
              type: _type,
              amount: parseAmount(_amount.text)!,
              label: _label.text.trim(),
              category: _category,
              horsBudget: _horsBudget,
            ),
          ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette transaction ?'),
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
      await _run(
        () =>
            ref.read(repositoryProvider).deleteTransaction(widget.existing!.id),
      );
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
                _isNew ? 'Nouvelle transaction' : 'Modifier la transaction',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.depense,
                    label: Text('Dépense'),
                    icon: Icon(Icons.remove),
                  ),
                  ButtonSegment(
                    value: TransactionType.revenu,
                    label: Text('Revenu'),
                    icon: Icon(Icons.add),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              if (_type == TransactionType.revenu) ...[
                const SizedBox(height: 8),
                Text(
                  'Un revenu (remboursement, prime…) vient en déduction des '
                  'dépenses du mois.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                label: 'Montant',
                autofocus: _isNew,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Libellé'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                isExpanded: true,
                items: [
                  if (_type == TransactionType.revenu)
                    const DropdownMenuItem(child: Text('Aucune')),
                  for (final b in widget.budgets)
                    DropdownMenuItem(
                      value: b.category,
                      child: Text(b.category),
                    ),
                ],
                validator: (c) => _type == TransactionType.depense && c == null
                    ? 'Catégorie requise'
                    : null,
                onChanged: _selectCategory,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(dayLabel(_date)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: _pickDate,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hors budget'),
                subtitle: const Text(
                  'Exclu des budgets, mais déduit à la fin du mois',
                ),
                value: _horsBudget,
                onChanged: (v) => setState(() => _horsBudget = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (!_isNew)
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
