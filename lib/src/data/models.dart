import 'dart:ui' show Rect, Size;

import '../geo/georeference.dart';
import '../geo/projection.dart';

class Airport {
  const Airport({required this.icao, this.name = ''});

  /// Four-letter ICAO location indicator, upper case.
  final String icao;
  final String name;

  Airport copyWith({String? name}) =>
      Airport(icao: icao, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'icao': icao, 'name': name};

  factory Airport.fromJson(Map<String, dynamic> json) => Airport(
    icao: json['icao'] as String,
    name: (json['name'] as String?) ?? '',
  );
}

/// Where a chart was downloaded from.
class ChartSource {
  const ChartSource({
    required this.sourceId,
    required this.editionId,
    required this.editionName,
    required this.effective,
    required this.fileName,
    required this.url,
    required this.category,
  });

  /// [AipSource.id], e.g. `in-aai`.
  final String sourceId;
  final String editionId;
  final String editionName;
  final DateTime effective;
  final String fileName;
  final String url;

  /// [ChartCategory.name].
  final String category;

  Map<String, dynamic> toJson() => {
    'source': sourceId,
    'edition': editionId,
    'editionName': editionName,
    'effective': effective.toIso8601String(),
    'file': fileName,
    'url': url,
    'category': category,
  };

  factory ChartSource.fromJson(Map<String, dynamic> json) => ChartSource(
    sourceId: json['source'] as String,
    editionId: json['edition'] as String,
    editionName: json['editionName'] as String,
    effective: DateTime.parse(json['effective'] as String),
    fileName: json['file'] as String,
    url: json['url'] as String,
    category: json['category'] as String,
  );
}

class ChartRecord {
  const ChartRecord({
    required this.id,
    required this.airportIcao,
    required this.name,
    required this.imageFile,
    required this.imageSize,
    required this.controlPoints,
    this.source,
    this.autoMethod,
    this.autoAccuracyMeters,
    this.autoAccuracyEstimated = false,
    this.projectionId,
    this.notToScaleAreas = const [],
    this.conformalFit = false,
  });

  /// Fit scale and rotation only (see [Georeference.fit]); set for charts
  /// georeferenced from named fixes.
  final bool conformalFit;

  final String id;
  final String airportIcao;
  final String name;

  /// File name inside the store's image directory.
  final String imageFile;

  /// Pixel size of the stored image; control points are in this space.
  final Size imageSize;
  final List<ControlPoint> controlPoints;

  /// Set for charts fetched from an AIP.
  final ChartSource? source;

  /// How the points were placed automatically, e.g. `grid labels`; null
  /// once a person has placed or edited them.
  final String? autoMethod;
  final double? autoAccuracyMeters;

  /// [autoAccuracyMeters] is an allowance, not a measured residual.
  final bool autoAccuracyEstimated;

  /// [MapProjection.id] the chart is drawn in, when known; Mercator if
  /// null.
  final String? projectionId;

  MapProjection get projection => MapProjection.fromId(projectionId);

  /// Parts of the chart it marks NOT TO SCALE, in image pixels.
  final List<Rect> notToScaleAreas;

  /// The fitted transform, or null if the points no longer define one.
  Georeference? get georeference {
    try {
      return Georeference.fit(
        controlPoints,
        projection: projection,
        conformal: conformalFit,
      );
    } on GeoreferenceException {
      return null;
    }
  }

  ChartRecord copyWith({
    String? name,
    List<ControlPoint>? controlPoints,
    bool clearAuto = false,
  }) => ChartRecord(
    id: id,
    airportIcao: airportIcao,
    name: name ?? this.name,
    imageFile: imageFile,
    imageSize: imageSize,
    controlPoints: controlPoints ?? this.controlPoints,
    source: source,
    autoMethod: clearAuto ? null : autoMethod,
    autoAccuracyMeters: clearAuto ? null : autoAccuracyMeters,
    autoAccuracyEstimated: !clearAuto && autoAccuracyEstimated,
    projectionId: projectionId,
    notToScaleAreas: notToScaleAreas,
    // Hand-placed points may come from a skewed scan.
    conformalFit: !clearAuto && conformalFit,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'airport': airportIcao,
    'name': name,
    'image': imageFile,
    'width': imageSize.width,
    'height': imageSize.height,
    'points': [for (final p in controlPoints) p.toJson()],
    if (source != null) 'source': source!.toJson(),
    if (autoMethod != null) 'autoMethod': autoMethod,
    if (autoAccuracyMeters != null) 'autoAccuracy': autoAccuracyMeters,
    if (autoAccuracyEstimated) 'autoAccuracyEstimated': true,
    if (projectionId != null) 'projection': projectionId,
    if (conformalFit) 'conformal': true,
    if (notToScaleAreas.isNotEmpty)
      'notToScale': [
        for (final r in notToScaleAreas) [r.left, r.top, r.right, r.bottom],
      ],
  };

  factory ChartRecord.fromJson(Map<String, dynamic> json) => ChartRecord(
    id: json['id'] as String,
    airportIcao: json['airport'] as String,
    name: json['name'] as String,
    imageFile: json['image'] as String,
    imageSize: Size(
      (json['width'] as num).toDouble(),
      (json['height'] as num).toDouble(),
    ),
    controlPoints: [
      for (final p in json['points'] as List)
        ControlPoint.fromJson(p as Map<String, dynamic>),
    ],
    source: json['source'] == null
        ? null
        : ChartSource.fromJson(json['source'] as Map<String, dynamic>),
    autoMethod: json['autoMethod'] as String?,
    autoAccuracyMeters: (json['autoAccuracy'] as num?)?.toDouble(),
    autoAccuracyEstimated: json['autoAccuracyEstimated'] == true,
    projectionId: json['projection'] as String?,
    conformalFit: json['conformal'] == true,
    notToScaleAreas: [
      for (final r in json['notToScale'] as List? ?? const [])
        Rect.fromLTRB(
          ((r as List)[0] as num).toDouble(),
          (r[1] as num).toDouble(),
          (r[2] as num).toDouble(),
          (r[3] as num).toDouble(),
        ),
    ],
  );
}
