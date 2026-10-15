import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';

class FinflowApp extends StatelessWidget {
  const FinflowApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FinFlow',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: router,
    );
  }
}
