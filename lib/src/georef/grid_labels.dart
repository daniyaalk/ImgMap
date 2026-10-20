import 'dart:math' as math;
import 'dart:ui';

import '../geo/coordinate_format.dart';
import '../geo/georeference.dart';
import '../geo/lat_lng.dart';
import '../geo/projection.dart';
import '../pdf/chart_pdf.dart';
import 'grid_fit.dart';

/// A graticule label such as `28°50'0"N` found on a chart.
class GridLabel {
  const GridLabel(this.axis, this.value, this.center, this.text);

  final CoordAxis axis;

  /// Degrees, negative south/west.
  final double value;

  /// Middle of the label in image pixels.
  final Offset center;
  final String text;
}

class AutoGeoreference {
  const AutoGeoreference({
    required this.points,
    required this.rmsMeters,
    required this.labels,
    this.scaleRatio,
    required this.method,
    this.projection = MapProjection.webMercator,
    this.estimated = false,
    this.notToScaleAreas = const [],
    this.conformal = false,
  });

  /// [points] are meant for a conformal fit (see [Georeference.fit]).
  final bool conformal;

  /// Where the chart says NOT TO SCALE, in image pixels. Features there,
  /// such as fixes beyond a break symbol or inside an inset, aren't at
  /// their true positions.
  final List<Rect> notToScaleAreas;

  AutoGeoreference withNotToScale(List<Rect> areas) =>
      copyWith(notToScaleAreas: areas);

  AutoGeoreference copyWith({String? method, List<Rect>? notToScaleAreas}) =>
      AutoGeoreference(
        points: points,
        rmsMeters: rmsMeters,
        labels: labels,
        scaleRatio: scaleRatio,
        method: method ?? this.method,
        projection: projection,
        estimated: estimated,
        notToScaleAreas: notToScaleAreas ?? this.notToScaleAreas,
        conformal: conformal,
      );

  /// [rmsMeters] is an allowance for an unverifiable fit, not measured.
  final bool estimated;

  /// How the fit was made, for display, e.g. `grid labels`.
  final String method;

  /// The projection [points] should be fitted in.
  final MapProjection projection;

  /// Grid intersections, usable like hand-placed control points.
  final List<ControlPoint> points;

  /// How far, on the ground, the labels sit from where the fit puts their
  /// grid lines.
  final double rmsMeters;
  final List<GridLabel> labels;

  /// Fitted ground scale divided by the chart's own (scale bar or printed);
  /// near 1 when they agree. Null if it has none, or the fit used it.
  final double? scaleRatio;
}

class AutoGeoreferenceFailure {
  const AutoGeoreferenceFailure(this.reason);
  final String reason;
}

final _label = RegExp(
  r'''(?:([NSEW])\s*)?(\d{1,3})\s*[°º]\s*(\d{1,2})\s*['’′]\s*'''
  r'''(?:(\d{1,2}(?:\.\d+)?)\s*["”″]\s*)?([NSEW])?''',
);

/// Bumped when georeferencing improves, so charts that failed before are
/// tried again.
const autoGeoreferenceVersion = 5;

/// Boxes around each `NOT TO SCALE` (or `NTS`) on a chart.
List<Rect> notToScaleAreas(List<ChartText> texts) {
  final phrase = RegExp(r'NOT(?:DRAWN)?TOSCALE|(?<![A-Z])NTS(?![A-Z])');
  final areas = <Rect>[];
  for (final t in texts) {
    final compact = StringBuffer();
    final index = <int>[];
    for (var i = 0; i < t.text.length; i++) {
      if (t.text[i].trim().isEmpty) continue;
      compact.write(t.text[i].toUpperCase());
      index.add(i);
    }
    for (final m in phrase.allMatches(compact.toString())) {
      areas.add(t.boundsOf(index[m.start], index[m.end - 1] + 1));
    }
  }
  return areas;
}

