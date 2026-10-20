import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:imgmap/src/aip/aip_points.dart';
import 'package:imgmap/src/aip/aip_registry.dart';
import 'package:imgmap/src/aip/aip_source.dart';
import 'package:imgmap/src/data/chart_store.dart';
import 'package:imgmap/src/data/storage_memory.dart';
import 'package:imgmap/src/enroute/enroute_loader.dart';
import 'package:imgmap/src/enroute/enroute_model.dart';
import 'package:imgmap/src/enroute/route_parser.dart';
import 'package:imgmap/src/geo/lat_lng.dart';
import 'package:imgmap/src/ui/country_picker.dart';
import 'package:imgmap/src/ui/enroute_screen.dart';

/// An eAIP ENR 3.x page: header row, then point and leg rows.
String routePage(String header, List<(String, String, String?)> rows) {
  final b = StringBuffer('<html><body><table>');
  b.write("<tr><td></td><td>$header</td></tr>");
  for (final (marker, point, leg) in rows) {
    b.write(
      '<tr><td>$marker</td><td>$point</td><td></td><td></td><td></td>'
      '<td></td><td></td><td></td></tr>',
    );
    if (leg != null) b.write(leg);
  }
  return '$b</table></body></html>';
}

String leg(
  String trackDistance, {
  String limits = 'FL 460 FL 75 Class D 3200 FT',
}) =>
    '<tr><td></td><td></td><td>$trackDistance</td><td>$limits</td>'
    '<td>20 NM</td><td></td><td>&#8595;</td><td></td></tr>';

final edition = AipEdition(
  id: '2026-09',
  name: 'AMDT 09/2026',
  effective: DateTime.utc(2026, 10, 1),
  baseUrl: Uri.parse('https://example.test/'),
);

// A474's first legs as published, with an amendment on the second.
final a474 = routePage('A474 (DPN-MURUS)', [
  ('p', 'DELHI DVOR DVOR/DME (DPN) 283401N 0770537E', leg('213/- 55.0 NM')),
  (
    'p',
    'DUDUM 274801N 0763121E',
    leg(
      "<del class='AmdtDeletedAIRAC'>214</del>"
      "<ins class='AmdtInsertedAIRAC'>213</ins>/- "
      "<del class='AmdtDeletedAIRAC'>21</del>"
      "<ins class='AmdtInsertedAIRAC'>20</ins>.0 NM",
      limits: 'FL 460 FL 75 Class D 4100 FT',
    ),
  ),
  (
    'c',
    "IGOLU <del class='AmdtDeletedAIRAC'>273000N </del>"
        "<ins class='AmdtInsertedAIRAC'>273123N </ins>0761850E",
    null,
  ),
]);

final q2 = routePage('Q2 (RNAV 5) (DPN-BBB)', [
  ('p', 'DELHI DVOR DVOR/DME (DPN) 283401N 0770537E', leg('213/- 55.0 NM')),
  // Published length deliberately wrong: 99 NM where the points are 55.
  ('p', 'DUDUM 274801N 0763121E', leg('213/- 99.0 NM')),
  ('p', 'IGOLU 273123N 0761850E', null),
]);

void main() {
  test('reads only the amended text, and keeps numbers whole', () {
    final cell = html
        .parse(
          "<td><del class='AmdtDeletedAIRAC'>93</del>"
          "<ins class='AmdtInsertedAIRAC'>94</ins>.6 NM</td>",
        )
        .body!;
    expect(nodeText(cell), '94.6 NM');
  });

  test('parses a route page', () {
    final r = parseRoutePage(a474).single;
    expect(r.designator, 'A474');
    expect(r.navigationSpec, isNull);
    expect(r.points.map((p) => p.ident ?? p.name), ['DPN', 'DUDUM', 'IGOLU']);
    expect(r.points.first.kind, PointKind.navaid);
    expect(r.points.last.compulsory, isFalse);
    // The amended position, not the deleted one.
    expect(
      r.points.last.position.latitude,
      closeTo(27 + 31 / 60 + 23 / 3600, 1e-9),
    );
    expect(r.legs[1].trackMagnetic, 213);
    expect(r.legs[1].distanceNm, 20.0);
    expect(r.legs[1].upper, 'FL 460');
    expect(r.legs[1].lower, 'FL 75');
    expect(r.legs[1].airspaceClass, 'D');
    expect(r.legs[1].mocaFt, 4100);
    expect(r.legs[1].widthNm, 20);
    expect(parseRoutePage(q2).single.navigationSpec, 'RNAV 5');
  });

  test('links routes into a network and checks it', () {
    final data = EnrouteLoader.build('in-aai', edition, [
      ...parseRoutePage(a474),
      ...parseRoutePage(q2),
    ], const []);
    expect(data.routes, hasLength(2));
    expect(data.points, hasLength(3), reason: 'shared by both routes');
    expect(
      identical(
        data.routes[0].segments[0].from,
        data.routes[1].segments[0].from,
      ),
      isTrue,
    );
    // Only Q2's wrong length is flagged.
    expect(data.issues.single.route.designator, 'Q2');
    expect(data.issues.single.message, contains('99.0 NM'));

    final again = EnrouteData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );
    expect(again.routes[1].navigationSpec, 'RNAV 5');
    expect(again.routes[0].segments[1].mocaFt, 4100);
    expect(again.points, hasLength(3));
    expect(again.issues, hasLength(1));
  });

  testWidgets('download the network, find a route, fly it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2376);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = await ChartStore.open(storage: MemoryChartStorage());
    final india = _FakeSource();
    Widget screen() => MaterialApp(
      home: EnrouteScreen(
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
      _FakeSource(),
      _FakeSource(id: 'np-caan', country: 'Nepal', countryCode: 'NP'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
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

class _FakeSource implements AipSource {
  _FakeSource({
    this.id = 'in-aai',
    this.country = 'India',
    this.countryCode = 'IN',
  });

  @override
  final String id;
  @override
  final String country;
  @override
  final String countryCode;
  @override
  String get displayName => 'AIP $country';
  @override
  LatLng get mapCenter => const LatLng(22, 80);
  @override
  bool covers(String icao) => true;
  @override
  Future<List<AipEdition>> editions() async => [edition];
  @override
  Future<List<ChartRef>> charts(String icao, AipEdition e) async => [];
  @override
  Future<Uint8List> download(ChartRef c) async => Uint8List(0);
  @override
  Future<PointDirectory> points(String icao, AipEdition e) async =>
      PointDirectory();
  @override
  Future<List<String>> routePages(AipEdition e) async => ['A474', 'Q2'];
  @override
  Future<String> page(AipEdition e, String name) async =>
      name == 'A474' ? a474 : q2;
}
