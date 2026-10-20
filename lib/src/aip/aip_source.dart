import 'dart:typed_data';

import '../geo/lat_lng.dart';
import 'aip_points.dart';

/// One published edition (AIRAC amendment) of an AIP.
class AipEdition {
  const AipEdition({
    required this.id,
    required this.name,
    required this.effective,
    required this.baseUrl,
  });

  /// Stable identifier, e.g. `2026-09`.
  final String id;

  /// Human name as published, e.g. `AMDT 09/2026`.
  final String name;
  final DateTime effective;

  /// Root of the edition's files.
  final Uri baseUrl;

  bool isEffectiveOn(DateTime day) => !effective.isAfter(day);
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
}

/// A chart listed in an AIP, before it is downloaded.
class ChartRef {
  const ChartRef({
    required this.icao,
    required this.fileName,
    required this.title,
    required this.category,
    required this.url,
    required this.edition,
  });

  final String icao;

  /// Published file name, unique within an edition and airport.
  final String fileName;
  final String title;
  final ChartCategory category;
  final Uri url;
  final AipEdition edition;
}

/// A country's (or publication format's) AIP.
///
/// To support another state, implement this, usually by extending
/// [EurocontrolEaipSource], and register it in [AipRegistry].
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

  /// Published editions, newest first. Usually the current one and, near
  /// an AIRAC date, the next.
  Future<List<AipEdition>> editions();

  Future<List<ChartRef>> charts(String icao, AipEdition edition);

  Future<Uint8List> download(ChartRef chart);

  /// Waypoints, navaids and reference points that [icao]'s charts may
  /// show, with their published positions.
  Future<PointDirectory> points(String icao, AipEdition edition);

  /// Names of the pages describing ATS routes (ENR 3.x).
  Future<List<String>> routePages(AipEdition edition);

  /// The HTML of one page of [edition].
  Future<String> page(AipEdition edition, String name);
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
