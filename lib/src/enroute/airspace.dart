import 'dart:math' as math;

import '../geo/lat_lng.dart';

enum AirspaceKind {
  ctr('Control zone'),
  tma('Terminal control area'),
  cta('Control area'),
  fir('Flight information region');

  const AirspaceKind(this.label);
  final String label;
}

/// An ATS unit serving an airspace, e.g. Delhi ACC.
class AtsUnit {
  const AtsUnit({
    required this.name,
    required this.frequenciesKhz,
    this.callsign,
    this.hours,
  });

  final String name;

  /// As published, e.g. `Delhi Control/Delhi Radar (RSR)`.
  final String? callsign;

  /// `H24`, `HO`, `HJ`…
  final String? hours;
  final List<int> frequenciesKhz;

  /// VHF in MHz (`120.900`), HF in kHz (`10018 kHz`).
  static String formatFrequency(int khz) =>
      khz >= 30000 ? (khz / 1000).toStringAsFixed(3) : '$khz kHz';

  List<String> get frequencies => [
    // Voice VHF first: what a pilot tunes.
    for (final f in frequenciesKhz.where((f) => f >= 30000)) formatFrequency(f),
    for (final f in frequenciesKhz.where((f) => f < 30000)) formatFrequency(f),
  ];

  Map<String, dynamic> toJson() => {
    'n': name,
    if (callsign != null) 'cs': callsign,
    if (hours != null) 'h': hours,
    'f': frequenciesKhz,
  };

  factory AtsUnit.fromJson(Map<String, dynamic> j) => AtsUnit(
    name: j['n'] as String,
    callsign: j['cs'] as String?,
    hours: j['h'] as String?,
    frequenciesKhz: [for (final f in j['f'] as List? ?? []) f as int],
  );
}

/// A FIR, control area, TMA or control zone from the AIP's ENR 2.1.
class Airspace {
  Airspace({
    required this.name,
    required this.kind,
    required this.rings,
    required this.units,
    this.upper,
    this.lower,
    this.upperFt,
    this.lowerFt,
    this.airspaceClass,
    this.approximate = false,
  });

  final String name;
  final AirspaceKind kind;

  /// The outer boundary, then any holes. Empty when the AIP's limits
  /// couldn't be read.
  final List<List<LatLng>> rings;

  /// Vertical limits as published, e.g. `FL 460`, `2700 FT AMSL`.
  final String? upper, lower;

  /// In feet; a null upper limit is unlimited.
  final int? upperFt, lowerFt;
  final String? airspaceClass;

  /// The boundary partly follows a border or coastline, drawn as a straight
  /// line between the published points.
  final bool approximate;
  final List<AtsUnit> units;

  late final ({double south, double west, double north, double east}) _bounds =
      () {
        var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
        for (final p in rings.expand((r) => r)) {
          s = math.min(s, p.latitude);
          n = math.max(n, p.latitude);
          w = math.min(w, p.longitude);
          e = math.max(e, p.longitude);
        }
        return (south: s, west: w, north: n, east: e);
      }();

  /// A rough size, for putting the most specific airspace first.
  double get _extent =>
      (_bounds.north - _bounds.south) * (_bounds.east - _bounds.west);

