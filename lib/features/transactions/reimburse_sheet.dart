import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<bool?> showReimburseSheet(
  BuildContext context, {
  required Transaction expense,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ReimburseSheet(expense: expense),
);

/// Remboursement d'une dépense (souvent hors budget) depuis l'épargne :
/// virement épargne → courant relié à la dépense.
class ReimburseSheet extends ConsumerStatefulWidget {
  const ReimburseSheet({super.key, required this.expense});

  final Transaction expense;

  @override
  ConsumerState<ReimburseSheet> createState() => _ReimburseSheetState();
}

class _ReimburseSheetState extends ConsumerState<ReimburseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  String? _projectId;
  bool _saving = false;
  String? _error;

  Transaction get _expense => widget.expense;

  @override
  void initState() {
    super.initState();
    final done = ref.read(reimbursementsProvider).value?[_expense.id] ?? 0;
    final left = _expense.amount - done;
    _amount = TextEditingController(
      text: amountInput(left > 0 ? left : _expense.amount),
    );
  }

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
    try {
      await ref
          .read(repositoryProvider)
          .withdrawFromSavings(
            amount: parseAmount(_amount.text)!,
            projectId: _projectId,
            reimburses: _expense.id,
          );
      invalidateMonthData(ref);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects =
        ref.watch(savingsProjectsProvider).value ?? const <SavingsProject>[];
    final done = ref.watch(reimbursementsProvider).value?[_expense.id] ?? 0;
    final title = _expense.label.isNotEmpty
        ? _expense.label
        : (_expense.category ?? 'Dépense');

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
                'Rembourser depuis l\'épargne',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '$title · ${euro(_expense.amount)} le '
                '${dayLabel(_expense.date).toLowerCase()}'
                '${done > 0 ? ' · déjà remboursé ${euro(done)}' : ''}',
              ),
              const SizedBox(height: 16),
              AmountField(controller: _amount, label: 'Montant'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _projectId,
                decoration: const InputDecoration(
                  labelText: 'Depuis le projet',
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    child: Text('Aucun : Épargne générale d\'abord'),
                  ),
                  for (final p in projects)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        '${p.name} · ${euro(p.currentAmount)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _projectId = id),
              ),
              const SizedBox(height: 8),
              Text(
                'Le compte courant est crédité tout de suite ; la dépense '
                'reste déduite à la clôture.',
                style: theme.textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Rembourser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
