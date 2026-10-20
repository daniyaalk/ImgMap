import 'dart:ui' show Rect;

import '../data/chart_store.dart';
import '../data/models.dart';
import '../geo/georeference.dart';
import '../georef/auto_georeference.dart';
import '../georef/grid_labels.dart';
import 'aip_points.dart';
import '../pdf/chart_pdf.dart';
import 'aip_source.dart';

enum ImportResult {
  /// Saved with automatically placed control points.
  georeferenced,

  /// Not saved: it couldn't be georeferenced (a table, no grid, not to
  /// scale).
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

/// Downloads AIP charts, renders them, georeferences them and saves the
/// ones that work, replacing older editions of the same chart. Charts that
/// can't be georeferenced aren't kept, but are remembered so they aren't
/// offered again.
class ChartImporter {
  ChartImporter(this.store, this.source);

  final ChartStore store;
  final AipSource source;

  final Map<String, Future<PointDirectory>> _points = {};

  /// The AIP's points for [ref]'s airport, fetched once per import run.
  /// Without them, charts are georeferenced from their grids alone.
  Future<PointDirectory> _pointsFor(ChartRef ref) {
    final key = '${ref.icao}@${ref.edition.id}';
    return _points[key] ??= source.points(ref.icao, ref.edition).catchError((
      Object _,
    ) {
      _points.remove(key);
      return PointDirectory.empty;
    });
  }

  /// Charts in [edition] already tried that couldn't be georeferenced by
  /// the current method. A better method retries them.
  Set<String> unusableIn(String icao, AipEdition edition) =>
      store.unusableCharts(source.id, icao, _attempt(edition));

  static String _attempt(AipEdition e) => '${e.id}@v$autoGeoreferenceVersion';

  ImportOutcome? alreadyHave(ChartRef ref) {
    final existing = store.chartFromSource(source.id, ref.icao, ref.fileName);
    if (existing?.source?.editionId == ref.edition.id &&
        existing?.georeference != null) {
      return ImportOutcome(ref, ImportResult.upToDate, 'Already up to date.');
    }
    return null;
  }

  Future<ImportOutcome> importChart(ChartRef ref) async {
    final have = alreadyHave(ref);
    if (have != null) return have;
    final previous = store.chartFromSource(source.id, ref.icao, ref.fileName);

    if (!ref.category.isMap) {
      return _unusable(ref, previous, 'Table, not a map.');
    }
    final RenderedChart rendered;
    try {
      rendered = await renderChartPdf(await source.download(ref));
    } catch (e) {
      return ImportOutcome(ref, ImportResult.failed, '$e');
    }
    final auto = autoGeoreference(rendered, await _pointsFor(ref));
    if (auto is AutoGeoreferenceFailure) {
      return _unusable(ref, previous, auto.reason);
    }
    final fitted = auto as AutoGeoreference;

    final ImportedImage image;
    try {
      image = await store.importImage(rendered.png, 'png');
    } catch (e) {
      return ImportOutcome(ref, ImportResult.failed, '$e');
    }
    // Image pixels match the render unless the store had to downscale.
    final k = image.size.width / rendered.size.width;
    final chart = ChartRecord(
      id: previous?.id ?? store.newChartId(),
      airportIcao: ref.icao,
      name: ref.title,
      imageFile: image.fileName,
      imageSize: image.size,
      controlPoints: _scaled(fitted, k),
      source: _source(ref),
      autoMethod: fitted.method,
      autoAccuracyMeters: fitted.rmsMeters,
      autoAccuracyEstimated: fitted.estimated,
      projectionId: fitted.projection.id,
      conformalFit: fitted.conformal,
      notToScaleAreas: [
        for (final r in fitted.notToScaleAreas)
          Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k),
      ],
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
      'From ${fitted.method}, '
      '${formatAccuracy(fitted.rmsMeters, estimated: fitted.estimated)}'
      '${fitted.notToScaleAreas.isEmpty ? '' : '; parts marked not to scale'}.',
    );
  }

  /// Records [ref] as unusable. An older edition of it is removed too: a
  /// superseded chart shouldn't linger as if current.
  Future<ImportOutcome> _unusable(
    ChartRef ref,
    ChartRecord? previous,
    String reason,
  ) async {
    await store.markUnusable(
      source.id,
      ref.icao,
      _attempt(ref.edition),
      ref.fileName,
    );
    if (previous != null) await store.deleteChart(previous.id);
    return ImportOutcome(ref, ImportResult.unusable, reason);
  }

  ChartSource _source(ChartRef ref) => ChartSource(
    sourceId: source.id,
    editionId: ref.edition.id,
    editionName: ref.edition.name,
    effective: ref.edition.effective,
    fileName: ref.fileName,
    url: ref.url.toString(),
    category: ref.category.name,
  );

  static List<ControlPoint> _scaled(AutoGeoreference g, double k) => [
    for (final p in g.points)
      ControlPoint(pixel: p.pixel * k, position: p.position),
  ];
}

/// `±14 m`, `±1.2 km`, with `~` for estimates.
String formatAccuracy(double meters, {bool estimated = false}) {
  final value = meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';
  return '±${estimated ? '~' : ''}$value';
}
