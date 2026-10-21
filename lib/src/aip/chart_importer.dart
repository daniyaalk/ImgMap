import 'dart:ui';

import '../data/chart_store.dart';
import '../data/models.dart';
import '../geo/georeference.dart';
import '../pdf/chart_pdf.dart';
import 'aip_source.dart';

enum ImportResult {
  /// Saved, with the backend's control points.
  georeferenced,

  /// Not saved: the backend couldn't georeference it (a table, no grid,
  /// not to scale).
  unusable,

  /// Already have this edition of the chart.
  upToDate,
  failed,
}

class ImportOutcome {
  const ImportOutcome(this.chart, this.result, this.detail);
  final ChartRef chart;
  final ImportResult result;
  final String detail;
}

/// Downloads charts from the backend and saves them with the control
/// points it worked out, replacing older editions of the same chart.
class ChartImporter {
  ChartImporter(this.store, this.source);

  final ChartStore store;
  final AipSource source;

  ImportOutcome? alreadyHave(ChartRef ref) {
    final existing = store.chartFromSource(source.id, ref.icao, ref.fileName);
    final s = existing?.source;
    if (s != null &&
        s.editionId == ref.edition.id &&
        s.sha256 == ref.sha256 &&
        existing!.georeference != null) {
      return ImportOutcome(ref, ImportResult.upToDate, 'Already up to date.');
    }
    return null;
  }

  Future<ImportOutcome> importChart(ChartRef ref) async {
    final have = alreadyHave(ref);
    if (have != null) return have;
    final previous = store.chartFromSource(source.id, ref.icao, ref.fileName);
    final georef = ref.georef;
    if (!ref.usable || georef == null) {
      // A superseded copy shouldn't linger as if current.
      if (previous != null) await store.deleteChart(previous.id);
      return ImportOutcome(
        ref,
        ImportResult.unusable,
        ref.unusableReason ?? 'Not usable as a moving map.',
      );
    }

    final ImportedImage image;
    try {
      final rendered = await renderChartPdf(await source.download(ref));
      image = await store.importImage(rendered.png, 'png');
    } catch (e) {
      return ImportOutcome(ref, ImportResult.failed, '$e');
    }
    final chart = recordFor(
      ref,
      georef,
      id: previous?.id ?? store.newChartId(),
      imageFile: image.fileName,
      imageSize: image.size,
    );
    try {
      await store.saveChart(chart);
    } catch (e) {
      await store.discardImage(image.fileName);
      return ImportOutcome(ref, ImportResult.failed, '$e');
    }
    if (previous != null) await store.discardImage(previous.imageFile);
    return ImportOutcome(
      ref,
      ImportResult.georeferenced,
      'From ${georef.method}, '
      '${formatAccuracy(georef.accuracyMeters, estimated: georef.estimated)}'
      '${georef.notToScale.isEmpty ? '' : '; parts marked not to scale'}.',
    );
  }

  /// Applies improved georeferencing the backend has published since
  /// [icao]'s charts were imported, and returns how many changed.
  ///
  /// Only charts whose points are still automatic are touched; points a
  /// person placed or edited stay as they are. The PDF must be the same
  /// one, or the new points wouldn't fit the stored image.
  Future<int> refreshGeoreferences(String icao) async {
    final stored = [
      for (final c in store.chartsFor(icao))
        if (c.source?.sourceId == source.id &&
            c.autoMethod != null &&
            c.source?.sha256 != null)
          c,
    ];
    final byEdition = <String, List<ChartRecord>>{};
    for (final c in stored) {
      (byEdition[c.source!.editionId] ??= []).add(c);
    }
    var updated = 0;
    for (final charts in byEdition.values) {
      final s = charts.first.source!;
      final edition = AipEdition(
        id: s.editionId,
        name: s.editionName,
        effective: s.effective,
      );
      final published = {
        for (final r in await source.charts(icao, edition)) r.fileName: r,
      };
      for (final c in charts) {
        final ref = published[c.source!.fileName];
        final georef = ref?.georef;
        if (ref == null ||
            georef == null ||
            ref.sha256 != c.source!.sha256 ||
            georef.revision <= (c.source!.georefRevision ?? 0)) {
          continue;
        }
        await store.saveChart(
          recordFor(
            ref,
            georef,
            id: c.id,
            imageFile: c.imageFile,
            imageSize: c.imageSize,
          ).copyWith(name: c.name),
        );
        updated++;
      }
    }
    return updated;
  }

  ChartRecord recordFor(
    ChartRef ref,
    ChartGeoref georef, {
    required String id,
    required String imageFile,
    required Size imageSize,
  }) => ChartRecord(
    id: id,
    airportIcao: ref.icao,
    name: ref.title,
    imageFile: imageFile,
    imageSize: imageSize,
    controlPoints: controlPointsFor(georef, imageSize),
    source: ChartSource(
      sourceId: source.id,
      editionId: ref.edition.id,
      editionName: ref.edition.name,
      effective: ref.edition.effective,
      fileName: ref.fileName,
      url: ref.pdfPath ?? '',
      category: ref.category.name,
      sha256: ref.sha256,
      georefRevision: georef.revision,
    ),
    autoMethod: georef.method,
    autoAccuracyMeters: georef.accuracyMeters,
    autoAccuracyEstimated: georef.estimated,
    projectionId: georef.projectionId,
    conformalFit: georef.conformal,
    notToScaleAreas: [
      for (final r in georef.notToScale)
        Rect.fromLTRB(
          r.left * imageSize.width,
          r.top * imageSize.height,
          r.right * imageSize.width,
          r.bottom * imageSize.height,
        ),
    ],
  );
}

/// The backend's points (page fractions) on an image of [imageSize].
List<ControlPoint> controlPointsFor(ChartGeoref georef, Size imageSize) => [
  for (final p in georef.points)
    ControlPoint(
      pixel: Offset(p.u * imageSize.width, p.v * imageSize.height),
      position: p.position,
    ),
];

/// `±14 m`, `±1.2 km`, with `~` for estimates.
String formatAccuracy(double meters, {bool estimated = false}) {
  final value = meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';
  return '±${estimated ? '~' : ''}$value';
}
