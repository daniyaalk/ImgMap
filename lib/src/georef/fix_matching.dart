import 'dart:math' as math;
import 'dart:ui';

import '../aip/aip_points.dart';
import '../geo/georeference.dart';
import '../geo/lat_lng.dart';
import '../geo/projection.dart';
import '../pdf/chart_pdf.dart';
import 'grid_labels.dart';

/// A named fix on a chart: its label, the symbol drawn beside it, and every
/// position the AIP publishes under that name.
class FixCandidate {
  const FixCandidate(this.name, this.symbol, this.positions, this.label);

  final String name;

  /// The fix's symbol, in image pixels.
  final Rect symbol;
  Offset get pixel => symbol.center;
  final List<LatLng> positions;
  final Rect label;
}

final _word = RegExp(r'(?<![A-Za-z0-9])([A-Z][A-Z0-9]{1,4})(?![A-Za-z0-9])');

/// A procedure designator after a name (`DUDUM 6E`, `AKTIM 8A`): the text
/// names a route, not the fix it sits by.
final _designator = RegExp(r'^\s*\d{1,2}[A-Z](?![A-Za-z])');

/// Symbol-sized vector shapes, bucketed by position for quick lookup; an
/// aerodrome chart can hold tens of thousands of shapes.
class _Symbols {
  _Symbols(Iterable<Rect> shapes) {
    for (final s in shapes) {
      final aspect = s.width / math.max(s.height, 1e-6);
      if (aspect < 0.5 || aspect > 2 || s.longestSide < 4) continue;
      (_buckets[_key(s.center)] ??= []).add(s);
    }
  }

  static const _cell = 128.0;
  final _buckets = <(int, int), List<Rect>>{};

  static (int, int) _key(Offset p) =>
      ((p.dx / _cell).floor(), (p.dy / _cell).floor());

  /// The shape nearest [score]-wise within [radius] of [around], sized
  /// between [minSize] and [maxSize].
  Rect? nearest(
    Rect around,
    double radius, {
    required double minSize,
    required double maxSize,
    bool Function(Rect)? exclude,
  }) {
    Rect? best;
    var bestDistance = double.infinity;
    final x0 = ((around.left - radius) / _cell).floor();
    final x1 = ((around.right + radius) / _cell).floor();
    final y0 = ((around.top - radius) / _cell).floor();
    final y1 = ((around.bottom + radius) / _cell).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        for (final s in _buckets[(x, y)] ?? const <Rect>[]) {
          final size = s.longestSide;
          if (size < minSize || size > maxSize) continue;
          if (exclude != null && exclude(s)) continue;
          final d = _distance(around, s.center);
          if (d < bestDistance && d <= radius) {
            bestDistance = d;
            best = s;
          }
        }
      }
    }
    return best;
  }
}

/// Finds labels of [directory]'s points on [chart] and the symbol each one
/// labels: the nearest symbol-sized shape that isn't part of the label.
List<FixCandidate> findFixCandidates(
  RenderedChart chart,
  PointDirectory directory,
) => _findCandidates(chart, directory, _Symbols(chart.shapes));

List<FixCandidate> _findCandidates(
  RenderedChart chart,
  PointDirectory directory,
  _Symbols symbols,
) {
  // Same name and symbol found twice (outline and fill) count once.
  final seen = <(String, int, int)>{};
  final found = <FixCandidate>[];
  for (final t in chart.texts) {
    for (final m in _word.allMatches(t.text)) {
      final name = m.group(1)!;
      if (!isFixName(name) || !directory.contains(name)) continue;
      if (_designator.hasMatch(t.text.substring(m.end))) continue;
      final label = t.boundsOf(m.start, m.end);
      final glyph = label.shortestSide;
      if (glyph <= 0) continue;
      final keepOut = label.inflate(2);
      final symbol = symbols.nearest(
        label,
        4.5 * glyph,
        minSize: 0.8 * glyph,
        maxSize: 2.5 * glyph,
        // Dashes of lines crossing the label, or bits of the label's box.
        exclude: (s) => keepOut.overlaps(s),
      );
      if (symbol == null) continue;
      final key = (name, symbol.center.dx.round(), symbol.center.dy.round());
      if (!seen.add(key)) continue;
      found.add(FixCandidate(name, symbol, directory[name], label));
    }
  }
  return found;
}

