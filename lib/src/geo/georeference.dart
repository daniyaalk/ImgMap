import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'lat_lng.dart';
import 'projection.dart';

/// A known correspondence between a pixel on the chart image and a position
/// on the ground.
class ControlPoint {
  const ControlPoint({required this.pixel, required this.position});

  /// Pixel position in the stored image's own coordinate space
  /// (origin top-left, y down), independent of how it is displayed.
  final Offset pixel;
  final LatLng position;

  Map<String, dynamic> toJson() => {
    'x': pixel.dx,
    'y': pixel.dy,
    ...position.toJson(),
  };

  factory ControlPoint.fromJson(Map<String, dynamic> json) => ControlPoint(
    pixel: Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
    position: LatLng.fromJson(json),
  );
}

/// Thrown when control points cannot define a usable transform.
class GeoreferenceException implements Exception {
  GeoreferenceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Maps between ground positions and chart pixels.
///
/// Positions are first projected to Web Mercator, which is conformal: a
/// chart's own projection (Lambert conformal conic for most aeronautical
/// charts) agrees with it locally up to scale and rotation. The projected
/// plane is then mapped to pixels with:
///  * a similarity transform (scale + rotation + translation) for 2 points,
///  * a least-squares affine transform for 3 or more points, which also
///    absorbs non-uniform scanning scale and skew.
///
/// Unlike a per-axis linear lat/lon interpolation this handles rotated or
/// non-north-up charts and does not assume a degree of longitude is the same
/// length as a degree of latitude.
class Georeference {
  Georeference._(
    this.projection,
    this._a,
    this._b,
    this._c,
    this._d,
    this._e,
    this._f,
    this.points,
    this.isAffine,
  ) {
    _det = _a * _e - _b * _d;
  }

  // pixel.x = a*X + b*Y + c ; pixel.y = d*X + e*Y + f  (X, Y in mercator m)
  final double _a, _b, _c, _d, _e, _f;
  late final double _det;

  final List<ControlPoint> points;

  /// The plane the transform is fitted in; should match the chart's own.
  final MapProjection projection;

  /// Whether the transform was fitted as a general affine (3+ points).
  final bool isAffine;

  static const int minPoints = 2;

  /// With [conformal], always fits scale, rotation and shift only. Right
  /// when the chart is known to be drawn in [projection] (true of AIP
  /// charts), and stable even when the points are nearly in a line; an
  /// affine fit also absorbs scanning skew but needs well-spread points.
  factory Georeference.fit(
    List<ControlPoint> points, {
    MapProjection projection = MapProjection.webMercator,
    bool conformal = false,
  }) {
    if (points.length < minPoints) {
      throw GeoreferenceException('At least $minPoints points are needed.');
    }
    final world = points.map((p) => projection.forward(p.position)).toList();
    final pixels = points.map((p) => p.pixel).toList();

    // Center both sets to keep the arithmetic well conditioned; mercator
    // values are ~1e7 m and their squares would swamp small differences.
    final wc = _mean(world);
    final pc = _mean(pixels);
    final w = world.map((o) => o - wc).toList();
    final px = pixels.map((o) => o - pc).toList();

    final Georeference result;
    if (points.length == 2 || conformal) {
      result = _fitSimilarity(w, px, wc, pc, points, projection);
    } else {
      result =
          _fitAffine(w, px, wc, pc, points, projection) ??
          _fitSimilarity(w, px, wc, pc, points, projection);
    }
    if (!result._det.isFinite || result._det.abs() < 1e-18) {
      throw GeoreferenceException(
        'Points are too close together or in a line to define the chart.',
      );
    }
    return result;
  }

  static Georeference _fitSimilarity(
    List<Offset> w,
    List<Offset> px,
    Offset wc,
    Offset pc,
    List<ControlPoint> points,
    MapProjection projection,
  ) {
    // Least-squares similarity: pixel = s*R*world + t, written as
    // x' =  p*X + q*Y,  y' = q*X - p*Y. The sign flip on y reflects the
    // image's y-down axis against mercator's y-up (north up).
    double sxx = 0, num1 = 0, num2 = 0;
    for (var i = 0; i < w.length; i++) {
      final X = w[i].dx, Y = w[i].dy, x = px[i].dx, y = px[i].dy;
      sxx += X * X + Y * Y;
      num1 += X * x - Y * y;
      num2 += Y * x + X * y;
    }
    if (sxx == 0) {
      throw GeoreferenceException('Points must be at different positions.');
    }
    final p = num1 / sxx, q = num2 / sxx;
    final a = p, b = q, d = q, e = -p;
    return Georeference._(
      projection,
      a,
      b,
      pc.dx - a * wc.dx - b * wc.dy,
      d,
      e,
      pc.dy - d * wc.dx - e * wc.dy,
      List.unmodifiable(points),
      false,
    );
  }

