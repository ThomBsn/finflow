import 'package:finflow/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

Subscription sub(int day, {DateTime? lastCharge}) => Subscription(
  id: 'id',
  name: 'Abo',
  amount: 10,
  billingDay: day,
  active: true,
  lastChargeDate: lastCharge,
);

void main() {
  test('prochain prélèvement ce mois-ci s\'il est à venir', () {
    expect(sub(20).nextCharge(DateTime(2026, 10, 16)), DateTime(2026, 10, 20));
    expect(
      sub(16).nextCharge(DateTime(2026, 10, 16, 15)),
      DateTime(2026, 10, 16),
    );
  });

  test('mois suivant si le jour est passé ou déjà prélevé', () {
    expect(sub(13).nextCharge(DateTime(2026, 10, 16)), DateTime(2026, 11, 13));
    expect(
      sub(
        20,
        lastCharge: DateTime(2026, 10, 20),
      ).nextCharge(DateTime(2026, 10, 20)),
      DateTime(2026, 11, 20),
    );
  });

  test('jour ramené au dernier jour du mois', () {
    expect(sub(31).nextCharge(DateTime(2027, 2, 10)), DateTime(2027, 2, 28));
    expect(
      sub(31).nextCharge(DateTime(2026, 12, 31, 9)),
      DateTime(2026, 12, 31),
    );
    expect(
      sub(
        31,
        lastCharge: DateTime(2027, 1, 31),
      ).nextCharge(DateTime(2027, 1, 31)),
      DateTime(2027, 2, 28),
    );
  });
}
