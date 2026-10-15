import 'package:flutter/material.dart';

import '../format.dart';

class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.allowZero = false,
    this.allowNegative = false,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final bool allowZero;
  final bool allowNegative;
  final bool enabled;
  final bool autofocus;

  String? _validate(String? input) {
    final amount = parseAmount(input ?? '');
    if (amount == null) return 'Montant invalide';
    if (!allowNegative && amount < 0) return 'Montant positif attendu';
    if (!allowZero && amount == 0) return 'Montant non nul attendu';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 3,
        suffixText: '€',
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: allowNegative,
      ),
      validator: enabled ? _validate : null,
    );
  }
}
