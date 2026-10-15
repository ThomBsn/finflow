import 'package:finflow/features/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpLogin(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: LoginPage()));

  testWidgets('valide les champs avant tout appel réseau', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Se connecter'));
    await tester.pump();

    expect(find.text('E-mail invalide'), findsOneWidget);
    expect(find.text('6 caractères minimum'), findsOneWidget);
  });

  testWidgets('bascule entre connexion et création de compte', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Connexion au compte'), findsOneWidget);

    await tester.tap(find.text('Pas de compte ? En créer un'));
    await tester.pump();

    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text('Créer le compte'), findsOneWidget);
  });
}
