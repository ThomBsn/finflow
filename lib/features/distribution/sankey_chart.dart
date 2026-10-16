import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';

/// Couleur d'un flux, par nature (jamais par rang). Palette validée
/// (dataviz, toutes paires, clair et sombre) : bleu = argent entrant,
/// orange = dépenses, vert d'eau = épargne ; gris neutre étiqueté pour le
/// compte commun et les soldes.
Color flowColor(FlowKind kind, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (kind) {
    FlowKind.opening ||
    FlowKind.salary ||
    FlowKind.income => dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6),
    FlowKind.expense =>
      dark ? const Color(0xFFD95926) : const Color(0xFFEB6834),
    FlowKind.savings =>
      dark ? const Color(0xFF199E70) : const Color(0xFF1BAF7A),
    _ => dark ? const Color(0xFF7A7974) : const Color(0xFF9B9A94),
  };
}

/// Ordre d'affichage : entrées puis sorties, regroupées par nature.
const _order = [
  FlowKind.salary,
  FlowKind.income,
  FlowKind.opening,
  FlowKind.overdraft,
  FlowKind.expense,
  FlowKind.shared,
  FlowKind.savings,
  FlowKind.remaining,
  FlowKind.openingOverdraft,
];

List<SettlementFlow> sortFlows(Iterable<SettlementFlow> flows) =>
    flows.toList()..sort((a, b) {
      final byKind = _order.indexOf(a.kind).compareTo(_order.indexOf(b.kind));
      return byKind != 0 ? byKind : b.amount.compareTo(a.amount);
    });

/// Sankey à trois colonnes : entrées → mois → sorties. Toucher un flux le
/// met en évidence ; libellés et montants sont toujours visibles.
class SankeyChart extends StatefulWidget {
  const SankeyChart({super.key, required this.flows, this.height = 320});

  final List<SettlementFlow> flows;
  final double height;

  @override
  State<SankeyChart> createState() => _SankeyChartState();
}

class _SankeyChartState extends State<SankeyChart> {
  int? _selected;
  _Layout? _layout;

  @override
  void didUpdateWidget(SankeyChart old) {
    super.didUpdateWidget(old);
    if (old.flows != widget.flows) _selected = null;
  }

