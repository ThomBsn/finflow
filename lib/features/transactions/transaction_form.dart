import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../budgets/budget_gauge.dart';
import 'reimburse_sheet.dart';

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

/// Saisie ou modification d'une dépense / d'un revenu, ou virement entre
/// l'épargne et le courant.
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
  late bool _immediate;

  /// Mois de débit ; null : mois en cours.
  DateTime? _month;

  /// Nombre de mois d'étalement sur le budget, null si pas étalée.
  int? _installments;

  /// Virement : de l'épargne vers le courant (sinon l'inverse), depuis ou
  /// vers un projet (null : répartition automatique).
  bool _toCourant = true;
  String? _projectId;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;
  bool get _isTransfer => _type == TransactionType.transfert;

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
    _immediate = t?.immediate ?? false;
    _month = t?.month;
    _installments = t?.installments;
    _amount.addListener(() => setState(() {}));
  }

  /// Seule une dépense comptée dans un budget peut être étalée.
  bool get _canSpread =>
      _type == TransactionType.depense && !_horsBudget && _category != null;

  /// « 3 × 66,66 € sur Loisirs, d'octobre à décembre » ; la base tronque au
  /// centime et met le reliquat sur la dernière mensualité.
  String? get _spreadSummary {
    final amount = parseAmount(_amount.text);
    final n = _installments;
    if (amount == null || amount <= 0 || n == null) return null;
    final share = (amount / n * 100).truncateToDouble() / 100;
    final start = _month ?? ref.read(currentMonthProvider).value ?? _date;
    final last = DateTime(start.year, start.month + n - 1);
    return '$n × ${euro(share)} sur $_category, de '
        '${monthLabel(start).toLowerCase()} à ${monthLabel(last).toLowerCase()}';
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
      // « Hors budget » suit la catégorie (budget hors budget), modifiable ensuite.
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
    if (_isTransfer) {
      final repo = ref.read(repositoryProvider);
      final amount = parseAmount(_amount.text)!;
      return _run(
        () => _toCourant
            ? repo.withdrawFromSavings(amount: amount, projectId: _projectId)
            : repo.saveToSavings(
                amount: amount,
                mode: _projectId == null
                    ? DistributionMode.automatique
                    : DistributionMode.precis,
                projectId: _projectId,
              ),
      );
    }
    await _run(() async {
      final repo = ref.read(repositoryProvider);
      final installments = _canSpread ? _installments : null;
      final current = widget.existing?.installments;
      // Ne plus étaler avant d'enregistrer : la base refuse l'étalement
      // d'une dépense hors budget.
      if (installments == null && current != null) {
        await repo.setInstallments(
          widget.existing!.id,
          installments: null,
          current: current,
        );
      }
      final id = await repo.saveTransaction(
        TransactionDraft(
          id: widget.existing?.id,
          date: _date,
          type: _type,
          amount: parseAmount(_amount.text)!,
          label: _label.text.trim(),
          category: _category,
          horsBudget: _horsBudget,
          immediate: _type == TransactionType.depense && _immediate,
          month: _month ?? ref.read(currentMonthProvider).value,
        ),
      );
      if (installments != null) {
        await repo.setInstallments(
          id,
          installments: installments,
          current: current,
        );
      }
    });
  }

  /// Dépense hors budget déjà enregistrée : remboursable depuis l'épargne.
  bool get _reimbursable =>
      !_isNew &&
      _horsBudget &&
      widget.existing!.horsBudget &&
      _type == TransactionType.depense;

  double get _reimbursed =>
      ref.watch(reimbursementsProvider).value?[widget.existing?.id] ?? 0;

  Future<void> _reimburse() async {
    final done = await showReimburseSheet(context, expense: widget.existing!);
    if ((done ?? false) && mounted) Navigator.of(context).pop();
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
    final statuses = {
      for (final s
          in ref.watch(budgetStatusProvider).value ?? const <BudgetStatus>[])
        s.category: s,
    };
    final selected = statuses[_category];
    final pending = ref.watch(currentMonthProvider).value;
    final month = _month ?? pending;
    final months = <DateTime>{
      ?pending,
      if (pending != null) DateTime(pending.year, pending.month + 1),
      ?month,
    }.toList()..sort();

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
                segments: [
                  const ButtonSegment(
                    value: TransactionType.depense,
                    label: Text('Dépense'),
                    icon: Icon(Icons.remove),
                  ),
                  const ButtonSegment(
                    value: TransactionType.revenu,
                    label: Text('Revenu'),
                    icon: Icon(Icons.add),
                  ),
                  if (_isNew)
                    const ButtonSegment(
                      value: TransactionType.transfert,
                      label: Text('Virement'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                ],
                showSelectedIcon: false,
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
              if (_isTransfer)
                ..._transferFields(theme)
              else ...[
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
                  selectedItemBuilder: (_) => [
                    if (_type == TransactionType.revenu) const Text('Aucune'),
                    for (final b in widget.budgets) Text(b.category),
                  ],
                  items: [
                    if (_type == TransactionType.revenu)
                      const DropdownMenuItem(child: Text('Aucune')),
                    for (final b in widget.budgets)
                      DropdownMenuItem(
                        value: b.category,
                        child: _CategoryChoice(
                          category: b.category,
                          status: statuses[b.category],
                        ),
                      ),
                  ],
                  validator: (c) =>
                      _type == TransactionType.depense && c == null
                      ? 'Catégorie requise'
                      : null,
                  onChanged: _selectCategory,
                ),
                if (selected != null && !selected.horsBudget) ...[
                  const SizedBox(height: 12),
                  _CategoryGauge(status: selected),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(dayLabel(_date)),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: _pickDate,
                ),
                if (month != null) ...[
                  Text('Mois de débit', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SegmentedButton<DateTime>(
                    segments: [
                      for (final m in months)
                        ButtonSegment(value: m, label: Text(monthLabel(m))),
                    ],
                    selected: {month},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _month = s.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Le mois dont la clôture la réglera (débit différé de la '
                    'carte)',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hors budget'),
                  subtitle: const Text(
                    'Exclue des budgets, mais déduite du compte courant (ex. '
                    'avance remboursée ensuite depuis l\'épargne)',
                  ),
                  value: _horsBudget,
                  onChanged: (v) => setState(() => _horsBudget = v),
                ),
                if (_reimbursable)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _reimburse,
                      icon: const Icon(Icons.savings_outlined),
                      label: Text(
                        _reimbursed > 0
                            ? 'Remboursée ${euro(_reimbursed)} · rembourser encore'
                            : 'Rembourser depuis l\'épargne',
                      ),
                    ),
                  ),
                if (_type == TransactionType.depense)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Débit immédiat'),
                    subtitle: const Text(
                      'Sort du compte courant tout de suite (virement, '
                      'prélèvement…), pas avec le débit différé du mois',
                    ),
                    value: _immediate,
                    onChanged: (v) => setState(() => _immediate = v),
                  ),
                if (_canSpread) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Étaler sur le budget'),
                    subtitle: const Text(
                      'Dépensée en entier, mais le budget ne compte qu\'une '
                      'mensualité par mois',
                    ),
                    value: _installments != null,
                    onChanged: (v) =>
                        setState(() => _installments = v ? 3 : null),
                  ),
                  if (_installments != null)
                    DropdownButtonFormField<int>(
                      initialValue: _installments,
                      decoration: InputDecoration(
                        labelText: 'Nombre de mois',
                        helperText: _spreadSummary,
                        helperMaxLines: 2,
                      ),
                      items: [
                        for (final n in const [
                          2,
                          3,
                          4,
                          5,
                          6,
                          8,
                          10,
                          12,
                          18,
                          24,
                        ])
                          DropdownMenuItem(value: n, child: Text('$n mois')),
                      ],
                      onChanged: (n) => setState(() => _installments = n),
                    ),
                ],
              ],
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
                    child: Text(_isTransfer ? 'Virer' : 'Enregistrer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sens du virement et projet d'épargne concerné.
  List<Widget> _transferFields(ThemeData theme) {
    final projects =
        ref.watch(savingsProjectsProvider).value ?? const <SavingsProject>[];
    final courant = ref.watch(monthSummaryProvider).value?.courant;
    return [
      const SizedBox(height: 16),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: true,
            label: Text('Épargne → courant'),
            icon: Icon(Icons.south_west),
          ),
          ButtonSegment(
            value: false,
            label: Text('Courant → épargne'),
            icon: Icon(Icons.north_east),
          ),
        ],
        showSelectedIcon: false,
        selected: {_toCourant},
        onSelectionChanged: (s) => setState(() => _toCourant = s.first),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String?>(
        initialValue: _projectId,
        decoration: InputDecoration(
          labelText: _toCourant ? 'Depuis le projet' : 'Vers le projet',
        ),
        isExpanded: true,
        items: [
          DropdownMenuItem(
            child: Text(
              _toCourant
                  ? 'Aucun : Épargne générale d\'abord'
                  : 'Aucun : selon les pourcentages',
            ),
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
        _toCourant
            ? 'Le compte courant est crédité tout de suite. Sans projet, on '
                  'puise dans l\'Épargne générale, puis les autres projets, et '
                  'le Fond de sécurité en dernier. Ce qui n\'est pas dépensé '
                  'repart en épargne à la clôture.'
            : 'Le compte courant est débité tout de suite'
                  '${courant == null ? '' : ' (${euro(courant)} aujourd\'hui)'}.',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }
}

/// Catégorie dans la liste de choix, avec une mini-jauge de son budget.
class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({required this.category, required this.status});

  final String category;
  final BudgetStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    if (s == null || s.horsBudget || s.allocated <= 0) {
      return Text(category);
    }
    final remaining = s.allocated - s.spent - s.reserved;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(category, overflow: TextOverflow.ellipsis)),
            Text(
              remaining >= 0
                  ? 'reste ${euro(remaining)}'
                  : 'dépassé de ${euro(-remaining)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: remaining < 0 ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        BudgetGauge(status: s, height: 3),
      ],
    );
  }
}

/// Jauge du budget de la catégorie choisie, au mois en cours.
class _CategoryGauge extends StatelessWidget {
  const _CategoryGauge({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    final remaining = s.allocated - s.spent - s.reserved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BudgetGauge(status: s, height: 4),
        const SizedBox(height: 4),
        Text(
          s.allocated <= 0
              ? 'Dépensé ${euro(s.spent)} ce mois-ci, sans enveloppe'
              : '${euro(s.spent)} dépensés sur ${euro(s.allocated)} · '
                    '${remaining >= 0 ? 'reste ${euro(remaining)}' : 'dépassé de ${euro(-remaining)}'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: remaining < 0 && s.allocated > 0
                ? theme.colorScheme.error
                : null,
          ),
        ),
      ],
    );
  }
}
