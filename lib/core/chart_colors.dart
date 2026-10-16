import 'package:flutter/material.dart';

/// Palette des graphiques (Sankey, jauges de budget). Trois teintes
/// validées ensemble (dataviz : toutes paires, daltonisme compris, clair et
/// sombre) + un gris neutre toujours accompagné d'un libellé.
class ChartColors {
  const ChartColors._(this.blue, this.orange, this.aqua, this.neutral);

  factory ChartColors.of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static const _light = ChartColors._(
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFF9B9A94),
  );
  static const _dark = ChartColors._(
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFF7A7974),
  );

  final Color blue;
  final Color orange;
  final Color aqua;
  final Color neutral;
}
