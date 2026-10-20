import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/data/chart_store.dart';
import 'package:imgmap/src/data/models.dart';
import 'package:imgmap/src/data/storage_io.dart';
import 'package:imgmap/src/geo/georeference.dart';
import 'package:imgmap/src/geo/lat_lng.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('imgmap'));
  tearDown(() => dir.delete(recursive: true));

  ChartRecord chart(ChartStore store, String file) => ChartRecord(
    id: store.newChartId(),
    airportIcao: 'VIDP',
    name: 'STAR 28',
    imageFile: file,
    imageSize: const Size(1000, 800),
    controlPoints: const [
      ControlPoint(pixel: Offset(10, 20), position: LatLng(28.5, 77.0)),
      ControlPoint(pixel: Offset(900, 700), position: LatLng(28.3, 77.4)),
    ],
  );

  Future<String> fakeImage(ChartStore store, String name) async {
    await File('${dir.path}/charts/$name')
        .create(recursive: true)
        .then((f) => f.writeAsBytes([1, 2, 3]));
    return name;
  }

  test('persists airports and charts across reopen', () async {
    var store = await ChartStore.open(storage: FileChartStorage(dir));
    await store.addAirport(const Airport(icao: 'VIDP', name: 'Delhi'));
    final c = chart(store, await fakeImage(store, 'a.png'));
    await store.saveChart(c);

    store = await ChartStore.open(storage: FileChartStorage(dir));
    expect(store.airports.single.name, 'Delhi');
    final loaded = store.chartsFor('VIDP').single;
    expect(loaded.id, c.id);
    expect(loaded.imageSize, const Size(1000, 800));
    expect(loaded.controlPoints[1].pixel, const Offset(900, 700));
    expect(loaded.georeference, isNotNull);
  });

  test('rejects duplicate airports', () async {
    final store = await ChartStore.open(storage: FileChartStorage(dir));
    await store.addAirport(const Airport(icao: 'VIDP'));
    expect(
      () => store.addAirport(const Airport(icao: 'VIDP')),
      throwsStateError,
    );
  });

  test('deleting an airport removes its charts and images', () async {
    final store = await ChartStore.open(storage: FileChartStorage(dir));
    await store.addAirport(const Airport(icao: 'VIDP'));
    final file = await fakeImage(store, 'a.png');
    await store.saveChart(chart(store, file));

    await store.deleteAirport('VIDP');
    expect(store.airports, isEmpty);
    expect(await File('${dir.path}/charts/$file').exists(), isFalse);
  });

  test('unsaved imports are cleaned up on next open', () async {
    var store = await ChartStore.open(storage: FileChartStorage(dir));
    await store.addAirport(const Airport(icao: 'VIDP'));
    final kept = await fakeImage(store, 'kept.png');
    await store.saveChart(chart(store, kept));
    final orphan = await fakeImage(store, 'orphan.png');

    store = await ChartStore.open(storage: FileChartStorage(dir));
    expect(await File('${dir.path}/charts/$kept').exists(), isTrue);
    expect(await File('${dir.path}/charts/$orphan').exists(), isFalse);
  });

  test('lists only georeferenced charts', () async {
    final store = await ChartStore.open(storage: FileChartStorage(dir));
    await store.addAirport(const Airport(icao: 'VIDP'));
    final good = chart(store, await fakeImage(store, 'good.png'));
    await store.saveChart(good);
    await store.saveChart(
      chart(
        store,
        await fakeImage(store, 'bad.png'),
      ).copyWith(controlPoints: const []),
    );
    expect(store.chartsFor('VIDP'), hasLength(2));
    expect(store.usableChartsFor('VIDP').map((c) => c.id), [good.id]);
  });

  test('remembers charts that could not be georeferenced', () async {
    var store = await ChartStore.open(storage: FileChartStorage(dir));
    await store.addAirport(const Airport(icao: 'VIDP'));
    await store.markUnusable('in-aai', 'VIDP', '2026-09', 'VIDP-ADC.pdf');

    store = await ChartStore.open(storage: FileChartStorage(dir));
    expect(store.unusableCharts('in-aai', 'VIDP', '2026-09'), {'VIDP-ADC.pdf'});
    // A new edition is tried afresh.
    expect(store.unusableCharts('in-aai', 'VIDP', '2026-10'), isEmpty);

    await store.deleteAirport('VIDP');
    expect(store.unusableCharts('in-aai', 'VIDP', '2026-09'), isEmpty);
  });
}
