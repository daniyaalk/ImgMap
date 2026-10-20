import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/geo/lat_lng.dart';
import 'package:imgmap/src/geo/projection.dart';

void main() {
  test('UTM matches known values', () {
    final zone31 = TransverseMercator.utm(31);
    // On the central meridian, northing is 0.9996 × the meridian arc
    // (4,984,944.4 m from the equator to 45°N on WGS-84).
    final p = zone31.forward(const LatLng(45, 3));
    expect(p.dx, closeTo(500000, 0.01));
    expect(p.dy, closeTo(4982950.4, 0.5));
    expect(zone31.forward(const LatLng(0, 3)).dy, closeTo(0, 1e-6));
    expect(TransverseMercator.utmZone(77.1), 43);
    expect(TransverseMercator.utm(43).centralMeridian, 75);
  });

  test('projections round-trip within their zones', () {
    final cases = {
      MapProjection.webMercator: const [
        LatLng(28.5665, 77.1031),
        LatLng(-23.4, -46.5),
      ],
      TransverseMercator.utm(43): const [
        LatLng(28.5665, 77.1031),
        LatLng(12.95, 77.67),
        LatLng(34.0, 72.1),
      ],
      TransverseMercator.utm(23, north: false): const [LatLng(-23.4, -46.5)],
    };
    cases.forEach((proj, points) {
      for (final p in points) {
        final back = proj.inverse(proj.forward(p));
        expect(back.distanceTo(p), lessThan(0.001), reason: '${proj.id} $p');
      }
    });
  });

  test('ids survive storage', () {
    expect(MapProjection.fromId('utm43n').name, 'UTM zone 43N');
    expect(MapProjection.fromId('merc'), same(MapProjection.webMercator));
    expect(MapProjection.fromId(null), same(MapProjection.webMercator));
  });
}
