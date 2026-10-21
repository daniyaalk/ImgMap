import 'dart:typed_data';
import 'dart:ui';

import '../geo/lat_lng.dart';
import '../geo/projection.dart';

/// One published edition (AIRAC amendment) of an AIP.
class AipEdition {
  const AipEdition({
    required this.id,
    required this.name,
    required this.effective,
  });

  /// Stable identifier, e.g. `2026-09`.
  final String id;

  /// Human name as published, e.g. `AMDT 09/2026`.
  final String name;
  final DateTime effective;

  bool isEffectiveOn(DateTime day) => !effective.isAfter(day);

  factory AipEdition.fromJson(Map<String, dynamic> j) => AipEdition(
    id: j['id'] as String,
    name: j['name'] as String,
    effective: DateTime.parse('${j['effective']}T00:00:00Z'),
  );
}

enum ChartCategory {
  aerodrome('Aerodrome'),
  parking('Parking & docking'),
  ground('Ground movement'),
  departure('Departures (SID)'),
  arrival('Arrivals (STAR)'),
  approach('Approaches'),
  terrain('Obstacles & terrain'),
  tabular('Tables & coding'),
  other('Other');

  const ChartCategory(this.label);
  final String label;

  /// Whether charts of this kind are drawn to a map scale at all.
  bool get isMap => this != tabular;

  /// The category named [name], or null for one this version doesn't know.
  static ChartCategory? byNameOrNull(String? name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// A chart's placement on the ground, worked out by the backend.
///
/// Positions are fractions of the displayed page, so they apply at
/// whatever size the PDF is rendered.
class ChartGeoref {
  const ChartGeoref({
    required this.revision,
    required this.method,
    required this.projectionId,
    required this.conformal,
    required this.accuracyMeters,
    required this.estimated,
    required this.points,
    required this.footprint,
    required this.notToScale,
  });

  /// Increases whenever the backend's placement of this chart changes.
  final int revision;
  final String method;
  final String projectionId;
  final bool conformal;
  final double accuracyMeters;
  final bool estimated;

  /// (u, v) page fractions and the ground position there.
  final List<({double u, double v, LatLng position})> points;

  /// The page's corners on the ground.
  final List<LatLng> footprint;

  /// Areas marked NOT TO SCALE, as page fractions.
  final List<Rect> notToScale;

  /// Null if the entry uses anything this app version can't apply (a newer
  /// projection, say): such a chart is treated as not georeferenced.
  static ChartGeoref? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    try {
      final projection = j['projection'] as String;
      if (!MapProjection.isKnown(projection)) return null;
      final points = [
        for (final p in j['points'] as List)
          (
            u: ((p as Map)['u'] as num).toDouble(),
            v: (p['v'] as num).toDouble(),
            position: LatLng(
              (p['lat'] as num).toDouble(),
              (p['lon'] as num).toDouble(),
            ),
          ),
      ];
      if (points.length < 2) return null;
      return ChartGeoref(
        revision: (j['revision'] as num?)?.toInt() ?? 0,
        method: j['method'] as String? ?? 'backend',
        projectionId: projection,
        conformal: j['conformal'] == true,
        accuracyMeters: (j['accuracyM'] as num?)?.toDouble() ?? 0,
        estimated: j['estimated'] == true,
        points: points,
        footprint: [
          for (final c in j['footprint'] as List? ?? const [])
            LatLng(
              ((c as List)[0] as num).toDouble(),
              (c[1] as num).toDouble(),
            ),
        ],
        notToScale: [
          for (final r in j['notToScale'] as List? ?? const [])
            Rect.fromLTRB(
              ((r as List)[0] as num).toDouble(),
              (r[1] as num).toDouble(),
              (r[2] as num).toDouble(),
              (r[3] as num).toDouble(),
            ),
        ],
      );
    } on Object {
      return null; // Malformed: unusable rather than wrong.
    }
  }
}

/// A chart listed in an AIP, before it is downloaded.
class ChartRef {
  const ChartRef({
    required this.icao,
    required this.fileName,
    required this.title,
    required this.category,
    required this.edition,
    this.pdfPath,
    this.sha256,
    this.bytes,
    this.georef,
    this.unusableReason,
  });

  final String icao;

  /// Published file name, unique within an edition and airport.
  final String fileName;
  final String title;
  final ChartCategory category;
  final AipEdition edition;

  /// The mirrored PDF, relative to the backend.
  final String? pdfPath;
  final String? sha256;
  final int? bytes;

  /// Null when the chart can't be used as a moving map.
  final ChartGeoref? georef;
  final String? unusableReason;

  bool get usable => georef != null && pdfPath != null && category.isMap;
}

/// A country's AIP, as published by the backend.
abstract class AipSource {
  /// Stable id stored with imported charts, e.g. `in-aai`.
  String get id;

  /// Shown to the user, e.g. `AIP India (AAI)`.
  String get displayName;

  /// The country it covers, e.g. `India`.
  String get country;

  /// ISO 3166-1 alpha-2 code, e.g. `IN`.
  String get countryCode;

  /// Roughly the middle of the country, for a first map view.
  LatLng get mapCenter;

  /// Whether this source publishes charts for [icao].
  bool covers(String icao);

  /// Published editions, newest first.
  Future<List<AipEdition>> editions();

  Future<List<ChartRef>> charts(String icao, AipEdition edition);

  /// The chart's PDF, checked against its published hash.
  Future<Uint8List> download(ChartRef chart);

  /// The airway network in EnrouteData JSON form.
  Future<Map<String, dynamic>> enroute(AipEdition edition);
}

/// The edition in force on [day], or null if none is yet.
AipEdition? currentEdition(List<AipEdition> editions, DateTime day) {
  final effective = editions.where((e) => e.isEffectiveOn(day)).toList()
    ..sort((a, b) => b.effective.compareTo(a.effective));
  return effective.isEmpty ? null : effective.first;
}

class AipException implements Exception {
  AipException(this.message, {this.statusCode});
  final String message;

  /// The HTTP status, when the server answered with an error.
  final int? statusCode;
  @override
  String toString() => message;
}
