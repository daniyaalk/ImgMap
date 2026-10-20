import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/main.dart';
import 'package:imgmap/src/data/chart_store.dart';
import 'package:imgmap/src/data/storage_memory.dart';
import 'package:imgmap/src/ui/chart_viewport.dart';

/// Pixel position of a lat/lon on assets/demo_chart.png; mirrors
/// tool/make_demo_chart.py.
Offset demoPixel(double lat, double lon) {
  const w = 2400.0, h = 1800.0, rot = 8 * math.pi / 180;
  Offset merc(double lat, double lon) => Offset(
    6378137.0 * lon * math.pi / 180,
    6378137.0 * math.log(math.tan(math.pi / 4 + lat * math.pi / 360)),
  );
  final c = merc((28.40 + 28.75) / 2, (76.90 + 77.30) / 2);
  final scale = 0.80 * w / (merc(28.40, 77.30).dx - merc(28.40, 76.90).dx);
  final m = merc(lat, lon);
  final dx = (m.dx - c.dx) * scale, dy = -(m.dy - c.dy) * scale;
  return Offset(
    w / 2 + dx * math.cos(rot) - dy * math.sin(rot),
    h / 2 + dx * math.sin(rot) + dy * math.cos(rot),
  );
}

void main() {
  testWidgets('demo: georeference a chart, then fly it in the simulator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Memory storage does no real I/O, so it can run in the fake-async zone.
    final store = await ChartStore.open(storage: MemoryChartStorage());
    await tester.pumpWidget(ImgMapApp(store: store));

    // Lets real async work (image decoding) finish, then settles frames.
    Future<void> settle([int ms = 300]) async {
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: ms)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.tap(find.text('Try the demo'));
    await tester.pumpAndSettle();
    expect(find.text('VIDP'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add demo chart'));
    await settle(800);
    expect(find.text('Georeference chart'), findsOneWidget);

    ChartViewController view() =>
        tester
                .widget<InteractiveViewer>(find.byType(InteractiveViewer))
                .transformationController!
            as ChartViewController;
    Offset screenOf(Offset pixel) =>
        tester.getTopLeft(find.byType(InteractiveViewer)) +
        view().toScreen(pixel);

    // ALPHA, BRAVO, CHARL, DELTA as printed on the chart.
    const fixes = [
      (28.6833, 76.9667, "N28°41.00'", "E076°58.00'"),
      (28.7000, 77.2500, "N28°42.00'", "E077°15.00'"),
      (28.4500, 77.2333, '282700N', '0771400E'),
      (28.4667, 76.9500, '28 28 N', '76.95'),
    ];
    for (final (lat, lon, latText, lonText) in fixes) {
      await tester.tapAt(screenOf(demoPixel(lat, lon)));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), latText);
      await tester.enterText(fields.at(1), lonText);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    // Printed coordinates are rounded to 0.01', so expect a few meters.
    expect(find.textContaining('Accuracy ±'), findsOneWidget);
    await settle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = store.chartsFor('VIDP').single;
    expect(saved.controlPoints, hasLength(4));
    final geo = saved.georeference!;
    expect(geo.isAffine, isTrue);
    expect(geo.rmsErrorMeters, lessThan(20));
    // The chart is rotated 8° clockwise, so north points 8° right of up.
    expect(
      geo.northAngleAt(saved.controlPoints.first.position) * 180 / math.pi,
      closeTo(8, 0.1),
    );

    await tester.tap(find.text('Demo chart'));
    await settle();
    await settle(1000);
    // No location plugin in tests: the app must degrade, not crash.
    expect(find.textContaining('Location is not available'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump(const Duration(milliseconds: 600));
    // The test screen is landscape: no app bar, floating controls and a
    // side column of flight data.
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.textContaining('SIM'), findsOneWidget);
    expect(find.text('120 kt'), findsOneWidget);
    expect(find.text('3000 ft'), findsOneWidget);
    // The loop starts just past the chart's right edge.
    expect(find.textContaining('Off chart'), findsOneWidget);

    // A quarter lap later the aircraft is over the chart and followed.
    await tester.pump(const Duration(seconds: 20));
    await settle();
    expect(find.textContaining('Off chart'), findsNothing);
    final v = view();
    // Following keeps the user's zoom (initially fit-to-screen).
    expect(v.scale, closeTo(v.fitScale, 0.05));
    final centre = v.toImage(v.viewportSize.center(Offset.zero));
    final heading = find.textContaining('°').evaluate().length;
    expect(heading, greaterThan(0));
    expect(
      (centre - const Offset(1200, 900 + 1800 * 0.32)).distance,
      lessThan(60),
    );

    // Rotated to portrait mid-flight: app bar and bottom bar return, and
    // the flight carries on.
    tester.view.physicalSize = const Size(900, 1280);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('SIMULATED'), findsOneWidget);
    expect(find.text('120 kt'), findsOneWidget);

    // Leaving the screen must stop the simulated feed's timer.
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
