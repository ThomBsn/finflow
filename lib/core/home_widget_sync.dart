import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import 'format.dart';

/// Classe Kotlin du widget (android/app/src/main/kotlin/.../FinflowWidgetProvider.kt).
const _provider = 'FinflowWidgetProvider';

final _time = DateFormat('d MMM HH:mm', 'fr_FR');

String _budgets(double value) => value >= 0
    ? '${euro(value)} si budgets épuisés'
    : 'budgets épuisés : ${euro(-value)} sous la marge';

/// Pousse le résumé du mois vers le widget Android (textes déjà formatés).
/// Sans résumé (déconnecté, avant l'onboarding), le widget invite à ouvrir
/// l'app. Sans effet hors Android.
Future<void> syncHomeWidget(MonthSummary? summary) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final data = <String, String?>{
      'month': summary == null
          ? 'FinFlow'
          : 'Épargne prévue · ${monthLabel(summary.month)}',
      'available': summary == null
          ? '—'
          : summary.needsSalary
          ? 'Salaire à renseigner'
          : euro(summary.projectedSavings < 0 ? 0 : summary.projectedSavings),
      'balances': summary == null
          ? 'Ouvre FinFlow pour charger tes soldes'
          : summary.needsSalary
          ? 'Réglages → salaire habituel'
          : '${_budgets(summary.projectedSavingsBudgets)} · '
                '${euro(summary.unsettledExpenses)} dépensés',
      'updated': summary == null
          ? ''
          : 'Mis à jour le ${_time.format(DateTime.now())}',
    };
    for (final entry in data.entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
    await HomeWidget.updateWidget(androidName: _provider);
  } catch (e) {
    // Le widget est un complément : un échec ne doit jamais gêner l'app.
    debugPrint('Widget non mis à jour : $e');
  }
}