/// Finds round-valued coordinate labels: graticule labels are whole
/// minutes, which keeps out the precise positions printed for fixes and
/// reference points.
List<GridLabel> findGridLabels(List<ChartText> texts) {
  final labels = <GridLabel>[];
  for (final t in texts) {
    // Match with spacing removed: word-processor charts letter-space
    // labels (`0 7 7 ° 1 0 ' E`). [index] maps back to the original.
    final compact = StringBuffer();
    final index = <int>[];
    for (var i = 0; i < t.text.length; i++) {
      if (t.text[i].trim().isEmpty) continue;
      compact.write(t.text[i]);
      index.add(i);
    }
    for (final m in _label.allMatches(compact.toString())) {
      final hemi = m.group(1) ?? m.group(5);
      if (hemi == null || (m.group(1) != null && m.group(5) != null)) continue;
      final deg = int.parse(m.group(2)!);
      final min = int.parse(m.group(3)!);
      final sec = m.group(4) == null ? 0.0 : double.parse(m.group(4)!);
      if (min >= 60 || sec != 0) continue;
      final axis = (hemi == 'N' || hemi == 'S')
          ? CoordAxis.latitude
          : CoordAxis.longitude;
      if (deg > (axis == CoordAxis.latitude ? 90 : 180)) continue;
      // A digit right before the match means it started mid-number.
      if (m.start > 0 &&
          RegExp(r'[\d.]').hasMatch(compact.toString()[m.start - 1])) {
        continue;
      }
      final sign = (hemi == 'S' || hemi == 'W') ? -1 : 1;
      labels.add(
        GridLabel(
          axis,
          sign * (deg + min / 60),
          t.boundsOf(index[m.start], index[m.end - 1] + 1).center,
          m.group(0)!,
        ),
      );
    }
  }
  return labels;
}

/// Georeferences a chart from its graticule labels.
///
/// Each label pins one map axis along a line through the label: a
/// longitude label fixes easting across the image, a latitude label
/// northing. With two or more labelled meridians and parallels, easting
/// and northing are fitted as linear functions of pixel position, and a
/// weak prior that the chart is conformal (true of the Lambert, Mercator
/// and UTM projections charts use) keeps the fit stable when labels run
/// along only one edge.
///
/// Many terminal charts label only one meridian and one parallel. Those
/// fix position and rotation; the scale then comes from the chart's scale
/// bar or printed `1:N`, and is accepted only when the two lines are
/// perpendicular and the scale sources agree.
///
/// A chart may mark parts of itself NOT TO SCALE: a shortened leg behind a
/// break symbol, or an enlarged inset. When its frame carries a full
/// coordinate grid, the map is still usable and the marked places are
/// returned in [AutoGeoreference.notToScaleAreas]; on weaker evidence such
/// a chart is refused.
Object georeferenceFromGridLabels(RenderedChart chart) {
  final notToScale = notToScaleAreas(chart.texts);
  final labels = findGridLabels(chart.texts);
  if (labels.length < 4) {
    return const AutoGeoreferenceFailure('No grid labels found.');
  }
  final scale = chartScale(chart);
  if (scale is AutoGeoreferenceFailure) return scale;
  final known = scale as ChartScale?;

  int distinct(CoordAxis axis) =>
      labels.where((l) => l.axis == axis).map((l) => l.value).toSet().length;
  if (distinct(CoordAxis.latitude) >= 2 && distinct(CoordAxis.longitude) >= 2) {
    final result = _fromGrid(labels, chart.size, known);
    if (result is AutoGeoreference && notToScale.isNotEmpty) {
      return result.withNotToScale(notToScale);
    }
    if (result is AutoGeoreferenceFailure && notToScale.isNotEmpty) {
      return AutoGeoreferenceFailure(
        'Marked not to scale, and its grid didn\'t check out: '
        '${result.reason}',
      );
    }
    return result;
  }
  if (notToScale.isNotEmpty) {
    return const AutoGeoreferenceFailure(
      'Marked not to scale, with no full coordinate grid to rely on.',
    );
  }
  if (known == null) {
    return const AutoGeoreferenceFailure(
      'Only one grid line each way and no scale to go with them.',
    );
  }
  return _fromSingleLines(labels, chart.size, known);
}