  static Georeference? _fitAffine(
    List<Offset> w,
    List<Offset> px,
    Offset wc,
    Offset pc,
    List<ControlPoint> points,
    MapProjection projection,
  ) {
    // Centered data means the translation drops out; solve the 2x2 normal
    // equations for each pixel axis.
    double sXX = 0, sXY = 0, sYY = 0, sXx = 0, sYx = 0, sXy = 0, sYy = 0;
    for (var i = 0; i < w.length; i++) {
      final X = w[i].dx, Y = w[i].dy;
      sXX += X * X;
      sXY += X * Y;
      sYY += Y * Y;
      sXx += X * px[i].dx;
      sYx += Y * px[i].dx;
      sXy += X * px[i].dy;
      sYy += Y * px[i].dy;
    }
    final det = sXX * sYY - sXY * sXY;
    // Nearly collinear ground points leave the cross-line direction
    // unconstrained, and an affine fit would amplify tap error along it.
    // Require the point spread's minor axis to be at least ~3% of its
    // major axis (eigenvalue ratio of the scatter matrix).
    final trace = sXX + sYY;
    final root = math.sqrt(math.max(0, trace * trace / 4 - det));
    final minor = trace / 2 - root, major = trace / 2 + root;
    if (major <= 0 || minor / major < 1e-3) return null;
    final a = (sXx * sYY - sYx * sXY) / det;
    final b = (sYx * sXX - sXx * sXY) / det;
    final d = (sXy * sYY - sYy * sXY) / det;
    final e = (sYy * sXX - sXy * sXY) / det;
    return Georeference._(
      projection,
      a,
      b,
      pc.dx - a * wc.dx - b * wc.dy,
      d,
      e,
      pc.dy - d * wc.dx - e * wc.dy,
      List.unmodifiable(points),
      true,
    );
  }

  /// Chart pixel for a ground position.
  Offset toPixel(LatLng position) {
    final m = projection.forward(position);
    return Offset(_a * m.dx + _b * m.dy + _c, _d * m.dx + _e * m.dy + _f);
  }

  /// Ground position for a chart pixel.
  LatLng toLatLng(Offset pixel) {
    final x = pixel.dx - _c, y = pixel.dy - _f;
    final mx = (_e * x - _b * y) / _det;
    final my = (-_d * x + _a * y) / _det;
    return projection.inverse(Offset(mx, my));
  }

  /// Screen-space angle, in radians clockwise from image "up", of true north
  /// at [position]. Rotate a track/heading marker by `heading + this`.
  double northAngleAt(LatLng position) {
    final here = toPixel(position);
    final north = toPixel(
      LatLng(math.min(position.latitude + 0.01, 85), position.longitude),
    );
    final v = north - here;
    return math.atan2(v.dx, -v.dy);
  }

  /// Distance in meters between where each control point was placed and
  /// where the fitted transform puts its ground position. Always ~0 with
  /// two points, so a third point is the only way to check a chart.
  List<double> residualsMeters() => [
    for (final p in points) toLatLng(p.pixel).distanceTo(p.position),
  ];

  /// Root-mean-square residual in meters, or null if it cannot be judged
  /// (fewer than 3 points).
  double? get rmsErrorMeters {
    if (points.length < 3) return null;
    final r = residualsMeters();
    return math.sqrt(r.fold<double>(0, (s, v) => s + v * v) / r.length);
  }

  /// Approximate meters per image pixel near the control points.
  double get metersPerPixel {
    final c = toLatLng(_mean(points.map((p) => p.pixel).toList()));
    final px = toPixel(c);
    return toLatLng(px + const Offset(1, 0)).distanceTo(c);
  }
}

/// Spherical Web Mercator, in meters (y north).
Offset projectMercator(LatLng p) => MapProjection.webMercator.forward(p);

LatLng unprojectMercator(Offset m) => MapProjection.webMercator.inverse(m);

Offset _mean(List<Offset> pts) {
  var x = 0.0, y = 0.0;
  for (final p in pts) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / pts.length, y / pts.length);
}