  void _onTap(TapUpDetails details) {
    final hit = _layout?.hitTest(details.localPosition);
    setState(() => _selected = hit == _selected ? null : hit);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incoming = sortFlows(widget.flows.where((f) => f.incoming));
    final outgoing = sortFlows(widget.flows.where((f) => !f.incoming));

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = math.max(incoming.length, outgoing.length);
        final size = Size(
          constraints.maxWidth,
          math.max(widget.height, _Layout.minHeight(count)),
        );
        final layout = _Layout(size, incoming, outgoing);
        _layout = layout;
        return Semantics(
          label:
              'Diagramme de répartition : '
              '${incoming.map((f) => '${f.label} ${euro(f.amount)}').join(', ')} '
              'vers ${outgoing.map((f) => '${f.label} ${euro(f.amount)}').join(', ')}',
          child: GestureDetector(
            onTapUp: _onTap,
            child: CustomPaint(
              size: size,
              painter: _SankeyPainter(
                layout: layout,
                selected: _selected,
                brightness: theme.brightness,
                surface: theme.colorScheme.surfaceContainerLow,
                center: theme.colorScheme.outline,
                labelStyle: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                amountStyle: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Node {
  _Node(this.flow, this.rect, this.centerTop, this.centerBottom);

  final SettlementFlow flow;
  final Rect rect;

  /// Segment correspondant sur la barre centrale.
  final double centerTop;
  final double centerBottom;
}

class _Layout {
  _Layout(
    this.size,
    List<SettlementFlow> incoming,
    List<SettlementFlow> outgoing,
  ) {
    labelWidth = math.min(140, size.width * 0.3);
    final leftX = labelWidth;
    final rightX = size.width - labelWidth - nodeWidth;
    centerX = (size.width - nodeWidth) / 2;

    final total = math.max(
      incoming.fold<double>(0, (s, f) => s + f.amount),
      outgoing.fold<double>(0, (s, f) => s + f.amount),
    );
    // Même échelle des deux côtés (les bandes doivent se raccorder), assez
    // petite pour que chaque nœud ait un emplacement à la hauteur de son
    // libellé.
    final scale = total <= 0
        ? 0.0
        : math.min(_fitScale(incoming), _fitScale(outgoing));
    centerHeight = total * scale;
    centerTop = (size.height - centerHeight) / 2;

    List<_Node> column(List<SettlementFlow> flows, double x) {
      final slots = [for (final f in flows) math.max(f.amount * scale, slot)];
      final used =
          slots.fold<double>(0, (s, h) => s + h) +
          gap * math.max(flows.length - 1, 0);
      var y = (size.height - used) / 2;
      var c = centerTop;
      return [
        for (final (i, f) in flows.indexed)
          () {
            final h = math.max(f.amount * scale, 2.0);
            final node = _Node(
              f,
              Rect.fromLTWH(x, y + (slots[i] - h) / 2, nodeWidth, h),
              c,
              c + f.amount * scale,
            );
            y += slots[i] + gap;
            c += f.amount * scale;
            return node;
          }(),
      ];
    }

    left = column(incoming, leftX);
    right = column(outgoing, rightX);
  }

  /// Plus grande échelle (px par euro) pour laquelle la colonne tient dans la
  /// hauteur, les petits nœuds occupant au moins [slot] pixels.
  double _fitScale(List<SettlementFlow> flows) {
    final available = size.height - gap * math.max(flows.length - 1, 0);
    final total = flows.fold<double>(0, (s, f) => s + f.amount);
    if (total <= 0) return double.infinity;
    var scale = available / total;
    for (var i = 0; i < 8; i++) {
      final small = flows.where((f) => f.amount * scale < slot);
      final large = total - small.fold<double>(0, (s, f) => s + f.amount);
      if (large <= 0) break;
      scale = math.max((available - slot * small.length) / large, 0);
    }
    return scale;
  }

  /// Hauteur minimale pour que [count] nœuds et leurs libellés tiennent.
  static double minHeight(int count) => count * (slot + gap) + 80;

  static const nodeWidth = 10.0;
  static const gap = 6.0;

  /// Hauteur d'un libellé (nom + montant).
  static const slot = 32.0;

  final Size size;
  late final double labelWidth;
  late final double centerX;
  late final double centerTop;
  late final double centerHeight;
  late final List<_Node> left;
  late final List<_Node> right;

  List<_Node> get nodes => [...left, ...right];

  /// Index du flux touché (nœud, libellé ou bande), null sinon.
  int? hitTest(Offset p) {
    for (final (i, n) in nodes.indexed) {
      final isLeft = i < left.length;
      final row = Rect.fromLTRB(
        isLeft ? 0 : n.rect.left,
        n.rect.top - 6,
        isLeft ? n.rect.right : size.width,
        n.rect.bottom + 6,
      );
      if (row.contains(p)) return i;
    }
    return null;
  }
}

class _SankeyPainter extends CustomPainter {
  _SankeyPainter({
    required this.layout,
    required this.selected,
    required this.brightness,
    required this.surface,
    required this.center,
    required this.labelStyle,
    required this.amountStyle,
  });

  final _Layout layout;
  final int? selected;
  final Brightness brightness;
  final Color surface;
  final Color center;
  final TextStyle labelStyle;
  final TextStyle amountStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    final cx = l.centerX;
    final bandAlpha = brightness == Brightness.dark ? 0.45 : 0.35;

    for (final (i, n) in l.nodes.indexed) {
      final isLeft = i < l.left.length;
      final color = flowColor(n.flow.kind, brightness);
      final faded = selected != null && selected != i;
      final paint = Paint()
        ..color = color.withValues(alpha: faded ? 0.1 : bandAlpha);

      // Bande entre le nœud et son segment sur la barre centrale, avec 1 px
      // de retrait de chaque côté pour un espace de 2 px entre bandes.
      final x0 = isLeft ? n.rect.right : cx + _Layout.nodeWidth;
      final x1 = isLeft ? cx : n.rect.left;
      final top0 = isLeft ? n.rect.top : n.centerTop + 1;
      final bottom0 = isLeft ? n.rect.bottom : n.centerBottom - 1;
      final top1 = isLeft ? n.centerTop + 1 : n.rect.top;
      final bottom1 = isLeft ? n.centerBottom - 1 : n.rect.bottom;
      final mid = (x0 + x1) / 2;
      final band = Path()
        ..moveTo(x0, top0)
        ..cubicTo(mid, top0, mid, top1, x1, top1)
        ..lineTo(x1, bottom1)
        ..cubicTo(mid, bottom1, mid, bottom0, x0, bottom0)
        ..close();
      canvas.drawPath(band, paint);

      canvas.drawRRect(
        RRect.fromRectAndRadius(n.rect, const Radius.circular(2)),
        Paint()..color = color.withValues(alpha: faded ? 0.3 : 1),
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, l.centerTop, _Layout.nodeWidth, l.centerHeight),
        const Radius.circular(2),
      ),
      Paint()..color = center,
    );

    _labels(canvas, l.left, alignRight: true);
    _labels(canvas, l.right, alignRight: false, offset: l.left.length);
  }

  /// Libellé (une ligne, tronqué) et montant, centrés sur chaque nœud.
  void _labels(
    Canvas canvas,
    List<_Node> nodes, {
    required bool alignRight,
    int offset = 0,
  }) {
    final width = layout.labelWidth - 8;
    for (final (i, n) in nodes.indexed) {
      final faded = selected != null && selected != i + offset;
      TextPainter line(String text, TextStyle style) => TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(
            color: style.color!.withValues(alpha: faded ? 0.4 : 1),
          ),
        ),
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: width);

      final name = line(n.flow.label, labelStyle);
      final amount = line(euro(n.flow.amount), amountStyle);
      var y = n.rect.center.dy - (name.height + amount.height) / 2;
      for (final text in [name, amount]) {
        final x = alignRight ? n.rect.left - 8 - text.width : n.rect.right + 8;
        text.paint(canvas, Offset(x, y));
        y += text.height;
      }
    }
  }

  @override
  bool shouldRepaint(_SankeyPainter old) =>
      old.layout != layout ||
      old.selected != selected ||
      old.brightness != brightness;
}
