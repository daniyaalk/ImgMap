import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imgmap/src/aip/aip_registry.dart';
import 'package:imgmap/src/aip/aip_source.dart';
import 'package:imgmap/src/aip/backend.dart';
import 'package:imgmap/src/aip/chart_importer.dart';
import 'package:imgmap/src/data/chart_store.dart';
import 'package:imgmap/src/data/models.dart';
import 'package:imgmap/src/data/storage_memory.dart';
import 'package:imgmap/src/geo/footprint.dart';
import 'package:imgmap/src/geo/georeference.dart';
import 'package:imgmap/src/geo/lat_lng.dart';
import 'package:imgmap/src/location/app_location.dart';
import 'package:imgmap/src/location/location_controller.dart';
import 'package:imgmap/src/ui/charts_screen.dart';

import 'fake_backend.dart';

final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 a chart'));
final pdfSha = sha256.convert(pdf).toString();

Map<String, dynamic> georefJson({
  int revision = 1,
  String projection = 'utm43n',
}) => {
  'revision': revision,
  'algorithm': 6,
  'method': 'grid labels',
  'projection': projection,
  'conformal': false,
  'accuracyM': 14.0,
  'estimated': false,
  'points': [
    {'u': 0.1, 'v': 0.1, 'lat': 28.8, 'lon': 76.9},
    {'u': 0.9, 'v': 0.1, 'lat': 28.8, 'lon': 77.4},
    {'u': 0.1, 'v': 0.9, 'lat': 28.2, 'lon': 76.9},
    {'u': 0.9, 'v': 0.9, 'lat': 28.2, 'lon': 77.4},
  ],
  'footprint': [
    [28.9, 76.8],
    [28.9, 77.5],
    [28.1, 77.5],
    [28.1, 76.8],
  ],
  'notToScale': [
    [0.4, 0.4, 0.5, 0.45],
  ],
  // From a newer backend: ignored.
  'confidence': 0.97,
};

/// The backend's files, as served.
Map<String, Object> files({int revision = 1}) => {
  'v1/countries.json': {
    'schema': 1,
    'countries': [
      {
        'id': 'in-aai',
        'country': 'India',
        'countryCode': 'IN',
        'authority': 'AAI',
        'icaoPrefixes': ['VA', 'VE', 'VI', 'VO'],
        'mapCenter': {'lat': 22, 'lon': 80},
        'flagColour': 'saffron', // unknown field
      },
    ],
  },
  'v1/in-aai/editions.json': {
    'schema': 1,
    'editions': [
      {'id': '2026-09', 'name': 'AMDT 09/2026', 'effective': '2026-10-01'},
    ],
  },
  'v1/in-aai/2026-09/ad/VIDP.json': {
    'schema': 1,
    'charts': [
      {
        'file': 'VIDP-ILS-LOC-RWY-27.pdf',
        'title': 'ILS LOC RWY 27',
        'category': 'approach',
        'pdf': {
          'path': 'pdf/$pdfSha.pdf',
          'sha256': pdfSha,
          'bytes': pdf.length,
        },
        'page': {'width': 595.5, 'height': 842.26, 'rotation': 0},
        'georef': georefJson(revision: revision),
      },
      {
        'file': 'VIDP-FUTURE.pdf',
        'title': 'Lambert chart',
        'category': 'approach',
        'pdf': {'path': 'pdf/x.pdf', 'sha256': 'x', 'bytes': 1},
        // A projection this app version doesn't know.
        'georef': georefJson(projection: 'lcc28_32'),
      },
      {
        'file': 'VIDP-HELI.pdf',
        'title': 'Helipad chart',
        'category': 'helipad', // a category this version doesn't know
        'pdf': {'path': 'pdf/y.pdf', 'sha256': 'y', 'bytes': 1},
        'georef': georefJson(),
      },
      {
        'file': 'VIDP-TORA-RWY-09.pdf',
        'title': 'TORA RWY 09',
        'category': 'tabular',
        'unusable': 'Table, not a map.',
      },
    ],
  },
  'pdf/$pdfSha.pdf': pdf,
};

Backend backendFor(Map<String, Object> served) => Backend(
  base: Uri.parse('https://data.example/'),
  client: MockClient((req) async {
    final body = served[req.url.path.substring(1)];
    if (body == null) return http.Response('not found', 404);
    return body is Uint8List
        ? http.Response.bytes(body, 200)
        : http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  }),
);

