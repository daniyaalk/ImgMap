import 'dart:math' as math;

import '../geo/lat_lng.dart';

enum PointKind { navaid, waypoint }

/// A significant point on the airway network.
class EnroutePoint {
  const EnroutePoint({
    required this.name,
    required this.position,
    required this.kind,
    this.ident,
    this.compulsory = false,
  });

  /// As published, e.g. `DUDUM` or `DELHI DVOR/DME`.
  final String name;

  /// Navaid identifier (`DPN`), when the point is a navaid.
  final String? ident;
  final LatLng position;
  final PointKind kind;

  /// A compulsory reporting point (filled triangle on charts).
  final bool compulsory;

  /// What charts label the point with.
  String get label => ident ?? name;

  Map<String, dynamic> toJson() => {
    'n': name,
    if (ident != null) 'i': ident,
    'lat': position.latitude,
    'lon': position.longitude,
    'k': kind.name,
    if (compulsory) 'c': true,
  };

  factory EnroutePoint.fromJson(Map<String, dynamic> j) => EnroutePoint(
    name: j['n'] as String,
    ident: j['i'] as String?,
    position: LatLng(
      (j['lat'] as num).toDouble(),
      (j['lon'] as num).toDouble(),
    ),
    kind: PointKind.values.byName(j['k'] as String),
    compulsory: j['c'] == true,
  );
}

/// One leg of a route, between consecutive points, with what the AIP
/// publishes for it.
class RouteSegment {
  const RouteSegment({
    required this.from,
    required this.to,
    this.trackMagnetic,
    this.distanceNm,
    this.upper,
    this.lower,
    this.airspaceClass,
    this.mocaFt,
    this.widthNm,
  });

  final EnroutePoint from, to;
  final int? trackMagnetic;
  final double? distanceNm;

  /// Vertical limits as published, e.g. `FL 460`, `FL 75`.
  final String? upper, lower;
  final String? airspaceClass;
  final int? mocaFt;
  final double? widthNm;

  /// Great-circle length from the coordinates.
  double get computedDistanceNm => from.position.distanceTo(to.position) / 1852;

  /// Initial true track from the coordinates.
  double get computedTrackTrue => from.position.bearingTo(to.position);

  Map<String, dynamic> toJson(Map<EnroutePoint, int> index) => {
    'f': index[from],
    't': index[to],
    if (trackMagnetic != null) 'trk': trackMagnetic,
    if (distanceNm != null) 'd': distanceNm,
    if (upper != null) 'u': upper,
    if (lower != null) 'l': lower,
    if (airspaceClass != null) 'cls': airspaceClass,
    if (mocaFt != null) 'moca': mocaFt,
    if (widthNm != null) 'w': widthNm,
  };

  factory RouteSegment.fromJson(
    Map<String, dynamic> j,
    List<EnroutePoint> points,
  ) => RouteSegment(
    from: points[j['f'] as int],
    to: points[j['t'] as int],
    trackMagnetic: j['trk'] as int?,
    distanceNm: (j['d'] as num?)?.toDouble(),
    upper: j['u'] as String?,
    lower: j['l'] as String?,
    airspaceClass: j['cls'] as String?,
    mocaFt: j['moca'] as int?,
    widthNm: (j['w'] as num?)?.toDouble(),
  );
}

/// An ATS route, e.g. `A474` or `Q2`.
class AirRoute {
  const AirRoute({
    required this.designator,
    required this.segments,
    this.navigationSpec,
  });

  final String designator;

  /// e.g. `RNAV 5`, `RNP10`; null for conventional routes.
  final String? navigationSpec;
  final List<RouteSegment> segments;

  bool get isRnav => navigationSpec != null;

  List<EnroutePoint> get points => [
    if (segments.isNotEmpty) segments.first.from,
    for (final s in segments) s.to,
  ];
}

/// A segment whose coordinates don't match its published length or track.
class SegmentIssue {
  const SegmentIssue(this.route, this.segment, this.message);
  final AirRoute route;
  final RouteSegment segment;
  final String message;
}

/// The airway network from one AIP edition.
class EnrouteData {
  EnrouteData({
    required this.sourceId,
    required this.editionId,
    required this.editionName,
    required this.points,
    required this.routes,
    this.unreadPages = const [],
  });

  final String sourceId, editionId, editionName;
  final List<EnroutePoint> points;
  final List<AirRoute> routes;

  /// Route pages that couldn't be fetched or parsed.
  final List<String> unreadPages;

  /// Segments to treat with suspicion. A route segment publishes its
  /// length and magnetic track, so a misread coordinate shows up as a
  /// mismatch.
  late final List<SegmentIssue> issues = [
    for (final r in routes)
      for (final s in r.segments)
        if (_check(s) case final message?) SegmentIssue(r, s, message),
  ];

  late final Set<RouteSegment> suspect = {for (final i in issues) i.segment};

  static String? _check(RouteSegment s) {
    final d = s.distanceNm;
    if (d != null) {
      final computed = s.computedDistanceNm;
      if ((computed - d).abs() > math.max(0.6, 0.02 * d)) {
        return 'Published ${d.toStringAsFixed(1)} NM, coordinates give '
            '${computed.toStringAsFixed(1)} NM.';
      }
    }
    final t = s.trackMagnetic;
    if (t != null && s.computedDistanceNm > 2) {
      // Magnetic variation stays within a few degrees over most regions;
      // a wrong coordinate usually throws the track far further.
      var diff = (s.computedTrackTrue - t).abs() % 360;
      if (diff > 180) diff = 360 - diff;
      if (diff > 8) {
        return 'Published track ${t.toString().padLeft(3, '0')}°M, '
            'coordinates give ${s.computedTrackTrue.round()}°T.';
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final index = {for (var i = 0; i < points.length; i++) points[i]: i};
    return {
      'version': 1,
      'source': sourceId,
      'edition': editionId,
      'editionName': editionName,
      'points': [for (final p in points) p.toJson()],
      'routes': [
        for (final r in routes)
          {
            'id': r.designator,
            if (r.navigationSpec != null) 'spec': r.navigationSpec,
            'seg': [for (final s in r.segments) s.toJson(index)],
          },
      ],
      'unread': unreadPages,
    };
  }

  factory EnrouteData.fromJson(Map<String, dynamic> j) {
    final points = [
      for (final p in j['points'] as List)
        EnroutePoint.fromJson(p as Map<String, dynamic>),
    ];
    return EnrouteData(
      sourceId: j['source'] as String,
      editionId: j['edition'] as String,
      editionName: j['editionName'] as String,
      points: points,
      routes: [
        for (final r in j['routes'] as List)
          AirRoute(
            designator: (r as Map<String, dynamic>)['id'] as String,
            navigationSpec: r['spec'] as String?,
            segments: [
              for (final s in r['seg'] as List)
                RouteSegment.fromJson(s as Map<String, dynamic>, points),
            ],
          ),
      ],
      unreadPages: [for (final u in j['unread'] as List? ?? []) u as String],
    );
  }
}
