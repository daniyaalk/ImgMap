import 'dart:math' as math;
import 'dart:ui';

import 'package:geolocator/geolocator.dart';

import '../geo/georeference.dart';
import '../geo/lat_lng.dart';

/// A fake GPS feed that flies an oval over the chart, for trying the moving
/// map without being in an aircraft.
///
/// The oval is slightly wider than the chart, so the aircraft briefly
/// leaves it on both sides. Time is compressed so a lap takes [lap];
/// reported speed is a realistic [groundSpeedKt] rather than the
/// compressed one.
Stream<Position> simulatedFlight(
  Georeference geo,
  Size chartSize, {
  Duration lap = const Duration(seconds: 80),
  Duration interval = const Duration(milliseconds: 500),
  double groundSpeedKt = 120,
  double altitudeFt = 3000,
}) {
  final center = Offset(chartSize.width, chartSize.height) / 2;
  final rx = chartSize.width * 0.56, ry = chartSize.height * 0.32;
  LatLng at(double t) {
    final a = 2 * math.pi * t;
    // Clockwise in screen space (y down), like a standard-rate right turn.
    return geo.toLatLng(center + Offset(rx * math.cos(a), ry * math.sin(a)));
  }

  final steps = lap.inMilliseconds / interval.inMilliseconds;
  return Stream.periodic(interval, (i) {
    final t = (i % steps) / steps;
    final here = at(t);
    final ahead = at(t + 0.002);
    return Position(
      latitude: here.latitude,
      longitude: here.longitude,
      timestamp: DateTime.now(),
      accuracy: 8,
      altitude: altitudeFt / 3.28084,
      altitudeAccuracy: 10,
      heading: here.bearingTo(ahead),
      headingAccuracy: 2,
      speed: groundSpeedKt / 1.943844,
      speedAccuracy: 1,
      isMocked: true,
      hasAccuracy: true,
      hasAltitude: true,
      hasHeading: true,
      hasSpeed: true,
    );
  });
}

/// A fake GPS feed flying along [path] (an airway's points) and back, at
/// [groundSpeedKt] with time sped up [timeScale] times, so a 50 NM leg
/// passes in about half a minute.
Stream<Position> simulatedPath(
  List<LatLng> path, {
  double groundSpeedKt = 250,
  double timeScale = 25,
  Duration interval = const Duration(milliseconds: 500),
  double altitudeFt = 24000,
}) {
  final there = [...path, ...path.reversed.skip(1)];
  final legs = [
    for (var i = 0; i + 1 < there.length; i++)
      there[i].distanceTo(there[i + 1]),
  ];
  final total = legs.fold<double>(0, (s, l) => s + l);
  final metersPerTick =
      groundSpeedKt / 1.943844 * timeScale * interval.inMilliseconds / 1000;
  return Stream.periodic(interval, (i) {
    var d = total == 0 ? 0.0 : (i * metersPerTick) % total;
    var leg = 0;
    while (leg < legs.length - 1 && d > legs[leg]) {
      d -= legs[leg++];
    }
    final a = there[leg], b = there[leg + 1];
    final f = legs[leg] == 0 ? 0.0 : d / legs[leg];
    final here = LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
    return Position(
      latitude: here.latitude,
      longitude: here.longitude,
      timestamp: DateTime.now(),
      accuracy: 8,
      altitude: altitudeFt / 3.28084,
      altitudeAccuracy: 10,
      heading: here.bearingTo(b),
      headingAccuracy: 2,
      speed: groundSpeedKt / 1.943844,
      speedAccuracy: 1,
      isMocked: true,
      hasAccuracy: true,
      hasAltitude: true,
      hasHeading: true,
      hasSpeed: true,
    );
  });
}