Object _fromGrid(List<GridLabel> labels, Size size, ChartScale? scale) {
  // Fit in each projection the chart might be drawn in and keep the one
  // the labels agree with best. AIP charts are commonly UTM, whose
  // meridians converge; Mercator's are parallel.
  final meanLon = _mean([
    for (final l in labels)
      if (l.axis == CoordAxis.longitude) l.value,
  ]);
  final meanLat = _mean([
    for (final l in labels)
      if (l.axis == CoordAxis.latitude) l.value,
  ]);
  final candidates = <MapProjection>[
    MapProjection.webMercator,
    ...TransverseMercator.utmCandidates(meanLon, north: meanLat >= 0),
  ];
  ({GridFit fit, List<GridLabel> labels, double rms})? best;
  for (final projection in candidates) {
    final trimmed = _trimmedFit(labels, projection);
    if (trimmed == null) continue;
    if (best == null || trimmed.rms < best.rms) best = trimmed;
  }
  if (best == null) {
    return const AutoGeoreferenceFailure(
      'Grid labels don\'t pin the chart\'s position and orientation.',
    );
  }
  final fit = best.fit;
  labels = best.labels;

  // Charts use conformal projections; a fit far from conformal means a
  // stray label steered it.
  if (fit.skew > 0.03) {
    return const AutoGeoreferenceFailure(
      'Grid labels don\'t pin the chart\'s orientation.',
    );
  }
  // Labels are centred on their lines to within a few pixels.
  if (best.rms > 8 * fit.metersPerPixel) {
    return AutoGeoreferenceFailure(
      'Grid labels disagree by ±${best.rms.round()} m.',
    );
  }
  // Every label must be predicted by the others. Fails when the labels
  // leave some direction undetermined (say, one row and one column of
  // labels) and a single label is all that decides it.
  for (var i = 0; i < labels.length; i++) {
    final rest = [...labels]..removeAt(i);
    final f = GridFit.solve(rest, fit.projection, start: fit);
    if (f == null ||
        f.residualMeters(labels[i]).abs() > 8 * fit.metersPerPixel) {
      return const AutoGeoreferenceFailure(
        'Grid labels don\'t cross-check: too few, or all along one edge.',
      );
    }
  }

  final points = _intersections(fit, labels, size);
  if (points.length < 3) {
    return const AutoGeoreferenceFailure('Too few grid lines on the chart.');
  }
  double? ratio;
  if (scale != null) {
    ratio = fit.metersPerPixel / scale.metersPerPixel;
    if (ratio < 0.9 || ratio > 1.11) {
      return AutoGeoreferenceFailure(
        'Grid labels imply a scale ${(ratio * 100).round()}% of the '
        '${scale.source}.',
      );
    }
  }
  return AutoGeoreference(
    points: points,
    rmsMeters: best.rms,
    labels: labels,
    scaleRatio: ratio,
    method: 'grid labels',
    projection: fit.projection,
  );
}

/// Fits [labels] in [projection], dropping labels that disagree with the
/// rest: coordinates in notes, insets or boxes that aren't grid labels. A
/// plain least-squares fit bends towards a far-off stray label, making good
/// labels look like the outliers, so each round drops the label whose
/// removal helps most.
({GridFit fit, List<GridLabel> labels, double rms})? _trimmedFit(
  List<GridLabel> labels,
  MapProjection projection,
) {
  var fit = GridFit.solve(labels, projection);
  if (fit == null) return null;
  double rmsOf(GridFit f, List<GridLabel> ls) =>
      _rms([for (final l in ls) f.residualMeters(l)]);
  while (labels.length > 5) {
    final current = fit!;
    final r = [for (final l in labels) current.residualMeters(l).abs()]..sort();
    final median = r[r.length ~/ 2];
    if (r.last <= math.max(3 * median, 4 * current.metersPerPixel)) break;
    GridFit? bestFit;
    var bestIndex = -1;
    var bestRms = double.infinity;
    for (var i = 0; i < labels.length; i++) {
      final rest = [...labels]..removeAt(i);
      final f = GridFit.solve(rest, projection, start: current);
      if (f == null) continue;
      final rms = rmsOf(f, rest);
      if (rms < bestRms) {
        bestRms = rms;
        bestFit = f;
        bestIndex = i;
      }
    }
    if (bestFit == null) break;
    labels = [...labels]..removeAt(bestIndex);
    fit = bestFit;
  }
  return (fit: fit!, labels: labels, rms: rmsOf(fit, labels));
}

