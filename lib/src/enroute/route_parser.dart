import 'package:html/parser.dart' as html;

import '../aip/aip_points.dart' show nodeText;
import '../geo/lat_lng.dart';
import 'enroute_model.dart';

/// A route as read from one page, before points are shared across routes.
class ParsedRoute {
  ParsedRoute(this.designator, this.navigationSpec);
  final String designator;
  final String? navigationSpec;
  final List<ParsedPoint> points = [];

  /// Data for the leg after each point; one shorter than [points] when
  /// complete.
  final List<ParsedLeg> legs = [];
}

class ParsedPoint {
  const ParsedPoint(
    this.name,
    this.ident,
    this.position,
    this.kind,
    this.compulsory,
  );
  final String name;
  final String? ident;
  final LatLng position;
  final PointKind kind;
  final bool compulsory;
}

class ParsedLeg {
  const ParsedLeg({
    this.trackMagnetic,
    this.distanceNm,
    this.upper,
    this.lower,
    this.airspaceClass,
    this.mocaFt,
    this.widthNm,
  });
  final int? trackMagnetic;
  final double? distanceNm;
  final String? upper, lower, airspaceClass;
  final int? mocaFt;
  final double? widthNm;
}

final _header = RegExp(
  r'^([A-Z]{1,2}\d{1,4}[A-Z]?)\b\s*(?:\(((?:RNAV|RNP)\s*[\d.]+)\))?',
);
final _point = RegExp(
  r'^(.*?)\s*(\d{2})(\d{2})(\d{2}(?:\.\d+)?)\s*([NS])\s*'
  r'(\d{3})(\d{2})(\d{2}(?:\.\d+)?)\s*([EW])',
);
final _ident = RegExp(r'\(([A-Z]{2,4})\)');
final _navaid = RegExp(r'\b(VOR|DVOR|DME|NDB|TACAN|VORTAC)\b');
final _track = RegExp(r'\b(\d{3})\s*/\s*(?:\d{3}|-)');
final _distance = RegExp(r'([\d.]+)\s*NM\b');
final _level = RegExp(
  r'\b(FL\s*\d{2,3}|UNL|GND|\d{3,5}\s*FT(?:\s*(?:AMSL|ALT))?)',
);
final _class = RegExp(r'\bClass\s+([A-G])\b');
final _moca = RegExp(r'(\d{3,5})\s*FT\s*$');

/// Reads the routes on an eAIP ENR 3.x page.
///
/// The table alternates point rows (`DUDUM 274801N 0763121E`) with leg
/// rows (`213/- 55.0 NM | FL 460 FL 75 Class D 3200 FT | 20 NM`), under a
/// header row naming the route (`A474 (DPN-MURUS)`).
List<ParsedRoute> parseRoutePage(String page) {
  final routes = <ParsedRoute>[];
  ParsedRoute? current;
  for (final row in html.parse(page).querySelectorAll('tr')) {
    final cells = [for (final c in row.children) nodeText(c)];
    if (cells.every((c) => c.isEmpty)) continue;
    final joined = cells.where((c) => c.isNotEmpty).join(' | ');

    final h = cells.length <= 3 ? _header.firstMatch(joined) : null;
    if (h != null && !_point.hasMatch(joined)) {
      current = ParsedRoute(h.group(1)!, h.group(2)?.replaceAll(' ', ' '));
      routes.add(current);
      continue;
    }
    if (current == null) continue;

    final pointCell = cells.firstWhere(_point.hasMatch, orElse: () => '');
    if (pointCell.isNotEmpty) {
      final m = _point.firstMatch(pointCell)!;
      final label = m.group(1)!.trim();
      final position = _latLng(m);
      if (position == null) continue;
      final ident = _ident.firstMatch(label)?.group(1);
      final name = label
          .replaceAll(_ident, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      // Rows that only repeat the previous point (a page break) add nothing.
      if (current.points.isNotEmpty &&
          current.points.last.position == position) {
        continue;
      }
      // A point without a leg row before it: keep legs in step.
      while (current.legs.length < current.points.length) {
        current.legs.add(const ParsedLeg());
      }
      current.points.add(
        ParsedPoint(
          name.isEmpty ? (ident ?? '?') : name,
          ident,
          position,
          _navaid.hasMatch(label) ? PointKind.navaid : PointKind.waypoint,
          cells.first.trim() == 'p',
        ),
      );
      continue;
    }

    final t = _track.firstMatch(joined);
    final d = _distance.firstMatch(cells.length > 2 ? cells[2] : joined);
    if ((t != null || d != null) &&
        current.points.isNotEmpty &&
        current.legs.length < current.points.length) {
      final limits = cells.length > 3 ? cells[3] : '';
      final levels = [for (final l in _level.allMatches(limits)) l.group(1)!];
      final width = cells.length > 4 ? _distance.firstMatch(cells[4]) : null;
      current.legs.add(
        ParsedLeg(
          trackMagnetic: t == null ? null : int.parse(t.group(1)!),
          distanceNm: d == null ? null : double.tryParse(d.group(1)!),
          upper: levels.isNotEmpty ? _tidy(levels[0]) : null,
          lower: levels.length > 1 ? _tidy(levels[1]) : null,
          airspaceClass: _class.firstMatch(limits)?.group(1),
          mocaFt: int.tryParse(_moca.firstMatch(limits)?.group(1) ?? ''),
          widthNm: width == null ? null : double.tryParse(width.group(1)!),
        ),
      );
    }
  }
  return routes.where((r) => r.points.length >= 2).toList();
}

String _tidy(String level) => level.replaceAll(RegExp(r'\s+'), ' ');

LatLng? _latLng(RegExpMatch m) {
  final latD = int.parse(m.group(2)!), latM = int.parse(m.group(3)!);
  final latS = double.parse(m.group(4)!);
  final lonD = int.parse(m.group(6)!), lonM = int.parse(m.group(7)!);
  final lonS = double.parse(m.group(8)!);
  if (latD > 90 || lonD > 180 || latM >= 60 || lonM >= 60) return null;
  if (latS >= 60 || lonS >= 60) return null;
  final lat = latD + latM / 60 + latS / 3600;
  final lon = lonD + lonM / 60 + lonS / 3600;
  return LatLng(m.group(5) == 'S' ? -lat : lat, m.group(9) == 'W' ? -lon : lon);
}
