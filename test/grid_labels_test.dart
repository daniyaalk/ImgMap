import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/geo/georeference.dart';
import 'package:imgmap/src/geo/lat_lng.dart';
import 'package:imgmap/src/geo/projection.dart';
import 'package:imgmap/src/georef/grid_labels.dart';
import 'package:imgmap/src/pdf/chart_pdf.dart';

/// A synthetic north-up-ish chart around Delhi, [deg] rotated, at
/// [mPerPx] mercator meters per pixel.
Offset Function(LatLng) chart({
  double deg = 0,
  double mPerPx = 40,
  MapProjection projection = MapProjection.webMercator,
}) {
  final o = projection.forward(const LatLng(28.5, 77.1));
  final t = deg * math.pi / 180;
  return (p) {
    final m = projection.forward(p) - o;
    final x = m.dx / mPerPx, y = -m.dy / mPerPx;
    return Offset(
      1500 + x * math.cos(t) - y * math.sin(t),
      2000 + x * math.sin(t) + y * math.cos(t),
    );
  };
}

/// Text with per-glyph boxes laid out around [center], horizontally.
ChartText text(String s, Offset center, {double glyph = 20}) {
  final w = glyph * 0.6;
  final left = center.dx - s.length * w / 2;
  return ChartText(s, [
    for (var i = 0; i < s.length; i++)
      Rect.fromLTWH(left + i * w, center.dy - glyph / 2, w, glyph),
  ]);
}

RenderedChart rendered(List<ChartText> texts, {double ppp = 0.2}) =>
    RenderedChart(
      Uint8List(0),
      const Size(3000, 4000),
      texts,
      pointsPerPixel: ppp,
    );