double _mean(List<double> v) =>
    v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

Object _fromSingleLines(List<GridLabel> labels, Size size, ChartScale scale) {
  // The best-supported meridian and parallel.
  List<GridLabel> line(CoordAxis axis) {
    final groups = <double, List<GridLabel>>{};
    for (final l in labels.where((l) => l.axis == axis)) {
      (groups[l.value] ??= []).add(l);
    }
    if (groups.isEmpty) return const [];
    return groups.values.reduce((a, b) => b.length > a.length ? b : a);
  }

  final meridian = line(CoordAxis.longitude);
  final parallel = line(CoordAxis.latitude);
  final minSpan = 0.3 * math.min(size.width, size.height);
  final m = _Line.through(meridian), p = _Line.through(parallel);
  if (m == null || p == null || m.span < minSpan || p.span < minSpan) {
    return const AutoGeoreferenceFailure(
      'Grid labels don\'t span enough of the chart.',
    );
  }
  // Meridian points north (image up); parallel points east (right).
  final north = m.direction.dy <= 0 ? m.direction : -m.direction;
  final east = p.direction.dx >= 0 ? p.direction : -p.direction;
  final northFromEast = Offset(east.dy, -east.dx);
  final skew =
      math.asin(
        (north.dx * northFromEast.dy - north.dy * northFromEast.dx).clamp(
          -1.0,
          1.0,
        ),
      ) *
      180 /
      math.pi;
  if (skew.abs() > 1.5) {
    return AutoGeoreferenceFailure(
      'Grid lines are ${skew.abs().toStringAsFixed(1)}° from square.',
    );
  }
  final n = north + northFromEast;
  final up = n / n.distance;
  final right = Offset(-up.dy, up.dx);

  final origin = m.intersect(p);
  if (origin == null) {
    return const AutoGeoreferenceFailure('Grid lines don\'t cross.');
  }
  final lat0 = parallel.first.value, lon0 = meridian.first.value;
  // Control points a quarter of the chart away along each axis.
  final px = 0.25 * size.shortestSide;
  final d = px * scale.metersPerPixel;
  // WGS-84 radii of curvature: a sphere is ~0.3% off in latitude here.
  const a = 6378137.0, e2 = 0.00669437999014;
  final sin0 = math.sin(lat0 * math.pi / 180);
  final w = 1 - e2 * sin0 * sin0;
  final meridional = a * (1 - e2) / (w * math.sqrt(w));
  final primeVertical = a / math.sqrt(w);
  final dLat = d / meridional * 180 / math.pi;
  final dLon =
      d / (primeVertical * math.cos(lat0 * math.pi / 180)) * 180 / math.pi;
  final points = [
    ControlPoint(pixel: origin, position: LatLng(lat0, lon0)),
    ControlPoint(
      pixel: origin + right * px,
      position: LatLng(lat0, lon0 + dLon),
    ),
    ControlPoint(
      pixel: origin - right * px,
      position: LatLng(lat0, lon0 - dLon),
    ),
    ControlPoint(pixel: origin + up * px, position: LatLng(lat0 + dLat, lon0)),
    ControlPoint(pixel: origin - up * px, position: LatLng(lat0 - dLat, lon0)),
  ];
  final rms = _rms([
    for (final l in meridian) m.distanceTo(l.center) * scale.metersPerPixel,
    for (final l in parallel) p.distanceTo(l.center) * scale.metersPerPixel,
  ]);
  if (rms > 8 * scale.metersPerPixel) {
    return AutoGeoreferenceFailure(
      'Grid labels disagree by ±${rms.round()} m.',
    );
  }
  // Two labels per line can't reveal their own error, and the scale bar
  // isn't checked by anything: on real charts this has come out within
  // about 1% of the distance from the crossing. Report that, not ~0.
  var farthest = 0.0;
  for (final corner in [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ]) {
    farthest = math.max(farthest, (corner - origin).distance);
  }
  final estimate = math.max(rms, 0.01 * farthest * scale.metersPerPixel);
  return AutoGeoreference(
    points: points,
    rmsMeters: estimate,
    estimated: true,
    labels: [...meridian, ...parallel],
    method: 'grid lines + ${scale.source}',
    // The points sit close to the crossing, where projections agree; away
    // from it, a transverse Mercator follows converging meridians as most
    // national charts (UTM, Lambert) do, where Mercator would drift.
    // Zone from the chart's middle: a labelled meridian is often a zone
    // boundary (78°E), and the chart lies on one side of it.
    projection: TransverseMercator.utm(
      TransverseMercator.utmZone(
        lon0 +
            ((Offset(size.width, size.height) / 2 - origin).dx * right.dx +
                    (Offset(size.width, size.height) / 2 - origin).dy *
                        right.dy) *
                scale.metersPerPixel /
                (primeVertical * math.cos(lat0 * math.pi / 180)) *
                180 /
                math.pi,
      ),
      north: lat0 >= 0,
    ),
  );
}

