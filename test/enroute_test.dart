import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/aip/aip_registry.dart';
import 'package:imgmap/src/data/chart_store.dart';
import 'package:imgmap/src/data/storage_memory.dart';
import 'package:imgmap/src/enroute/enroute_model.dart';
import 'package:imgmap/src/location/app_location.dart';
import 'package:imgmap/src/location/location_controller.dart';
import 'package:imgmap/src/ui/country_picker.dart';
import 'package:imgmap/src/ui/enroute_screen.dart';

import 'fake_backend.dart';

void main() {
  test('reads the backend network and checks it', () {
    final data = EnrouteData.fromJson(enrouteJson());
    expect(data.routes, hasLength(2));
    expect(data.points, hasLength(3));
    expect(
      identical(
        data.routes[0].segments[0].from,
        data.routes[1].segments[0].from,
      ),
      isTrue,
      reason: 'points are shared between routes',
    );
    expect(data.routes[1].navigationSpec, 'RNAV 5');
    expect(data.routes[0].segments[1].mocaFt, 4100);
    // Only Q2's wrong length is flagged.
    expect(data.issues.single.route.designator, 'Q2');
    expect(data.issues.single.message, contains('99.0 NM'));

    final again = EnrouteData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );
    expect(again.issues, hasLength(1));
  });

  Widget app(Widget home) => MaterialApp(
    builder: (context, child) =>
        AppLocation(controller: LocationController(), child: child!),
    home: home,
  );

  testWidgets('download the network, find a route, fly it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2376);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = await ChartStore.open(storage: MemoryChartStorage());
    final india = FakeSource();
    Widget screen() => app(
      EnrouteScreen(
        store: store,
        registry: AipRegistry([india]),
        source: india,
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.textContaining('dashed red'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Q2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q2').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('SIMULATED'), findsOneWidget);
    expect(find.text('250 kt'), findsOneWidget);

    // Cached: opening again needs no download.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('choose the country and switch between them', (tester) async {
    tester.view.physicalSize = const Size(1080, 2376);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = await ChartStore.open(storage: MemoryChartStorage());
    final registry = AipRegistry([
      FakeSource(),
      FakeSource(id: 'np-caan', country: 'Nepal', countryCode: 'NP'),
    ]);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openEnrouteMap(context, store, registry),
            child: const Text('open'),
          ),
        ),
      ),
    );

    // First time, with two countries: asked which.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Country'), findsOneWidget);
    await tester.tap(find.text('Nepal'));
    await tester.pumpAndSettle();
    expect(store.enrouteSourceId, 'np-caan');
    expect(find.textContaining('AIP Nepal'), findsOneWidget);

    // Switch from the map screen itself (full name before any download).
    await tester.tap(find.text('Nepal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('India'));
    await tester.pumpAndSettle();
    expect(store.enrouteSourceId, 'in-aai');
    expect(find.textContaining('AIP India'), findsOneWidget);

    // Next time: straight to the remembered country.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Country'), findsNothing);
    expect(find.textContaining('AIP India'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
