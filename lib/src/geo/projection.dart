import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'lat_lng.dart';

/// A map projection from WGS-84 positions to a plane, in meters
/// (x east, y north).
///
/// Charts are drawn in some projection; fitting control points in the same
/// one leaves only a flat (affine) relation to image pixels, so a chart
/// stays accurate edge to edge.
abstract class MapProjection {
  const MapProjection();

  /// Stable id stored with charts, e.g. `merc` or `utm43n`.
  String get id;

  /// Shown to people, e.g. `UTM zone 43N`.
  String get name;

  Offset forward(LatLng p);
  LatLng inverse(Offset xy);

  /// Projected meters per ground meter near [p].
  double scaleFactor(LatLng p) {
    const d = 1e-4; // degrees of latitude, ~11 m
    final a = forward(p), b = forward(LatLng(p.latitude + d, p.longitude));
    return (b - a).distance / (d * math.pi / 180 * LatLng.earthRadiusMeters);
  }

  static const MapProjection webMercator = WebMercator();

  /// Whether this app version can apply projection [id].
  static bool isKnown(String id) =>
      id == 'merc' || RegExp(r'^utm([1-9]|[1-5]\d|60)[ns]$').hasMatch(id);

  /// The projection for [id]; Web Mercator if unknown.
  static MapProjection fromId(String? id) {
    if (id == null || id == 'merc') return webMercator;
    final m = RegExp(r'^utm(\d{1,2})([ns])$').firstMatch(id);
    if (m != null) {
      return TransverseMercator.utm(
        int.parse(m.group(1)!),
        north: m.group(2) == 'n',
      );
    }
    return webMercator;
  }
}

/// Spherical Web Mercator.
class WebMercator extends MapProjection {
  const WebMercator();

  static const double _r = 6378137.0;
  static const double _maxLat = 85.05112878;

  @override
  String get id => 'merc';

  @override
  String get name => 'Mercator';

  @override
  Offset forward(LatLng p) {
    final lat = p.latitude.clamp(-_maxLat, _maxLat) * math.pi / 180;
    return Offset(
      _r * p.longitude * math.pi / 180,
      _r * math.log(math.tan(math.pi / 4 + lat / 2)),
    );
  }

  @override
  LatLng inverse(Offset m) => LatLng(
    (2 * math.atan(math.exp(m.dy / _r)) - math.pi / 2) * 180 / math.pi,
    m.dx / _r * 180 / math.pi,
  );
}

/// Transverse Mercator on the WGS-84 ellipsoid (Krüger series), as used
/// by UTM. Accurate to well under a meter across a zone.
class TransverseMercator extends MapProjection {
  TransverseMercator({
    required this.centralMeridian,
    this.scale = 0.9996,
    this.falseEasting = 500000,
    this.falseNorthing = 0,
    required this.id,
    required this.name,
  });

  /// UTM [zone] (1–60).
  factory TransverseMercator.utm(int zone, {bool north = true}) =>
      TransverseMercator(
        centralMeridian: zone * 6.0 - 183,
        falseNorthing: north ? 0 : 10000000,
        id: 'utm$zone${north ? 'n' : 's'}',
        name: 'UTM zone $zone${north ? 'N' : 'S'}',
      );

  /// UTM zones a chart near [longitude] may be drawn in: its own and both
  /// neighbours, since states often keep one zone for charts that spill
  /// over a boundary.
  static List<TransverseMercator> utmCandidates(
    double longitude, {
    required bool north,
  }) {
    final z = utmZone(longitude);
    return [
      for (final zone in [z, z - 1, z + 1])
        if (zone >= 1 && zone <= 60) TransverseMercator.utm(zone, north: north),
    ];
  }

  /// The UTM zone containing [longitude].
  static int utmZone(double longitude) =>
      ((longitude + 180) / 6).floor().clamp(0, 59) + 1;

  final double centralMeridian, scale, falseEasting, falseNorthing;
  @override
  final String id;
  @override
  final String name;

  static const double _a = 6378137.0;
  static const double _f = 1 / 298.257223563;
  static final double _n = _f / (2 - _f);
  static final double _bigA =
      _a / (1 + _n) * (1 + _n * _n / 4 + math.pow(_n, 4) / 64);
  static final List<double> _alpha = [
    _n / 2 - 2 * _n * _n / 3 + 5 * math.pow(_n, 3) / 16,
    13 * _n * _n / 48 - 3 * math.pow(_n, 3) / 5,
    61 * math.pow(_n, 3) / 240,
  ];
  static final List<double> _beta = [
    _n / 2 - 2 * _n * _n / 3 + 37 * math.pow(_n, 3) / 96,
    _n * _n / 48 + math.pow(_n, 3) / 15,
    17 * math.pow(_n, 3) / 480,
  ];
  static final List<double> _delta = [
    2 * _n - 2 * _n * _n / 3 - 2 * math.pow(_n, 3),
    7 * _n * _n / 3 - 8 * math.pow(_n, 3) / 5,
    56 * math.pow(_n, 3) / 15,
  ];
  static final double _e2n = 2 * math.sqrt(_n) / (1 + _n);

  @override
  Offset forward(LatLng p) {
    final phi = p.latitude * math.pi / 180;
    final dLambda = (p.longitude - centralMeridian) * math.pi / 180;
    final sinPhi = math.sin(phi);
    final t = _sinh(_atanh(sinPhi) - _e2n * _atanh(_e2n * sinPhi));
    final xi = math.atan2(t, math.cos(dLambda));
    final eta = _atanh(math.sin(dLambda) / math.sqrt(1 + t * t));
    var e = eta, nn = xi;
    for (var j = 1; j <= 3; j++) {
      e += _alpha[j - 1] * math.cos(2 * j * xi) * _sinh(2 * j * eta);
      nn += _alpha[j - 1] * math.sin(2 * j * xi) * _cosh(2 * j * eta);
    }
    return Offset(
      falseEasting + scale * _bigA * e,
      falseNorthing + scale * _bigA * nn,
    );
  }

  @override
  LatLng inverse(Offset xy) {
    final xi = (xy.dy - falseNorthing) / (scale * _bigA);
    final eta = (xy.dx - falseEasting) / (scale * _bigA);
    var xi1 = xi, eta1 = eta;
    for (var j = 1; j <= 3; j++) {
      xi1 -= _beta[j - 1] * math.sin(2 * j * xi) * _cosh(2 * j * eta);
      eta1 -= _beta[j - 1] * math.cos(2 * j * xi) * _sinh(2 * j * eta);
    }
    final chi = math.asin(math.sin(xi1) / _cosh(eta1));
    var phi = chi;
    for (var j = 1; j <= 3; j++) {
      phi += _delta[j - 1] * math.sin(2 * j * chi);
    }
    final lambda = math.atan2(_sinh(eta1), math.cos(xi1));
    return LatLng(
      phi * 180 / math.pi,
      centralMeridian + lambda * 180 / math.pi,
    );
  }
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));
