import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<CloseResult?> showCloseMonthSheet(
  BuildContext context,
  MonthSummary summary,
) => showModalBottomSheet<CloseResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => CloseMonthSheet(summary: summary),
);

/// Modale « Passer au mois suivant » (spec §3) avec aperçu calculé par la
/// base (`preview_close_month`), mêmes formules que la clôture réelle.
class CloseMonthSheet extends ConsumerStatefulWidget {
  const CloseMonthSheet({super.key, required this.summary});

  final MonthSummary summary;

  @override
  ConsumerState<CloseMonthSheet> createState() => _CloseMonthSheetState();
}

class _CloseMonthSheetState extends ConsumerState<CloseMonthSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _salary;
  late final TextEditingController _sharedTransfer;
  bool _specialMonth = false;
  CloseResult? _preview;
  Timer? _debounce;
  bool _closing = false;
  String? _error;

  MonthSummary get _summary => widget.summary;

  @override
  void initState() {
    super.initState();
    String initial(double v) => v > 0 ? amountInput(v) : '';
    _salary = TextEditingController(text: initial(_summary.suggestedSalary))
      ..addListener(_schedulePreview);
    _sharedTransfer = TextEditingController(
      text: initial(_summary.suggestedSharedTransfer),
    )..addListener(_schedulePreview);
    _schedulePreview(); // pas de setState pendant initState
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _salary.dispose();
    _sharedTransfer.dispose();
    super.dispose();
  }

  double? get _salaryValue => parseAmount(_salary.text);
  double? get _sharedValue => _sharedTransfer.text.trim().isEmpty
      ? 0
      : parseAmount(_sharedTransfer.text);

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refreshPreview);
  }

  Future<void> _refreshPreview() async {
    final salary = _salaryValue;
    final shared = _sharedValue;
    if (salary == null || shared == null || salary < 0 || shared < 0) {
      setState(() => _preview = null);
      return;
    }
    try {
      final preview = await ref
          .read(repositoryProvider)
          .previewCloseMonth(
            salary: salary,
            sharedTransfer: shared,
            specialMonth: _specialMonth,
          );
      // Ignore une réponse dépassée par une saisie plus récente.
      if (mounted && salary == _salaryValue && shared == _sharedValue) {
        setState(() => _preview = preview);
      }
    } catch (_) {
      if (mounted) setState(() => _preview = null);
    }
  }

  Future<void> _close() async {
    if (!_formKey.currentState!.validate()) return;
    final monthName = monthLabel(_summary.month);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clôturer $monthName ?'),
        content: const Text(
          'Les dépenses du mois seront réglées et l\'épargne virée. '
          'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(repositoryProvider)
          .closeMonth(
            month: _summary.month,
            salary: _salaryValue!,
            sharedTransfer: _sharedValue!,
            specialMonth: _specialMonth,
          );
      invalidateAll(ref);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthName = monthLabel(_summary.month);
    final nextName = monthLabel(_summary.nextMonth);
    final monthNotOver = DateTime.now().isBefore(_summary.nextMonth);

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
              Text('Passer au mois suivant', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Clôture de $monthName, ouverture de $nextName'),
              if (monthNotOver) ...[
                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '$monthName n\'est pas terminé : ne clôture que si ton '
                      'salaire de $nextName est arrivé.',
                      style: TextStyle(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              AmountField(
                controller: _salary,
                label: 'Salaire de $nextName',
                allowZero: true,
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _sharedTransfer,
                label: 'Virement compte commun',
                allowZero: true,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mois particulier'),
                subtitle: const Text(
                  'Pas de virement d\'épargne : le surplus reste sur le courant',
                ),
                value: _specialMonth,
                onChanged: (v) {
                  setState(() => _specialMonth = v ?? false);
                  _refreshPreview();
                },
              ),
              const SizedBox(height: 8),
              _Preview(preview: _preview),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _closing ? null : _close,
                icon: const Icon(Icons.event_repeat),
                label: Text('Clôturer $monthName'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.preview});

  final CloseResult? preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = preview;

    Widget row(String label, double? value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value == null ? '…' : euro(value),
            style: strong
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aperçu', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            row('Dépenses du mois réglées', p?.totalExpenses),
            row('Épargne virée', p?.totalSavings, strong: true),
            row('Compte courant ensuite', p?.courant),
            if (p != null && p.courant < 0) ...[
              const SizedBox(height: 8),
              Text(
                'Le compte courant sera à découvert : tu pourras le rééquilibrer '
                'depuis le Fond de sécurité.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
