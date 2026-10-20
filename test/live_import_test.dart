// Imports a few charts from the live AIP India site end to end. Needs
// network and a host PDFium, so it only runs when asked:
//
//   IMGMAP_LIVE=VIDP IMGMAP_PDFIUM=/path/to/libpdfium.so \
//     flutter test test/live_import_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/aip/aip_source.dart';
import 'package:imgmap/src/aip/chart_importer.dart';
import 'package:imgmap/src/aip/countries/india.dart';
import 'package:imgmap/src/aip/eaip_country.dart';
import 'package:imgmap/src/data/chart_store.dart';
import 'package:imgmap/src/data/models.dart';
import 'package:imgmap/src/data/storage_memory.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  final icao = Platform.environment['IMGMAP_LIVE'];

  testWidgets('import charts from the live AIP', (tester) async {
    // The widget harness fakes HTTP; this test means the real thing.
    HttpOverrides.global = null;
    Pdfrx.pdfiumModulePath = Platform.environment['IMGMAP_PDFIUM'];
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    await tester.runAsync(() async {
      final source = ConfiguredEaipSource(india);
      final editions = await source.editions();
      final edition = currentEdition(editions, DateTime.now().toUtc())!;
      // ignore: avoid_print
      print(
        'Editions: ${editions.map((e) => '${e.name} ${e.effective}')}; '
        'using ${edition.name}',
      );
      final charts = await source.charts(icao!, edition);
      // ignore: avoid_print
      print('${charts.length} charts for $icao');
      final store = await ChartStore.open(storage: MemoryChartStorage());
      await store.addAirport(Airport(icao: icao));
      final importer = ChartImporter(store, source);
      final pick = [
        ...charts.where((c) => c.category == ChartCategory.approach).take(2),
        ...charts.where((c) => c.category == ChartCategory.departure).take(1),
        ...charts.where((c) => c.category == ChartCategory.arrival).take(1),
        ...charts.where((c) => c.category == ChartCategory.tabular).take(1),
      ];
      for (final c in pick) {
        final watch = Stopwatch()..start();
        final o = await importer.importChart(c);
        // ignore: avoid_print
        print(
          '${o.result.name.padRight(13)} ${c.fileName} '
          '(${watch.elapsed.inSeconds}s): ${o.detail}',
        );
      }
      for (final c in store.chartsFor(icao)) {
        // ignore: avoid_print
        print(
          'saved ${c.name}: ${c.imageSize}, ${c.controlPoints.length} pts, '
          '${c.projection.name}, geo ${c.georeference != null}',
        );
      }
      // Importing again is a no-op.
      final saved = store.usableChartsFor(icao).first.source!.fileName;
      final again = await importer.importChart(
        pick.firstWhere((c) => c.fileName == saved),
      );
      expect(again.result, ImportResult.upToDate);
    });
  }, skip: icao == null);
}
