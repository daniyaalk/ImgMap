import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/geo/georeference.dart';
import 'package:imgmap/src/geo/lat_lng.dart';

// Independent Web Mercator so expected pixels are not produced by the code
// under test.
Offset merc(LatLng p) => Offset(
  6378137.0 * p.longitude * math.pi / 180,
  6378137.0 * math.log(math.tan(math.pi / 4 + p.latitude * math.pi / 360)),
);

/// A synthetic chart around Delhi: [pxPerM] scale, rotated [deg] clockwise,
/// optional x-shear to mimic a skewed scan.
Offset Function(LatLng) chart({
  double deg = 0,
  double pxPerM = 0.05,
  double shear = 0,
}) {
  final origin = merc(const LatLng(28.56, 77.10));
  final t = deg * math.pi / 180;
  return (p) {
    final m = merc(p) - origin;
    // Image y grows downward (south).
    final x = m.dx * pxPerM, y = -m.dy * pxPerM;
    final rx = x * math.cos(t) - y * math.sin(t);
    final ry = x * math.sin(t) + y * math.cos(t);
    return Offset(2000 + rx + shear * ry, 1500 + ry);
  };
}

ControlPoint cp(Offset Function(LatLng) f, double lat, double lon) =>
    ControlPoint(pixel: f(LatLng(lat, lon)), position: LatLng(lat, lon));

void main() {
  const probe = LatLng(28.61, 77.21);

  test('two points recover a rotated chart (similarity)', () {
    final f = chart(deg: 23);
    final geo = Georeference.fit([cp(f, 28.50, 77.00), cp(f, 28.70, 77.30)]);
    expect(geo.isAffine, isFalse);
    expect((geo.toPixel(probe) - f(probe)).distance, lessThan(1e-6));
    expect(geo.rmsErrorMeters, isNull);
  });

  test('three or more points recover a skewed scan (affine)', () {
    final f = chart(deg: -8, shear: 0.04);
    final geo = Georeference.fit([
      cp(f, 28.50, 77.00),
      cp(f, 28.70, 77.30),
      cp(f, 28.45, 77.35),
      cp(f, 28.72, 76.98),
    ]);
    expect(geo.isAffine, isTrue);
    expect((geo.toPixel(probe) - f(probe)).distance, lessThan(1e-6));
    expect(geo.rmsErrorMeters, lessThan(0.01));
  });

  test('toLatLng inverts toPixel', () {
    final f = chart(deg: 40, shear: 0.1);
    final geo = Georeference.fit([
      cp(f, 28.5, 77.0),
      cp(f, 28.7, 77.3),
      cp(f, 28.4, 77.4),
    ]);
    final back = geo.toLatLng(geo.toPixel(probe));
    expect(back.distanceTo(probe), lessThan(1e-3));
  });

  test('a mistyped coordinate shows up as a large residual', () {
    final f = chart();
    final geo = Georeference.fit([
      cp(f, 28.50, 77.00),
      cp(f, 28.70, 77.30),
      cp(f, 28.45, 77.35),
      // Real position is 28.72N but entered as 28.27N.
      ControlPoint(
        pixel: f(const LatLng(28.72, 76.98)),
        position: const LatLng(28.27, 76.98),
      ),
    ]);
    expect(geo.rmsErrorMeters, greaterThan(5000));
  });

  test('north angle follows chart rotation', () {
    final f = chart(deg: 30);
    final geo = Georeference.fit([cp(f, 28.5, 77.0), cp(f, 28.7, 77.3)]);
    expect(geo.northAngleAt(probe), closeTo(30 * math.pi / 180, 1e-6));
  });

  test('rejects degenerate input', () {
    final f = chart();
    expect(
      () => Georeference.fit([cp(f, 28.5, 77.0)]),
      throwsA(isA<GeoreferenceException>()),
    );
    expect(
      () => Georeference.fit([cp(f, 28.5, 77.0), cp(f, 28.5, 77.0)]),
      throwsA(isA<GeoreferenceException>()),
    );
  });

  test('collinear points fall back to a similarity fit', () {
    final f = chart(deg: 10);
    final geo = Georeference.fit([
      cp(f, 28.5, 77.0),
      cp(f, 28.6, 77.1),
      cp(f, 28.7, 77.2),
    ]);
    expect(geo.isAffine, isFalse);
    expect((geo.toPixel(probe) - f(probe)).distance, lessThan(0.5));
  });
}
