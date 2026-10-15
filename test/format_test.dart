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
}
