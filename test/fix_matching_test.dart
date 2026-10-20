import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/aip/aip_points.dart';
import 'package:imgmap/src/geo/georeference.dart';
import 'package:imgmap/src/geo/lat_lng.dart';
import 'package:imgmap/src/geo/projection.dart';
import 'package:imgmap/src/georef/auto_georeference.dart';
import 'package:imgmap/src/georef/fix_matching.dart';
import 'package:imgmap/src/georef/grid_labels.dart';
import 'package:imgmap/src/pdf/chart_pdf.dart';

final utm43 = TransverseMercator.utm(43);

/// A synthetic SID around Delhi in UTM 43N, rotated [deg].
Offset Function(LatLng) chart({double deg = 0.9, double mPerPx = 45}) {
  final o = utm43.forward(const LatLng(28.3, 77.0));
  final t = deg * math.pi / 180;
  return (p) {
    final m = utm43.forward(p) - o;
    final x = m.dx / mPerPx, y = -m.dy / mPerPx;
    return Offset(
      1450 + x * math.cos(t) - y * math.sin(t),
      2000 + x * math.sin(t) + y * math.cos(t),
    );
  };
}

ChartText text(String s, Offset center, {double glyph = 40}) {
  final w = glyph * 0.6;
  final left = center.dx - s.length * w / 2;
  return ChartText(s, [
    for (var i = 0; i < s.length; i++)
      Rect.fromLTWH(left + i * w, center.dy - glyph / 2, w, glyph),
  ]);
}

const fixes = {
  'PABGU': LatLng(28.5658, 77.2842),
  'DP421': LatLng(28.3393, 77.2859),
  'DAGUL': LatLng(28.2454, 77.1967),
  'DUDUM': LatLng(27.8003, 76.5225),
  'AKRIB': LatLng(27.4169, 76.7989),
  'DP645': LatLng(28.2003, 77.1003),
};

/// Draws each fix as a symbol with its label beside it, plus clutter.
({List<ChartText> texts, List<Rect> shapes}) draw(
  Offset Function(LatLng) f, {
  Map<String, Offset> shifted = const {},
}) {
  final texts = <ChartText>[];
  final shapes = <Rect>[];
  fixes.forEach((name, position) {
    final at = f(position) + (shifted[name] ?? Offset.zero);
    shapes.add(Rect.fromCenter(center: at, width: 60, height: 58));
    texts.add(text(name, at + const Offset(130, -40)));
    // A dash of a route line crossing the label: must not be taken.
    shapes.add(
      Rect.fromCenter(
        center: at + const Offset(90, -40),
        width: 40,
        height: 38,
      ),
    );
  });
  // A procedure name: not a fix label.
  texts.add(text('DUDUM 6E', const Offset(2600, 150)));
  return (texts: texts, shapes: shapes);
}

RenderedChart rendered(({List<ChartText> texts, List<Rect> shapes}) d) =>
    RenderedChart(
      Uint8List(0),
      const Size(2900, 4096),
      d.texts,
      pointsPerPixel: 0.29,
      shapes: d.shapes,
    );

PointDirectory directory() {
  final d = PointDirectory();
  fixes.forEach(d.add);
  // A far-away point with a clashing name.
  d.add('DAGUL', const LatLng(12.9, 80.1));
  return d;
}

