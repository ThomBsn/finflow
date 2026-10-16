import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<void> showSubscriptionForm(
  BuildContext context, {
  Subscription? subscription,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => SubscriptionForm(subscription: subscription),
);

class SubscriptionForm extends ConsumerStatefulWidget {
  const SubscriptionForm({super.key, this.subscription});

  final Subscription? subscription;

  @override
  ConsumerState<SubscriptionForm> createState() => _SubscriptionFormState();
}

class _SubscriptionFormState extends ConsumerState<SubscriptionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _day;
  late bool _active;
  bool _saving = false;
  String? _error;

  Subscription? get _subscription => widget.subscription;

  @override
  void initState() {
    super.initState();
    final s = _subscription;
    _name = TextEditingController(text: s?.name ?? '');
    _amount = TextEditingController(
      text: s == null ? '' : amountInput(s.amount),
    );
    _day = TextEditingController(
      text: '${s?.billingDay ?? DateTime.now().day}',
    );
    _active = s?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
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
          .saveSubscription(
            id: _subscription?.id,
            name: _name.text.trim(),
            amount: parseAmount(_amount.text)!,
            billingDay: int.parse(_day.text),
            active: _active,
          ),
    );
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Supprimer « ${_subscription!.name} » ?',
      content: 'Les prélèvements déjà créés sont conservés.',
      action: 'Supprimer',
    );
    if (ok) {
      await _run(
        () =>
            ref.read(repositoryProvider).deleteSubscription(_subscription!.id),
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
                _subscription == null
                    ? 'Nouvel abonnement'
                    : 'Modifier l\'abonnement',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom'),
                textCapitalization: TextCapitalization.sentences,
                autofocus: _subscription == null,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              AmountField(controller: _amount, label: 'Montant mensuel'),
              const SizedBox(height: 16),
              DayOfMonthField(
                controller: _day,
                label: 'Jour de prélèvement',
                helperText:
                    'La dépense est créée automatiquement ce jour-là (le '
                    'dernier jour du mois s\'il est plus court). Un abonnement '
                    'créé après son jour de prélèvement démarre le mois suivant.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif'),
                subtitle: const Text('Suspendu : plus de prélèvement'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_subscription != null)
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
