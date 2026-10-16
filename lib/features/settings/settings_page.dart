import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Réglages : salaire et virement commun habituels (épargne prévue,
/// préremplissage de la clôture), marge de sécurité.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (s) => _SettingsForm(settings: s),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final Settings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _salary;
  late final TextEditingController _shared;
  late final TextEditingController _margin;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _salary = TextEditingController(text: amountInput(s.defaultSalary));
    _shared = TextEditingController(text: amountInput(s.defaultSharedTransfer));
    _margin = TextEditingController(text: amountInput(s.safetyMargin));
  }

  @override
  void dispose() {
    _salary.dispose();
    _shared.dispose();
    _margin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .saveSettings(
            Settings(
              defaultSalary: parseAmount(_salary.text)!,
              defaultSharedTransfer: parseAmount(_shared.text)!,
              safetyMargin: parseAmount(_margin.text)!,
            ),
          );
      ref.invalidate(settingsProvider);
      ref.invalidate(monthSummaryProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Réglages enregistrés')),
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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ces montants servent à calculer l\'épargne prévue en direct '
                  'et à préremplir « Passer au mois suivant ».',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                AmountField(
                  controller: _salary,
                  label: 'Salaire habituel',
                  allowZero: true,
                ),
                const SizedBox(height: 16),
                AmountField(
                  controller: _shared,
                  label: 'Virement compte commun habituel',
                  allowZero: true,
                ),
                const SizedBox(height: 16),
                AmountField(
                  controller: _margin,
                  label: 'Marge de sécurité',
                  allowZero: true,
                  helperText:
                      'Laissée sur le compte courant à chaque clôture, pour '
                      'les prélèvements immédiats (abonnements).',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Enregistrer'),
                ),
                const SizedBox(height: 40),
                OutlinedButton.icon(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
