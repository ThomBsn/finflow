import 'package:flutter/material.dart';

/// Demande de confirmation d'une action destructive ; true si confirmée.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? content,
  required String action,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: content == null ? null : Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Champ « jour du mois » (1 à 31).
class DayOfMonthField extends StatelessWidget {
  const DayOfMonthField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 3,
      ),
      keyboardType: TextInputType.number,
      validator: (v) {
        final day = int.tryParse(v ?? '');
        return day == null || day < 1 || day > 31 ? 'Jour entre 1 et 31' : null;
      },
    );
  }
}
