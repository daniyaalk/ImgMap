import 'dart:math' as math;
import 'dart:ui';

import '../geo/coordinate_format.dart';
import '../geo/lat_lng.dart';
import '../geo/projection.dart';
import 'grid_labels.dart' show GridLabel;

/// An affine map from image pixels to a projection's plane, fitted so each
/// grid label lies on its meridian or parallel.
///
///   x = a·u + b·v + c + x0
///   y = d·u + e·v + f + y0
///
/// with (u, v) pixels relative to the labels' centroid. In Mercator a
/// longitude label pins x alone and the problem is linear; in projections
/// where meridians converge (UTM, Lambert) it isn't, so the fit is refined
/// by Gauss–Newton on ground-distance residuals.
class GridFit {
  GridFit._(this.projection, this._p, this._pc, this._x0, this._y0);

  final MapProjection projection;
  final List<double> _p;
  final Offset _pc;
  final double _x0, _y0;

  static GridFit? solve(
    List<GridLabel> labels,
    MapProjection projection, {
    GridFit? start,
  }) {
    final init = start ?? _initial(labels, projection);
    if (init == null) return null;
    var fit = init;
    final spread = _spread(labels, fit._pc);
    for (var iteration = 0; iteration < 15; iteration++) {
      final step = fit._gaussNewtonStep(labels, spread);
      if (step == null) return null;
      fit = step.$1;
      if (step.$2 < 1e-3) break;
    }
    return fit._det.abs() < 1e-18 ? null : fit;
  }

  double get _det => _p[0] * _p[4] - _p[1] * _p[3];

  LatLng latLngOf(Offset pixel) {
    final u = pixel.dx - _pc.dx, v = pixel.dy - _pc.dy;
    return projection.inverse(
      Offset(
        _p[0] * u + _p[1] * v + _p[2] + _x0,
        _p[3] * u + _p[4] * v + _p[5] + _y0,
      ),
    );
  }

  Offset pixelOf(LatLng position) {
    final w = projection.forward(position);
    final x = w.dx - _x0 - _p[2], y = w.dy - _y0 - _p[5];
    return _pc +
        Offset((_p[4] * x - _p[1] * y) / _det, (-_p[3] * x + _p[0] * y) / _det);
  }

  /// Ground meters per image pixel at the labels' centroid.
  double get metersPerPixel =>
      math.sqrt(_det.abs()) / projection.scaleFactor(latLngOf(_pc));

  /// Departure from a conformal (shape-preserving) map, relative to scale.
  /// Charts' projections are conformal, so this should be near zero.
  double get skew =>
      math.sqrt(math.pow(_p[0] + _p[4], 2) + math.pow(_p[1] - _p[3], 2)) /
      (2 * math.sqrt(_det.abs()));

  /// Signed ground distance from a label's line to where the fit puts the
  /// label.
  double residualMeters(GridLabel l) {
    final at = latLngOf(l.center);
    const r = LatLng.earthRadiusMeters;
    if (l.axis == CoordAxis.longitude) {
      var d = at.longitude - l.value;
      d = (d + 540) % 360 - 180;
      return d * math.pi / 180 * r * math.cos(at.latitude * math.pi / 180);
    }
    return (at.latitude - l.value) * math.pi / 180 * r;
  }

  (GridFit, double)? _gaussNewtonStep(List<GridLabel> labels, double spread) {
    List<double> residuals(GridFit f) => [
      for (final l in labels) f.residualMeters(l),
      // Conformal prior with the image's y-down flip: a = -e, b = d.
      // Weak, but pins directions the labels leave open.
      0.1 * spread * (f._p[0] + f._p[4]),
      0.1 * spread * (f._p[1] - f._p[3]),
    ];

    final r0 = residuals(this);
    final s = math.sqrt(_det.abs());
    final jacobian = List.generate(r0.length, (_) => List<double>.filled(6, 0));
    for (var k = 0; k < 6; k++) {
      final h = 1e-6 * s * (k == 2 || k == 5 ? spread : 1);
      final p = [..._p];
      p[k] += h;
      final rk = residuals(GridFit._(projection, p, _pc, _x0, _y0));
      for (var i = 0; i < r0.length; i++) {
        jacobian[i][k] = (rk[i] - r0[i]) / h;
      }
    }
    final delta = leastSquares(jacobian, [for (final v in r0) -v]);
    if (delta == null) return null;
    final p = [for (var k = 0; k < 6; k++) _p[k] + delta[k]];
    // Size of the update in meters at the edge of the labels.
    final moved = math.sqrt(
      math.pow(delta[0] * spread, 2) +
          math.pow(delta[1] * spread, 2) +
          math.pow(delta[2], 2) +
          math.pow(delta[3] * spread, 2) +
          math.pow(delta[4] * spread, 2) +
          math.pow(delta[5], 2),
    );
    return (GridFit._(projection, p, _pc, _x0, _y0), moved);
  }