double _distance(Rect r, Offset p) {
  final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
  final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
  return math.sqrt(dx * dx + dy * dy);
}

/// Georeferences a chart from the named fixes drawn on it.
///
/// Two stages:
///  1. Consensus. Label-to-symbol pairs are noisy (a name in a note, a
///     symbol picked for the wrong label, a fix shifted along a leg marked
///     NOT TO SCALE, two points under one name), so every pair of fixes
///     proposes a transform and the one most others agree with wins
///     (RANSAC). A rough fit from elsewhere, such as one grid line and a
///     scale bar, can be passed as [hint] to seed this.
///  2. Guided matching. With a rough fit, each fix's symbol is looked for
///     where its published position falls, not where its label is, and
///     the fit is redone until it settles.
Object georeferenceFromFixes(
  RenderedChart chart,
  PointDirectory directory, {
  Georeference? hint,
  double hintRadius = 0,
}) {
  final symbols = _Symbols(chart.shapes);
  final candidates = _findCandidates(chart, directory, symbols);
  final names = candidates.map((c) => c.name).toSet();
  if (names.length < 4) {
    return AutoGeoreferenceFailure(
      'Only ${names.length} named fix${names.length == 1 ? '' : 'es'} found.',
    );
  }
  // Drawing and symbol-placement accuracy at the render size.
  final tolerance = 0.004 * chart.size.longestSide;
  // Names published once are the most trustworthy; cap the rest so the
  // pairwise search stays quick.
  candidates.sort((a, b) => a.positions.length.compareTo(b.positions.length));
  final pairs = [
    for (final c in candidates)
      for (final p in c.positions) (candidate: c, position: p),
  ].take(120).toList();
  // Symbols are drawn about label height; first-pass pairings are too
  // unreliable to size them from.
  final glyphs = [for (final c in candidates) c.label.shortestSide]..sort();
  final glyph = glyphs[glyphs.length ~/ 2];

  final lons = [for (final p in pairs) p.position.longitude]..sort();
  final lats = [for (final p in pairs) p.position.latitude]..sort();
  final utm =
      hint?.projection ??
      TransverseMercator.utm(
        TransverseMercator.utmZone(lons[lons.length ~/ 2]),
        north: lats[lats.length ~/ 2] >= 0,
      );

  // Label-paired fixes that agree with [geo].
  List<ControlPoint> agreeing(Georeference geo) {
    final best = <String, (double, ControlPoint)>{};
    for (final p in pairs) {
      final d = (geo.toPixel(p.position) - p.candidate.pixel).distance;
      if (d > tolerance) continue;
      final current = best[p.candidate.name];
      if (current == null || d < current.$1) {
        best[p.candidate.name] = (
          d,
          ControlPoint(pixel: p.candidate.pixel, position: p.position),
        );
      }
    }
    return [for (final v in best.values) v.$2];
  }

  // Every labelled fix, matched to the symbol where [geo] puts it.
  List<ControlPoint> guided(Georeference geo, double radius) {
    final best = <String, (double, ControlPoint)>{};
    for (final p in pairs) {
      final predicted = geo.toPixel(p.position);
      final s = symbols.nearest(
        Rect.fromCenter(center: predicted, width: 0, height: 0),
        radius,
        minSize: 0.8 * glyph,
        maxSize: 2.5 * glyph,
      );
      if (s == null) continue;
      final d = (s.center - predicted).distance;
      final current = best[p.candidate.name];
      if (current == null || d < current.$1) {
        best[p.candidate.name] = (
          d,
          ControlPoint(pixel: s.center, position: p.position),
        );
      }
    }
    return [for (final v in best.values) v.$2];
  }

  // Stage 1: consensus.
  final minSeparation = 0.15 * chart.size.shortestSide;
  var consensus = <ControlPoint>[];
  for (var i = 0; i < pairs.length; i++) {
    for (var j = i + 1; j < pairs.length; j++) {
      final a = pairs[i], b = pairs[j];
      if (a.candidate.name == b.candidate.name) continue;
      if ((a.candidate.pixel - b.candidate.pixel).distance < minSeparation) {
        continue;
      }
      final Georeference g;
      try {
        g = Georeference.fit(
          [
            ControlPoint(pixel: a.candidate.pixel, position: a.position),
            ControlPoint(pixel: b.candidate.pixel, position: b.position),
          ],
          projection: utm,
          conformal: true,
        );
      } on GeoreferenceException {
        continue;
      }
      // Chart scales run from about 1:5,000 to 1:2,000,000.
      final mpp = g.metersPerPixel;
      if (!(mpp > 0.3 && mpp < 3000)) continue;
      final inliers = agreeing(g);
      if (inliers.length > consensus.length) consensus = inliers;
    }
  }
  if (hint != null) {
    final seeded = guided(hint, math.max(hintRadius, tolerance));
    if (seeded.length > consensus.length) consensus = seeded;
  }
  if (consensus.length < 3) {
    return AutoGeoreferenceFailure(
      'Named fixes don\'t agree (${consensus.length} of ${names.length} '
      'consistent).',
    );
  }

  // Stage 2: guided matching until the set of fixes settles, in whichever
  // projection explains them best.
  Georeference? best;
  final fits = <Georeference>[];
  final projections = <MapProjection>{
    utm,
    ...TransverseMercator.utmCandidates(
      lons[lons.length ~/ 2],
      north: lats[lats.length ~/ 2] >= 0,
    ),
    MapProjection.webMercator,
  };
  for (final projection in projections) {
    var points = consensus;
    Georeference? g;
    for (var round = 0; round < 5; round++) {
      try {
        g = Georeference.fit(points, projection: projection, conformal: true);
      } on GeoreferenceException {
        g = null;
        break;
      }
      final next = guided(g, tolerance);
      if (next.length < 3 || _sameFixes(next, points)) break;
      points = next;
    }
    if (g != null && g.points.length >= 4) fits.add(g);
  }
  // The tightest fit among those matching nearly the most fixes: a wrong
  // projection can pick up an extra fix by fitting everything loosely.
  if (fits.isNotEmpty) {
    final most = fits.map((g) => g.points.length).reduce(math.max);
    for (final g in fits.where((g) => g.points.length >= most - 1)) {
      if (best == null || _rmsPixels(g) < _rmsPixels(best)) best = g;
    }
  }
  if (best == null) {
    return AutoGeoreferenceFailure(
      'Too few named fixes agree (${consensus.length}).',
    );
  }
  final fit = best;
  final points = fit.points;

  final spread = _bounds(points.map((p) => p.pixel));
  final diagonal = Offset(chart.size.width, chart.size.height).distance;
  if (Offset(spread.width, spread.height).distance < 0.3 * diagonal ||
      spread.shortestSide < 0.05 * chart.size.shortestSide) {
    return const AutoGeoreferenceFailure(
      'Agreeing fixes cover too little of the chart.',
    );
  }
  if (_rmsPixels(fit) > 0.5 * tolerance) {
    return const AutoGeoreferenceFailure('Named fixes fit loosely.');
  }
  // Each fix must be predicted by the others.
  for (var i = 0; i < points.length; i++) {
    final rest = [...points]..removeAt(i);
    try {
      final g = Georeference.fit(
        rest,
        projection: fit.projection,
        conformal: true,
      );
      if ((g.toPixel(points[i].position) - points[i].pixel).distance >
          2 * tolerance) {
        return const AutoGeoreferenceFailure('Named fixes don\'t cross-check.');
      }
    } on GeoreferenceException {
      return const AutoGeoreferenceFailure('Named fixes don\'t cross-check.');
    }
  }

  return AutoGeoreference(
    points: points,
    rmsMeters: fit.rmsErrorMeters!,
    labels: const [],
    method: '${points.length} named fixes',
    projection: fit.projection,
    conformal: true,
  );
}

bool _sameFixes(List<ControlPoint> a, List<ControlPoint> b) =>
    a.length == b.length &&
    a.every(
      (p) => b.any((q) => q.position == p.position && q.pixel == p.pixel),
    );

double _rmsPixels(Georeference g) {
  var s = 0.0;
  for (final p in g.points) {
    s += (g.toPixel(p.position) - p.pixel).distanceSquared;
  }
  return math.sqrt(s / g.points.length);
}

Rect _bounds(Iterable<Offset> points) {
  var r = Rect.fromPoints(points.first, points.first);
  for (final p in points) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r;
}