double _rms(List<double> v) =>
    math.sqrt(v.fold<double>(0, (s, x) => s + x * x) / v.length);

/// A best-fit line through label centres.
class _Line {
  _Line(this.point, this.direction, this.span);

  final Offset point;
  final Offset direction;
  final double span;

  static _Line? through(List<GridLabel> labels) {
    if (labels.length < 2) return null;
    var c = Offset.zero;
    for (final l in labels) {
      c += l.center;
    }
    c /= labels.length.toDouble();
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (final l in labels) {
      final d = l.center - c;
      sxx += d.dx * d.dx;
      sxy += d.dx * d.dy;
      syy += d.dy * d.dy;
    }
    // Principal axis of the scatter.
    final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
    final dir = Offset(math.cos(angle), math.sin(angle));
    var lo = double.infinity, hi = -double.infinity;
    for (final l in labels) {
      final t = (l.center - c).dx * dir.dx + (l.center - c).dy * dir.dy;
      lo = math.min(lo, t);
      hi = math.max(hi, t);
    }
    return _Line(c, dir, hi - lo);
  }

  double distanceTo(Offset q) {
    final d = q - point;
    return (d.dx * direction.dy - d.dy * direction.dx).abs();
  }

  Offset? intersect(_Line other) {
    final cross =
        direction.dx * other.direction.dy - direction.dy * other.direction.dx;
    if (cross.abs() < 1e-6) return null;
    final d = other.point - point;
    final t = (d.dx * other.direction.dy - d.dy * other.direction.dx) / cross;
    return point + direction * t;
  }
}

/// A chart's ground scale and where it came from.
class ChartScale {
  const ChartScale(this.metersPerPixel, this.source);
  final double metersPerPixel;
  final String source;
}

/// The chart's scale from its scale bar, else its printed `1:N`.
///
/// Returns null if neither is found, or an [AutoGeoreferenceFailure] if
/// both are found and disagree, which means the chart was resized after
/// being drawn and the printed figure can't be trusted.
Object? chartScale(RenderedChart chart) {
  final bar = scaleBarMetersPerPixel(chart.texts);
  final denominator = printedScaleOf(chart.texts);
  final printed = denominator == null
      ? null
      : denominator * 0.0254 / 72 * chart.pointsPerPixel;
  if (bar != null && printed != null) {
    final ratio = bar / printed;
    if (ratio < 0.95 || ratio > 1.05) {
      return AutoGeoreferenceFailure(
        'Scale bar and printed 1:$denominator disagree by '
        '${((ratio - 1) * 100).abs().round()}%.',
      );
    }
    return ChartScale(bar, 'scale bar (matches 1:$denominator)');
  }
  if (bar != null) return ChartScale(bar, 'scale bar');
  if (printed != null) return ChartScale(printed, 'printed 1:$denominator');
  return null;
}