void main() {
  test('fits a full grid and recovers rotation', () {
    final f = chart(deg: 3);
    final texts = <ChartText>[
      for (final lon in [76.9, 77.0, 77.1, 77.2, 77.3])
        for (final lat in [28.25, 28.75]) // top and bottom edges
          text(
            "${lon.floor()}°${((lon % 1) * 60).round()}'0\"E",
            f(LatLng(lat, lon)),
          ),
      for (final lat in [28.3, 28.4, 28.5, 28.6, 28.7])
        for (final lon in [76.85, 77.35]) // left and right edges
          text(
            "${lat.floor()}°${((lat % 1) * 60).round()}'0\"N",
            f(LatLng(lat, lon)),
          ),
      // A precise position in a note, not a grid label: ignored.
      text("28°34'05\"N", const Offset(200, 200)),
    ];
    final result = georeferenceFromGridLabels(rendered(texts));
    expect(result, isA<AutoGeoreference>());
    final g = result as AutoGeoreference;
    expect(g.method, 'grid labels');
    expect(g.rmsMeters, lessThan(1));
    final geo = Georeference.fit(g.points);
    const probe = LatLng(28.55, 77.05);
    expect((geo.toPixel(probe) - f(probe)).distance, lessThan(0.5));
    expect(geo.northAngleAt(probe) * 180 / math.pi, closeTo(3, 0.01));
  });

  test('rejects a stray label that disagrees with the grid', () {
    final f = chart();
    final texts = <ChartText>[
      for (final lon in [77.0, 77.1, 77.2])
        for (final lat in [28.2, 28.8])
          text(
            "${lon.floor()}°${((lon % 1) * 60).round()}'0\"E",
            f(LatLng(lat, lon)),
          ),
      for (final lat in [28.4, 28.5, 28.6])
        for (final lon in [76.9, 77.3])
          text(
            "${lat.floor()}°${((lat % 1) * 60).round()}'0\"N",
            f(LatLng(lat, lon)),
          ),
      // Inset map labelled with a meridian that doesn't belong here.
      text("77°30'0\"E", const Offset(400, 3800)),
    ];
    final r = georeferenceFromGridLabels(rendered(texts));
    if (r is AutoGeoreferenceFailure) fail(r.reason);
    final g = r as AutoGeoreference;
    expect(g.labels, hasLength(12));
    expect(g.rmsMeters, lessThan(1));
  });

  test('labels along one edge only plus a stray label: refuses to guess', () {
    final f = chart();
    final texts = <ChartText>[
      for (final lon in [77.0, 77.1, 77.2])
        text(
          "${lon.floor()}°${((lon % 1) * 60).round()}'0\"E",
          f(LatLng(28.2, lon)),
        ),
      for (final lat in [28.4, 28.5, 28.6])
        text(
          "${lat.floor()}°${((lat % 1) * 60).round()}'0\"N",
          f(LatLng(lat, 76.9)),
        ),
      text("77°30'0\"E", const Offset(400, 3800)),
    ];
    expect(
      georeferenceFromGridLabels(rendered(texts)),
      isA<AutoGeoreferenceFailure>(),
    );
  });

  test('one meridian and parallel plus scale bar', () {
    // Drawn in UTM like AAI's charts.
    final utm = TransverseMercator.utm(43);
    final f = chart(mPerPx: 40, projection: utm);
    final ground = 40 / utm.scaleFactor(const LatLng(28, 77));
    final pxPerNm = 1852 / ground;
    final texts = <ChartText>[
      // Letter-spaced, as word processors export them.
      text("0 7 7 ° 0 0 ' E", f(const LatLng(28.75, 77.0))),
      text("0 7 7 ° 0 0 ' E", f(const LatLng(28.25, 77.0))),
      text("2 8 ° 0 0 ' N", f(const LatLng(28.0, 76.7))),
      text("2 8 ° 0 0 ' N", f(const LatLng(28.0, 77.4))),
      for (final v in [0, 5, 10, 15, 20, 25])
        text('$v', Offset(1000 + v * pxPerNm, 3900)),
      text('NM', Offset(1000 + 27 * pxPerNm, 3900)),
    ];
    final scale = chartScale(rendered(texts)) as ChartScale;
    expect(scale.metersPerPixel, closeTo(ground, 0.05));

    final g = georeferenceFromGridLabels(rendered(texts)) as AutoGeoreference;
    expect(g.method, 'grid lines + scale bar');
    final geo = Georeference.fit(g.points);
    for (final p in const [LatLng(28.0, 77.0), LatLng(28.3, 76.8)]) {
      expect((geo.toPixel(p) - f(p)).distance, lessThan(3), reason: '$p');
    }
  });

  test('uses a full grid even when parts are marked not to scale', () {
    final f = chart(deg: 2);
    final texts = <ChartText>[
      for (final lon in [77.0, 77.1, 77.2])
        for (final lat in [28.2, 28.8])
          text(
            "${lon.floor()}°${((lon % 1) * 60).round()}'0\"E",
            f(LatLng(lat, lon)),
          ),
      for (final lat in [28.4, 28.5, 28.6])
        for (final lon in [76.9, 77.3])
          text(
            "${lat.floor()}°${((lat % 1) * 60).round()}'0\"N",
            f(LatLng(lat, lon)),
          ),
      // Letter-spaced, on a leg's break symbol.
      text('N O T  T O  S C A L E', const Offset(600, 900)),
    ];
    final g = georeferenceFromGridLabels(rendered(texts)) as AutoGeoreference;
    expect(g.notToScaleAreas, hasLength(1));
    expect(g.notToScaleAreas.single.center.dx, closeTo(600, 1));
  });

  test('without a full grid, not to scale means no', () {
    final utm = TransverseMercator.utm(43);
    final f = chart(mPerPx: 40, projection: utm);
    final pxPerNm = 1852 / (40 / utm.scaleFactor(const LatLng(28, 77)));
    final texts = <ChartText>[
      text("077°00'E", f(const LatLng(28.75, 77.0))),
      text("077°00'E", f(const LatLng(28.25, 77.0))),
      text("28°00'N", f(const LatLng(28.0, 76.7))),
      text("28°00'N", f(const LatLng(28.0, 77.4))),
      for (final v in [0, 5, 10, 15])
        text('$v', Offset(1000 + v * pxPerNm, 3900)),
      text('NM', Offset(1000 + 17 * pxPerNm, 3900)),
      text('NOT TO SCALE', const Offset(600, 900)),
    ];
    expect(
      georeferenceFromGridLabels(rendered(texts)),
      isA<AutoGeoreferenceFailure>(),
    );
  });

  test('refuses charts marked not to scale', () {
    final texts = [text('NOT TO SCALE', const Offset(100, 100))];
    expect(
      georeferenceFromGridLabels(rendered(texts)),
      isA<AutoGeoreferenceFailure>(),
    );
  });

  test('a scale bar that disagrees with the printed scale blocks the fit', () {
    final texts = <ChartText>[
      for (final v in [0, 5, 10]) text('$v', Offset(1000 + v * 100, 3900)),
      text('NM', const Offset(2200, 3900)),
      text('SCALE 1:200,000', const Offset(1500, 3800)),
    ];
    expect(chartScale(rendered(texts)), isA<AutoGeoreferenceFailure>());
  });

  test('reads printed scales', () {
    expect(printedScale('SCALE:1:450,000'), 450000);
    expect(printedScale('xxSCALE1:500000yy'), 500000);
    expect(printedScale('nothing'), isNull);
    // A neighbouring number must not run into the figure.
    expect(printedScale('SCALE:1:500,0000'), isNull);
    expect(
      printedScaleOf([
        text('SCALE', Offset.zero),
        text('1:250,000', Offset.zero),
      ]),
      250000,
    );
  });
}
