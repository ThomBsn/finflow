import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/providers.dart';

/// Démarrage en cours de mois (spec §9) : soldes de départ, puis
/// l'utilisateur saisit les dépenses faites depuis le début du mois.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _courant = TextEditingController();
  final _safetyFund = TextEditingController(text: '0');
  final _generalSavings = TextEditingController(text: '0');
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Par défaut le courant vaut la marge de sécurité, comme après une transition.
    ref.read(repositoryProvider).safetyMargin().then((margin) {
      if (mounted && _courant.text.isEmpty) {
        _courant.text = amountInput(margin);
      }
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _courant.dispose();
    _safetyFund.dispose();
    _generalSavings.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .completeOnboarding(
            courant: parseAmount(_courant.text)!,
            safetyFund: parseAmount(_safetyFund.text)!,
            generalSavings: parseAmount(_generalSavings.text)!,
          );
      ref.invalidate(currentMonthProvider);
      ref.invalidate(monthsProvider);
      ref.read(onboardingGateProvider).markOnboarded();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bienvenue'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Point de départ', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Indique tes soldes tels qu\'ils étaient en début de mois, '
                    'juste après ton virement d\'épargne. Tu ajouteras ensuite '
                    'les dépenses faites depuis.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'N\'ajoute pas comme dépenses le salaire, le virement '
                        'vers le compte commun ni l\'épargne de ce mois : ils '
                        'sont déjà pris en compte dans le solde de départ.',
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AmountField(
                    controller: _courant,
                    label: 'Compte courant',
                    helperText:
                        'Normalement ta marge de sécurité, sauf si tu n\'as pas '
                        'épargné ce mois-ci.',
                    allowZero: true,
                    allowNegative: true,
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    controller: _safetyFund,
                    label: 'Fond de sécurité',
                    allowZero: true,
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    controller: _generalSavings,
                    label: 'Épargne générale',
                    helperText: 'Tes autres projets d\'épargne seront repris plus tard.',
                    allowZero: true,
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
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Commencer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
