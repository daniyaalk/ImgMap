// Runs auto-georeferencing on real AIP chart PDFs. AIP charts are
// copyrighted, so none are in the repo; point the test at a folder:
//
//   IMGMAP_CHART_DIR=/path/to/pdfs IMGMAP_PDFIUM=/path/to/libpdfium.so \
//     flutter test test/real_charts_test.dart
//
// libpdfium.so for the host comes from github.com/bblanchon/pdfium-binaries
// (the release pdfrx bundles).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/src/aip/aip_points.dart';
import 'package:imgmap/src/geo/coordinate_format.dart';
import 'package:imgmap/src/geo/georeference.dart';
import 'package:imgmap/src/geo/lat_lng.dart';
import 'package:imgmap/src/georef/auto_georeference.dart';
import 'package:imgmap/src/georef/fix_matching.dart';
import 'package:imgmap/src/georef/grid_labels.dart';
import 'package:imgmap/src/pdf/pdf_shapes_native.dart';
import 'package:imgmap/src/pdf/chart_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  final dir = Platform.environment['IMGMAP_CHART_DIR'];

  test('auto-georeference real charts', () async {
    Pdfrx.pdfiumModulePath = Platform.environment['IMGMAP_PDFIUM'];
    await pdfrxInitialize();
    final files =
        Directory(dir!)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    // Optional: a folder of saved eAIP pages (ENR 4.4, ENR 4.1, AD 2) to
    // match named fixes against.
    final points = PointDirectory();
    final pointDir = Platform.environment['IMGMAP_POINTS'];
    if (pointDir != null) {
      for (final p in Directory(pointDir).listSync().whereType<File>()) {
        points.addAll(parsePointPage(p.readAsStringSync()));
      }
      // ignore: avoid_print
      print('${points.length} named points');
    }
    for (final f in files) {
      final doc = await PdfDocument.openFile(f.path);
      final page = doc.pages.first;
      final scale =
          4096 / (page.width > page.height ? page.width : page.height);
      final size = Size(page.width * scale, page.height * scale);
      final raw = (await page.loadText())!;
      final texts = groupText(raw.fullText, [
        for (final r in raw.charRects)
          r.toRect(page: page, scaledPageSize: size),
      ]);
      final shapes = await pageShapes(doc, page, size);
      final chart = RenderedChart(
        Uint8List(0),
        size,
        texts,
        pointsPerPixel: 1 / scale,
        shapes: shapes,
      );
      final labels = findGridLabels(texts);
      final result = autoGeoreference(chart, points);
      final candidates = findFixCandidates(chart, points);
      if (Platform.environment['IMGMAP_DUMP'] != null &&
          result is AutoGeoreference) {
        final g = Georeference.fit(
          result.points,
          projection: result.projection,
        );
        for (final c in candidates) {
          for (final p in c.positions) {
            // ignore: avoid_print
            print(
              'DUMP ${c.name} sym=${c.pixel.dx.round()},${c.pixel.dy.round()} '
              'label=${c.label.center.dx.round()},${c.label.center.dy.round()} '
              'aip=${g.toPixel(p).dx.round()},${g.toPixel(p).dy.round()}',
            );
          }
        }
      }
      final fixOnly = georeferenceFromFixes(chart, points);
      // ignore: avoid_print
      print(
        '    fixes: ${fixOnly is AutoGeoreferenceFailure ? fixOnly.reason : (fixOnly as AutoGeoreference).method}',
      );
      final name =
          '${f.uri.pathSegments.last} '
          '[${shapes.length} shapes, ${candidates.length} fix labels: '
          '${candidates.map((c) => c.name).toSet().take(12).join(' ')}]';
      // ignore: avoid_print
      print(
        '$name: ${labels.length} labels '
        '(${labels.where((l) => l.axis == CoordAxis.latitude).length} lat); '
        'scale 1:${printedScaleOf(texts)}',
      );
      if (result is AutoGeoreference) {
        // ignore: avoid_print
        print(
          '  OK ${result.method}, ${result.projection.name}, '
          '±${result.rmsMeters.toStringAsFixed(1)} m, '
          '${result.points.length} crossings, '
          'scale ratio ${result.scaleRatio?.toStringAsFixed(3)}, '
          '${result.notToScaleAreas.length} not-to-scale marks',
        );
        final geo = Georeference.fit(
          result.points,
          projection: result.projection,
        );
        for (final check
            in (Platform.environment['IMGMAP_CHECK'] ?? '')
                .split(';')
                .where((c) => c.contains('='))) {
          final [name, coords] = check.split('=');
          final [lat, lon] = coords.split(',').map(double.parse).toList();
          // ignore: avoid_print
          print('    $name -> ${geo.toPixel(LatLng(lat, lon))}');
        }
        for (final p in result.points.take(3)) {
          // ignore: avoid_print
          print('    ${p.position} @ ${p.pixel}');
        }
      } else {
        // ignore: avoid_print
        print('  FAIL ${(result as AutoGeoreferenceFailure).reason}');
        for (final l in labels.take(16)) {
          // ignore: avoid_print
          print('    "${l.text}" ${l.center}');
        }
      }
      await doc.dispose();
    }
  }, skip: dir == null ? 'set IMGMAP_CHART_DIR' : false);
}
