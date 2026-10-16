import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/chart_colors.dart';
import '../../core/format.dart';
import '../../data/models.dart';

/// Jauge segmentée d'un budget du mois :
///   orange    mensualités d'étalement (engagées)
///   bleu      autres dépenses
///   vert d'eau abonnements pas encore prélevés (réservés)
///   fond      ce qui reste vraiment disponible
/// Au-delà de l'enveloppe, la jauge s'étend et un trait marque l'alloué.
class BudgetGauge extends StatelessWidget {
  const BudgetGauge({
    super.key,
    required this.status,
    this.height = 6,
    this.legend = false,
  });

  final BudgetStatus status;
  final double height;

  /// Affiche la légende chiffrée sous la jauge.
  final bool legend;

  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(theme.brightness);
    final s = status;
    final installment = math.max(s.installmentSpent, 0.0);
    final other = math.max(s.spent - s.installmentSpent, 0.0);
    final reserved = math.max(s.reserved, 0.0);
    final used = installment + other + reserved;
    final scale = math.max(s.allocated, used);
    final over = used > s.allocated;

    final segments = [
      (installment, colors.orange, 'Étalements'),
      (other, colors.blue, 'Dépenses'),
      (reserved, colors.aqua, 'Abonnements à venir'),
    ].where((seg) => seg.$1 > 0).toList();

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final children = <Widget>[];
        for (final (i, seg) in segments.indexed) {
          final w = scale > 0 ? width * seg.$1 / scale : 0.0;
          children.add(
            Container(
              width: math.max(w - (i < segments.length - 1 ? _gap : 0), 1),
              color: seg.$2,
            ),
          );
          if (i < segments.length - 1) {
            children.add(const SizedBox(width: _gap));
          }
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: Container(
                height: height,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Row(children: children),
              ),
            ),
            if (over && s.allocated > 0)
              Positioned(
                left: width * s.allocated / scale - 1,
                top: -3,
                child: Container(
                  width: 2,
                  height: height + 6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
          ],
        );
      },
    );

    if (!legend) {
      return Semantics(
        label: segments.map((seg) => '${seg.$3} ${euro(seg.$1)}').join(', '),
        child: bar,
      );
    }

    final available = s.allocated - used;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final seg in segments)
              _LegendItem(color: seg.$2, label: '${seg.$3} ${euro(seg.$1)}'),
            if (available > 0)
              _LegendItem(
                color: theme.colorScheme.surfaceContainerHighest,
                label: 'Disponible ${euro(available)}',
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
