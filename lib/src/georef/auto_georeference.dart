import 'dart:math' as math;

import '../aip/aip_points.dart';
import '../geo/georeference.dart';
import '../pdf/chart_pdf.dart';
import 'fix_matching.dart';
import 'grid_labels.dart';

/// Georeferences a chart from everything it offers: its coordinate grid
/// and the named fixes drawn on it.
///
/// * A full grid is the strongest evidence. Fixes, when found, must agree
///   with it, or the chart is refused: one of them is misread.
/// * One grid line each way plus a scale bar can't check itself; agreeing
///   fixes replace it with a measured fit.
/// * With no usable grid, fixes alone are used if enough of them agree.
Object autoGeoreference(RenderedChart chart, PointDirectory points) {
  final grid = georeferenceFromGridLabels(chart);
  // An estimated grid fit is rough but close: let it seed fix matching.
  Georeference? hint;
  var hintRadius = 0.0;
  if (grid is AutoGeoreference && grid.estimated) {
    hint = Georeference.fit(grid.points, projection: grid.projection);
    hintRadius = 1.5 * grid.rmsMeters / hint.metersPerPixel;
  }
  final fixes = points.isEmpty
      ? const AutoGeoreferenceFailure('No AIP points to match.')
      : georeferenceFromFixes(
          chart,
          points,
          hint: hint,
          hintRadius: hintRadius,
        );

  if (grid is AutoGeoreference && fixes is AutoGeoreference) {
    final gridGeo = Georeference.fit(grid.points, projection: grid.projection);
    // Largest gap, on the ground, between where the grid puts each fix
    // and where the chart draws it.
    var gap = 0.0;
    for (final p in fixes.points) {
      final px = (gridGeo.toPixel(p.position) - p.pixel).distance;
      gap = math.max(gap, px * gridGeo.metersPerPixel);
    }
    final allowed = grid.estimated
        ? grid.rmsMeters * 1.5
        : math.max(4 * grid.rmsMeters, 3 * fixes.rmsMeters) +
              8 * gridGeo.metersPerPixel;
    if (gap > allowed) {
      return AutoGeoreferenceFailure(
        'Grid and named fixes disagree by ${gap.round()} m.',
      );
    }
    final n = fixes.points.length;
    if (grid.estimated) {
      return fixes.copyWith(
        method: '$n named fixes, agreeing with the grid',
        notToScaleAreas: grid.notToScaleAreas,
      );
    }
    return grid.copyWith(method: '${grid.method}, confirmed by $n fixes');
  }
  if (grid is AutoGeoreference) return grid;
  if (fixes is AutoGeoreference) {
    return fixes.copyWith(notToScaleAreas: notToScaleAreas(chart.texts));
  }
  final g = grid as AutoGeoreferenceFailure;
  final f = fixes as AutoGeoreferenceFailure;
  return AutoGeoreferenceFailure('${g.reason} ${f.reason}');
}