void main() {
  test(
    'reads countries, editions and charts; skips what it does not know',
    () async {
      final backend = backendFor(files());
      final source = (await backend.countries()).single;
      expect(source.country, 'India');
      expect(source.covers('VIDP'), isTrue);
      expect(source.covers('OPKC'), isFalse);
      final edition = (await source.editions()).single;
      final charts = await source.charts('VIDP', edition);
      expect(charts.map((c) => c.usable), [true, false, false, false]);
      final g = charts.first.georef!;
      expect(g.projectionId, 'utm43n');
      expect(g.points.first.u, 0.1);
      expect(g.footprint, hasLength(4));
      expect(g.notToScale.single, const Rect.fromLTRB(0.4, 0.4, 0.5, 0.45));
      expect(charts.last.unusableReason, 'Table, not a map.');
      // An airport with no charts published.
      expect(await source.charts('VOBL', edition), isEmpty);
    },
  );

  test('checks downloaded PDFs against their hash', () async {
    final backend = backendFor(files());
    final source = (await backend.countries()).single;
    final edition = (await source.editions()).single;
    final chart = (await source.charts('VIDP', edition)).first;
    expect(await source.download(chart), pdf);

    final damaged = backendFor({...files(), 'pdf/$pdfSha.pdf': Uint8List(3)});
    final s2 = (await damaged.countries()).single;
    final c2 = (await s2.charts('VIDP', edition)).first;
    await expectLater(s2.download(c2), throwsA(isA<AipException>()));
  });

  test('the country list is cached for offline use', () async {
    final storage = MemoryChartStorage();
    final online = await AipRegistry.load(backendFor(files()), storage);
    await online.refresh();
    expect(online.sources.single.id, 'in-aai');
    final offline = await AipRegistry.load(backendFor({}), storage);
    expect(offline.sources.single.country, 'India');
  });

  test('backend points land at page fractions of the stored image', () {
    final g = ChartGeoref.fromJson(georefJson())!;
    final points = controlPointsFor(g, const Size(2000, 3000));
    expect(points.first.pixel, const Offset(200, 300));
    expect(points.last.pixel, const Offset(1800, 2700));
  });

  /// A chart imported from the backend. In a widget test, [realAsync] runs
  /// the one step that needs real time: decoding the image.
  Future<(ChartStore, ChartRecord, FakeSource, ChartImporter)> imported({
    Future<ImportedImage?> Function(Future<ImportedImage> Function())?
    realAsync,
  }) async {
    final store = await ChartStore.open(storage: MemoryChartStorage());
    await store.addAirport(const Airport(icao: 'VIDP'));
    final source = FakeSource(id: 'in-aai');
    final importer = ChartImporter(store, source);
    final ref = (await (await backendFor(
      files(),
    ).countries()).single.charts('VIDP', edition)).first;
    final image = realAsync == null
        ? await store.importImage(_png, 'png')
        : (await realAsync(() => store.importImage(_png, 'png')))!;
    final record = importer.recordFor(
      ref,
      ref.georef!,
      id: store.newChartId(),
      imageFile: image.fileName,
      imageSize: const Size(2000, 3000),
    );
    await store.saveChart(record);
    return (store, record, source, importer);
  }

  test('a higher georef revision replaces automatic points', () async {
    final (store, record, source, importer) = await imported();
    // The backend improved the chart: revision 2, a point moved.
    final improved = (await (await backendFor(
      files(revision: 2),
    ).countries()).single.charts('VIDP', edition)).first;
    source.chartList = [improved];
    expect(await importer.refreshGeoreferences('VIDP'), 1);
    final updated = store.chart(record.id)!;
    expect(updated.source!.georefRevision, 2);

    // Nothing newer: nothing to do.
    expect(await importer.refreshGeoreferences('VIDP'), 0);
  });

  test('hand-placed points are never replaced', () async {
    final (store, record, source, importer) = await imported();
    await store.saveChart(record.copyWith(clearAuto: true));
    source.chartList = [
      (await (await backendFor(
        files(revision: 2),
      ).countries()).single.charts('VIDP', edition)).first,
    ];
    expect(await importer.refreshGeoreferences('VIDP'), 0);
    expect(store.chart(record.id)!.source!.georefRevision, 1);
  });

  test('footprints and containment', () async {
    final (_, record, _, _) = await imported();
    final footprint = chartFootprint(record)!;
    expect(polygonContains(footprint, const LatLng(28.5, 77.1)), isTrue);
    expect(polygonContains(footprint, const LatLng(26.9, 75.8)), isFalse);
  });

  testWidgets('charts covering the GPS position are marked and listed first', (
    tester,
  ) async {
    final (store, record, _, _) = await imported(
      realAsync: (f) => tester.runAsync(f),
    );
    await store.saveChart(
      ChartRecord(
        id: 'far',
        airportIcao: 'VIDP',
        name: 'Far away chart',
        imageFile: record.imageFile,
        imageSize: record.imageSize,
        controlPoints: [
          for (final p in record.controlPoints)
            ControlPoint(
              pixel: p.pixel,
              position: LatLng(p.position.latitude - 3, p.position.longitude),
            ),
        ],
      ),
    );
    final location = LocationController();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppLocation(controller: location, child: child!),
        home: ChartsScreen(store: store, registry: AipRegistry(), icao: 'VIDP'),
      ),
    );
    await tester.pump();
    expect(find.text('Covers your position'), findsNothing);

    location.debugSetPosition(_fix(28.5, 77.1));
    await tester.pump();
    expect(find.text('Covers your position'), findsOneWidget);
    expect(
      find.textContaining('Your position is on this chart'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.my_location), findsOneWidget);
    // Listed first.
    expect(
      tester.getTopLeft(find.text('ILS LOC RWY 27')).dy,
      lessThan(tester.getTopLeft(find.text('Far away chart')).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });
}

Position _fix(double lat, double lon) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 200,
  altitudeAccuracy: 5,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

// A 1×1 PNG, enough for the store to import.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