void main() {
  test('parses waypoint lists and navaid tables', () {
    const page = '''<html><body><table>
      <tr><td>84.</td><td>PABGU</td><td>283357.00N 0771703.05E</td></tr>
      <tr><td>19.</td><td>DP421</td><td>282021.53N 0771709.26E</td></tr>
      <tr><td>AGRA</td><td>VOR/DME</td><td>AGG</td><td>112.000MHZ (57X)</td>
        <td>As Required</td><td>270926.21N 0775723.59E</td></tr>
      <tr><td>MAX 250 KIAS FL100</td><td>281139.09N 0772256.90E</td></tr>
    </table></body></html>''';
    final d = parsePointPage(page);
    expect(d['PABGU'].single.latitude, closeTo(28 + 33 / 60 + 57 / 3600, 1e-9));
    expect(d['DP421'], hasLength(1));
    expect(
      d['AGG'].single.longitude,
      closeTo(77 + 57 / 60 + 23.59 / 3600, 1e-9),
    );
    expect(d.contains('AGRA'), isFalse, reason: 'four letters: not a fix name');
    expect(d.contains('MAX'), isFalse);
    expect(d.contains('FL100'), isFalse);
  });

  test('pairs labels with their symbols, not with nearby clutter', () {
    final f = chart();
    final c = findFixCandidates(rendered(draw(f)), directory());
    final dudum = c.where((c) => c.name == 'DUDUM').toList();
    expect(dudum, hasLength(1), reason: 'procedure name skipped');
    expect((dudum.single.pixel - f(fixes['DUDUM']!)).distance, lessThan(1));
  });

  test('georeferences from named fixes and rejects a displaced one', () {
    final f = chart();
    // DUDUM drawn 300 px off, as behind a NOT TO SCALE break.
    final d = draw(f, shifted: {'DUDUM': const Offset(-300, 120)});
    final g = georeferenceFromFixes(rendered(d), directory());
    if (g is AutoGeoreferenceFailure) fail(g.reason);
    final result = g as AutoGeoreference;
    expect(result.conformal, isTrue);
    expect(
      result.points.map((p) => p.position),
      isNot(contains(fixes['DUDUM'])),
    );
    expect(result.points, hasLength(5));
    final geo = Georeference.fit(
      result.points,
      projection: result.projection,
      conformal: true,
    );
    const probe = LatLng(28.0, 76.9);
    expect((geo.toPixel(probe) - f(probe)).distance, lessThan(1));
  });

  test('a single-line grid estimate is replaced by agreeing fixes', () {
    final f = chart();
    final d = draw(f);
    final ground = 45 / utm43.scaleFactor(const LatLng(28, 77));
    final pxPerNm = 1852 / ground;
    d.texts.addAll([
      text("077°00'E", f(const LatLng(28.6, 77.0))),
      text("077°00'E", f(const LatLng(27.5, 77.0))),
      text("28°00'N", f(const LatLng(28.0, 76.4))),
      text("28°00'N", f(const LatLng(28.0, 77.4))),
      for (final v in [0, 5, 10, 15, 20, 25])
        text('$v', Offset(800 + v * pxPerNm, 3950)),
      text('NM', Offset(800 + 27 * pxPerNm, 3950)),
    ]);
    final r = autoGeoreference(rendered(d), directory());
    if (r is AutoGeoreferenceFailure) fail(r.reason);
    final g = r as AutoGeoreference;
    expect(g.method, contains('named fixes, agreeing with the grid'));
    expect(g.estimated, isFalse);
    expect(g.rmsMeters, lessThan(30));
  });

  test('a grid that disagrees with the fixes is refused', () {
    final f = chart();
    // Fixes drawn 3% too large about the chart centre: the grid says
    // otherwise.
    Offset scaled(LatLng p) {
      final px = f(p);
      return const Offset(1450, 2000) + (px - const Offset(1450, 2000)) * 1.03;
    }

    final d = draw(scaled);
    d.texts.addAll([
      for (final lon in [76.5, 76.75, 77.0, 77.25])
        for (final lat in [27.3, 28.7])
          text(
            "${lon.floor()}°${((lon % 1) * 60).round()}'0\"E",
            f(LatLng(lat, lon)),
          ),
      for (final lat in [27.5, 27.75, 28.0, 28.25, 28.5])
        for (final lon in [76.3, 77.5])
          text(
            "${lat.floor()}°${((lat % 1) * 60).round()}'0\"N",
            f(LatLng(lat, lon)),
          ),
    ]);
    expect(
      autoGeoreference(rendered(d), directory()),
      isA<AutoGeoreferenceFailure>(),
    );
  });

  test('conformal fits survive nearly collinear points', () {
    final f = chart();
    final points = [
      for (final p in const [
        LatLng(28.0, 76.80),
        LatLng(28.1, 76.95),
        LatLng(28.2, 77.10),
        LatLng(28.3, 77.2501),
      ])
        ControlPoint(pixel: f(p), position: p),
    ];
    final g = Georeference.fit(points, projection: utm43, conformal: true);
    const off = LatLng(27.6, 77.3); // far off the line
    expect((g.toPixel(off) - f(off)).distance, lessThan(1));
  });
}
