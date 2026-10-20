import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/geo/coordinate_format.dart';

void main() {
  double lat(String s) => parseCoordinate(s, CoordAxis.latitude);
  double lon(String s) => parseCoordinate(s, CoordAxis.longitude);

  test('decimal degrees', () {
    expect(lat('28.5665'), 28.5665);
    expect(lon('-77.1031'), -77.1031);
    expect(lat('S12.5'), -12.5);
    expect(lon('77.1031 W'), -77.1031);
  });

  test('degrees and minutes / seconds', () {
    expect(lat("N28°34.0'"), closeTo(28 + 34 / 60, 1e-12));
    expect(lon('E077 06.2'), closeTo(77 + 6.2 / 60, 1e-12));
    expect(lat('''28°34'30"N'''), closeTo(28 + 34 / 60 + 30 / 3600, 1e-12));
    expect(lat('28:34:30 s'), closeTo(-(28 + 34 / 60 + 30 / 3600), 1e-12));
  });

  test('packed ICAO style', () {
    expect(lat('2834N'), closeTo(28 + 34 / 60, 1e-12));
    expect(lat('283430N'), closeTo(28 + 34 / 60 + 30 / 3600, 1e-12));
    expect(lat('283430.5N'), closeTo(28 + 34 / 60 + 30.5 / 3600, 1e-12));
    expect(lon('0770612E'), closeTo(77 + 6 / 60 + 12 / 3600, 1e-12));
    expect(lon('07706W'), closeTo(-(77 + 6 / 60), 1e-12));
  });

  test('rejects bad input', () {
    for (final bad in ['', 'abc', '91', "28°61'", '28.5 30', 'N-28', '28E']) {
      expect(() => lat(bad), throwsFormatException, reason: bad);
    }
    expect(() => lon('181'), throwsFormatException);
    expect(() => lon('77N'), throwsFormatException);
  });

  test('format round-trips through parse', () {
    for (final v in [28.5665, -0.001, 59.99999, -12.25]) {
      final s = formatCoordinate(v, CoordAxis.latitude);
      expect(lat(s), closeTo(v, 1 / 6000), reason: s);
    }
    expect(formatCoordinate(77.10333, CoordAxis.longitude), "E077°06.20'");
    expect(formatCoordinate(59.99999, CoordAxis.latitude), "N60°00.00'");
  });
}
