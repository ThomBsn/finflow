import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/home_widget_sync.dart';
import 'core/router.dart';
import 'data/providers.dart';
import 'core/theme.dart';

class FinflowApp extends ConsumerWidget {
  const FinflowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Le widget d'écran d'accueil suit le résumé du mois (vide si déconnecté).
    ref.listen(monthSummaryProvider, (_, next) {
      if (next case AsyncData(:final value)) syncHomeWidget(value);
    });

    return MaterialApp.router(
      title: 'FinFlow',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