  /// Starting point: the linear Mercator solution, carried into
  /// [projection] through three nearby points.
  static GridFit? _initial(List<GridLabel> labels, MapProjection projection) {
    final lons = labels.where((l) => l.axis == CoordAxis.longitude).toList();
    final lats = labels.where((l) => l.axis == CoordAxis.latitude).toList();
    if (lons.isEmpty || lats.isEmpty) return null;
    var pc = Offset.zero;
    for (final l in labels) {
      pc += l.center;
    }
    pc /= labels.length.toDouble();
    final spread = _spread(labels, pc);
    if (spread == 0) return null;

    const merc = MapProjection.webMercator;
    double east(double lon) => merc.forward(LatLng(0, lon)).dx;
    double north(double lat) => merc.forward(LatLng(lat, 0)).dy;
    final x0 = lons.fold<double>(0, (s, l) => s + east(l.value)) / lons.length;
    final y0 = lats.fold<double>(0, (s, l) => s + north(l.value)) / lats.length;
    final rows = <List<double>>[];
    final ys = <double>[];
    for (final l in labels) {
      final u = l.center.dx - pc.dx, v = l.center.dy - pc.dy;
      if (l.axis == CoordAxis.longitude) {
        rows.add([u, v, 1, 0, 0, 0]);
        ys.add(east(l.value) - x0);
      } else {
        rows.add([0, 0, 0, u, v, 1]);
        ys.add(north(l.value) - y0);
      }
    }
    final w = 0.1 * spread;
    rows
      ..add([w, 0, 0, 0, w, 0])
      ..add([0, w, 0, -w, 0, 0]);
    ys.addAll([0, 0]);
    final p = leastSquares(rows, ys);
    if (p == null) return null;
    final mercFit = GridFit._(merc, p, pc, x0, y0);
    if (mercFit._det.abs() < 1e-18) return null;
    if (projection.id == merc.id) return mercFit;

    // Express the same pixel→ground mapping in [projection].
    final o = projection.forward(mercFit.latLngOf(pc));
    final ex = projection.forward(mercFit.latLngOf(pc + Offset(spread, 0)));
    final ey = projection.forward(mercFit.latLngOf(pc + Offset(0, spread)));
    return GridFit._(
      projection,
      [
        (ex.dx - o.dx) / spread,
        (ey.dx - o.dx) / spread,
        0,
        (ex.dy - o.dy) / spread,
        (ey.dy - o.dy) / spread,
        0,
      ],
      pc,
      o.dx,
      o.dy,
    );
  }

  static double _spread(List<GridLabel> labels, Offset pc) {
    var s = 0.0;
    for (final l in labels) {
      s += (l.center - pc).distanceSquared;
    }
    return math.sqrt(s / labels.length);
  }
}

/// Solves min |A p − y| through the normal equations; null if A leaves a
/// direction unconstrained.
List<double>? leastSquares(List<List<double>> a, List<double> y) {
  final n = a.first.length;
  final m = List.generate(n, (_) => List<double>.filled(n + 1, 0));
  for (var r = 0; r < a.length; r++) {
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        m[i][j] += a[r][i] * a[r][j];
      }
      m[i][n] += a[r][i] * y[r];
    }
  }
  var largest = 0.0;
  for (var i = 0; i < n; i++) {
    largest = math.max(largest, m[i][i].abs());
  }
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (m[pivot][col].abs() < 1e-10 * largest) return null;
    final tmp = m[col];
    m[col] = m[pivot];
    m[pivot] = tmp;
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final f = m[r][col] / m[col][col];
      for (var c = col; c <= n; c++) {
        m[r][c] -= f * m[col][c];
      }
    }
  }
  return [for (var i = 0; i < n; i++) m[i][n] / m[i][i]];
}
