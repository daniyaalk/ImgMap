import 'dart:ui';

import '../data/models.dart';
import 'lat_lng.dart';

/// The ground area a georeferenced chart covers: its image corners placed
/// on the ground. Null if the chart isn't georeferenced.
List<LatLng>? chartFootprint(ChartRecord chart) {
  final geo = chart.georeference;
  if (geo == null) return null;
  final s = chart.imageSize;
  return [
    for (final corner in [
      Offset.zero,
      Offset(s.width, 0),
      Offset(s.width, s.height),
      Offset(0, s.height),
    ])
      geo.toLatLng(corner),
  ];
}

/// Whether [p] lies inside [polygon] (ray casting in latitude/longitude,
/// fine for a chart's few hundred kilometres).
bool polygonContains(List<LatLng> polygon, LatLng p) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude <
            (b.longitude - a.longitude) *
                    (p.latitude - a.latitude) /
                    (b.latitude - a.latitude) +
                a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}
