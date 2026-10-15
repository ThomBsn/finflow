import 'package:intl/intl.dart';

final _euro = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
final _month = DateFormat.yMMMM('fr_FR');
final _day = DateFormat('EEEE d MMMM', 'fr_FR');

String euro(num value) => _euro.format(value);

String monthLabel(DateTime month) =>
    toBeginningOfSentenceCase(_month.format(month));

String dayLabel(DateTime day) => toBeginningOfSentenceCase(_day.format(day));

/// Accepte « 12,50 », « 12.5 » ou « 1 200 ».
double? parseAmount(String input) => double.tryParse(
  input.replaceAll(RegExp(r'[\s  €]'), '').replaceAll(',', '.'),
);

/// Montant pour un champ de saisie : « 12,5 » plutôt que « 12.50 ».
String amountInput(double value) {
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return text.replaceAll('.', ',');
}
