import 'package:finflow/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseAmount accepte les saisies françaises', () {
    expect(parseAmount('12,50'), 12.5);
    expect(parseAmount('12.5'), 12.5);
    expect(parseAmount('1 200'), 1200);
    expect(parseAmount('1 200,99 €'), 1200.99);
    expect(parseAmount('-300'), -300);
    expect(parseAmount('abc'), isNull);
  });

  test('amountInput affiche une virgule et pas de décimales inutiles', () {
    expect(amountInput(200), '200');
    expect(amountInput(12.5), '12,50');
  });

  test('savingsProgress : montant, objectif et pourcentage arrondi', () {
    expect(savingsProgress(1000, 3000), '${euro(1000)} / ${euro(3000)} · 33 %');
    expect(savingsProgress(2999, 3000), endsWith('· 99 %'));
    expect(savingsProgress(3200, 3000), endsWith('· 106 %'));
    expect(savingsProgress(500, null), euro(500));
  });
}
