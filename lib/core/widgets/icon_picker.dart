import 'package:flutter/material.dart';

import '../category_icons.dart';

/// Choix d'une icône parmi [categoryIcons] (budgets, projets d'épargne).
class IconPicker extends StatelessWidget {
  const IconPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Icône', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final entry in categoryIcons.entries)
              IconButton(
                tooltip: entry.key,
                isSelected: entry.key == selected,
                icon: Icon(entry.value),
                style: IconButton.styleFrom(
                  backgroundColor: entry.key == selected
                      ? theme.colorScheme.primaryContainer
                      : null,
                ),
                onPressed: () => onChanged(entry.key),
              ),
          ],
        ),
      ],
    );
  }
}