/// The `1:N` scale printed in [text], if any. Spacing must already be
/// removed.
int? printedScale(String text) {
  final m = RegExp(
    r'SCALE:?1:(\d{1,3}(?:[,.]\d{3})+|\d{4,8})(?![\d,.]*\d)',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  final n = int.parse(m.group(1)!.replaceAll(RegExp('[,.]'), ''));
  return n >= 1000 && n <= 50000000 ? n : null;
}

/// The printed scale on a chart, looking in each text run and in each run
/// joined to the next (for `SCALE` and `1:N` set apart).
int? printedScaleOf(List<ChartText> texts) {
  String compact(ChartText t) => t.text.replaceAll(RegExp(r'\s+'), '');
  for (var i = 0; i < texts.length; i++) {
    final here = compact(texts[i]);
    final found =
        printedScale(here) ??
        (i + 1 < texts.length
            ? printedScale(here + compact(texts[i + 1]))
            : null);
    if (found != null) return found;
  }
  return null;
}

/// Ground meters per pixel from a horizontal scale bar: tick labels
/// `0 5 10 15 …` in a row, evenly spaced, with `NM` or `KM` beside them.
double? scaleBarMetersPerPixel(List<ChartText> texts) {
  final tick = RegExp(r'^(\d{1,3})(NM|KM)?$');
  final unit = RegExp(r'^(NM|KM)$');
  final ticks = <({int value, Offset at, double h, String? unit})>[];
  final units = <({Offset at, double h, String unit})>[];
  for (final t in texts) {
    final s = t.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final b = t.bounds;
    if (tick.firstMatch(s) case final m?) {
      // A unit glued to the number shifts the box; centre on the digits.
      final digits = m.group(1)!.length;
      var start = 0;
      while (t.text[start].trim().isEmpty) {
        start++;
      }
      final db = t.boundsOf(start, start + digits);
      ticks.add((
        value: int.parse(m.group(1)!),
        at: db.center,
        h: db.height,
        unit: m.group(2),
      ));
    } else if (unit.hasMatch(s)) {
      units.add((at: b.center, h: b.height, unit: s));
    }
  }

  double? best;
  var bestCount = 0;
  for (final zero in ticks.where((t) => t.value == 0)) {
    final row =
        ticks
            .where(
              (t) =>
                  (t.at.dy - zero.at.dy).abs() < 0.6 * zero.h &&
                  t.at.dx >= zero.at.dx,
            )
            .toList()
          ..sort((a, b) => a.at.dx.compareTo(b.at.dx));
    // Keep a strictly increasing run from zero.
    final run = [row.first];
    for (final t in row.skip(1)) {
      if (t.value > run.last.value) run.add(t);
    }
    if (run.length < 3) continue;
    final last = run.last;
    String? u = last.unit;
    if (u == null) {
      for (final c in units) {
        if ((c.at.dy - zero.at.dy).abs() < 1.5 * zero.h &&
            c.at.dx > zero.at.dx &&
            c.at.dx - last.at.dx < 0.5 * (last.at.dx - zero.at.dx)) {
          u = c.unit;
          break;
        }
      }
    }
    if (u == null) continue;
    // Evenly spaced: positions linear in value.
    final pxPerUnit = (last.at.dx - zero.at.dx) / last.value;
    if (pxPerUnit <= 0) continue;
    final span = last.at.dx - zero.at.dx;
    final straight = run.every(
      (t) => (zero.at.dx + t.value * pxPerUnit - t.at.dx).abs() < 0.03 * span,
    );
    if (!straight || run.length <= bestCount) continue;
    bestCount = run.length;
    best = (u == 'NM' ? 1852 : 1000) / pxPerUnit;
  }
  return best;
}

/// Grid crossings of the labelled lines that fall on the image.
List<ControlPoint> _intersections(
  GridFit fit,
  List<GridLabel> labels,
  Size size,
) {
  final lats = {
    for (final l in labels)
      if (l.axis == CoordAxis.latitude) l.value,
  };
  final lons = {
    for (final l in labels)
      if (l.axis == CoordAxis.longitude) l.value,
  };
  final bounds = Offset.zero & size;
  return [
    for (final lat in lats)
      for (final lon in lons)
        if (fit.pixelOf(LatLng(lat, lon)) case final px
            when bounds.contains(px))
          ControlPoint(pixel: px, position: LatLng(lat, lon)),
  ];
}