  bool contains(LatLng p) {
    if (rings.isEmpty) return false;
    final b = _bounds;
    if (p.latitude < b.south ||
        p.latitude > b.north ||
        p.longitude < b.west ||
        p.longitude > b.east) {
      return false;
    }
    // Even-odd over all rings, so holes are outside.
    var inside = false;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final a = ring[i], c = ring[j];
        if ((a.latitude > p.latitude) != (c.latitude > p.latitude) &&
            p.longitude <
                (c.longitude - a.longitude) *
                        (p.latitude - a.latitude) /
                        (c.latitude - a.latitude) +
                    a.longitude) {
          inside = !inside;
        }
      }
    }
    return inside;
  }

  /// Whether [altitudeFt] lies within the vertical limits. Flight levels
  /// are compared as altitudes, close enough to tell sectors apart.
  bool coversAltitude(double altitudeFt) =>
      altitudeFt >= (lowerFt ?? 0) &&
      (upperFt == null || altitudeFt <= upperFt!);

  /// Distance from [p] to the boundary in nautical miles (approximate,
  /// flat-earth: for nearby points only).
  double distanceNm(LatLng p) {
    final k = math.cos(p.latitude * math.pi / 180);
    var best = double.infinity;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final ax = (ring[j].longitude - p.longitude) * k;
        final ay = ring[j].latitude - p.latitude;
        final bx = (ring[i].longitude - p.longitude) * k;
        final by = ring[i].latitude - p.latitude;
        final dx = bx - ax, dy = by - ay;
        final len2 = dx * dx + dy * dy;
        final t = len2 == 0
            ? 0.0
            : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
        final x = ax + dx * t, y = ay + dy * t;
        best = math.min(best, math.sqrt(x * x + y * y));
      }
    }
    return best * 60;
  }

  String get levels => '${lower ?? '—'} to ${upper ?? '—'}';

  Map<String, dynamic> toJson() => {
    'n': name,
    'k': kind.name,
    if (rings.isNotEmpty)
      'rings': [
        for (final r in rings)
          [
            for (final p in r) [p.latitude, p.longitude],
          ],
      ],
    if (approximate) 'approx': true,
    if (upper != null) 'u': upper,
    if (upperFt != null) 'uft': upperFt,
    if (lower != null) 'l': lower,
    if (lowerFt != null) 'lft': lowerFt,
    if (airspaceClass != null) 'cls': airspaceClass,
    'units': [for (final u in units) u.toJson()],
  };

  /// Null for a kind this version doesn't know (skipped, not guessed).
  static Airspace? fromJson(Map<String, dynamic> j) {
    final kind = AirspaceKind.values.asNameMap()[j['k']];
    if (kind == null) return null;
    return Airspace(
      name: j['n'] as String,
      kind: kind,
      rings: [
        for (final r in j['rings'] as List? ?? [])
          [
            for (final p in r as List)
              LatLng(
                ((p as List)[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ),
          ],
      ],
      approximate: j['approx'] == true,
      upper: j['u'] as String?,
      upperFt: j['uft'] as int?,
      lower: j['l'] as String?,
      lowerFt: j['lft'] as int?,
      airspaceClass: j['cls'] as String?,
      units: [
        for (final u in j['units'] as List? ?? [])
          AtsUnit.fromJson(u as Map<String, dynamic>),
      ],
    );
  }
}

/// The airspace at a position: the most specific first (control zone
/// before control area before FIR, smaller before larger).
class AirspaceQuery {
  AirspaceQuery(List<Airspace> airspaces, LatLng at, {double? altitudeFt})
    : this._(_find(airspaces, at), altitudeFt);

  AirspaceQuery._(List<Airspace> found, this.altitudeFt)
    : current = [
        for (final a in found)
          if (altitudeFt == null || a.coversAltitude(altitudeFt)) a,
      ],
      aboveOrBelow = [
        for (final a in found)
          if (altitudeFt != null && !a.coversAltitude(altitudeFt)) a,
      ];

  final double? altitudeFt;

  /// Containing the position at its altitude (or at any, when unknown).
  final List<Airspace> current;

  /// Over or under the position.
  final List<Airspace> aboveOrBelow;

  bool get isEmpty => current.isEmpty && aboveOrBelow.isEmpty;

  /// The airspace to work: the most specific one with a frequency.
  Airspace? get primary =>
      current
          .where((a) => a.units.any((u) => u.frequenciesKhz.isNotEmpty))
          .firstOrNull ??
      current.firstOrNull;

  /// FIRs whose drawn boundary misses border regions; one this close is
  /// taken to be the FIR when no drawn one contains the position.
  static const double _approximateFirReachNm = 300;

  static List<Airspace> _find(List<Airspace> airspaces, LatLng at) {
    final found = [
      for (final a in airspaces)
        if (a.contains(at)) a,
    ];
    if (!found.any((a) => a.kind == AirspaceKind.fir)) {
      Airspace? nearest;
      var best = _approximateFirReachNm;
      for (final a in airspaces) {
        if (a.kind != AirspaceKind.fir || !a.approximate || a.rings.isEmpty) {
          continue;
        }
        final d = a.distanceNm(at);
        if (d < best) {
          best = d;
          nearest = a;
        }
      }
      if (nearest != null) found.add(nearest);
    }
    found.sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      return k != 0 ? k : a._extent.compareTo(b._extent);
    });
    return found;
  }
}
