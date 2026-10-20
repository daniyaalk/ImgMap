import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../geo/lat_lng.dart';

/// Named positions published in an AIP: waypoints, navaids, reference
/// points. A name can occur more than once (an NDB and a VOR sharing an
/// ident, or the same name in two states), so each maps to every position
/// published for it.
class PointDirectory {
  PointDirectory([Map<String, List<LatLng>>? points]) : _points = points ?? {};

  final Map<String, List<LatLng>> _points;

  static final empty = PointDirectory();

  bool get isEmpty => _points.isEmpty;
  int get length => _points.length;

  List<LatLng> operator [](String name) => _points[name] ?? const [];

  bool contains(String name) => _points.containsKey(name);

  void add(String name, LatLng position) {
    final list = _points.putIfAbsent(name, () => []);
    // The same point is often listed in several tables.
    if (!list.any((p) => p.distanceTo(position) < 50)) list.add(position);
  }

  void addAll(PointDirectory other) {
    other._points.forEach((name, list) {
      for (final p in list) {
        add(name, p);
      }
    });
  }
}

/// Words near a coordinate that are never point names.
const _notNames = {
  'VOR', 'DME', 'DVOR', 'NDB', 'ILS', 'LOC', 'GP', 'TACAN', 'VORTAC', //
  'MHZ', 'KHZ', 'GHZ', 'H24', 'HJ', 'HN', 'HO', 'HX', 'FT', 'M', 'NM', //
  'NOTAM', 'ATS', 'AIP', 'RWY', 'THR', 'TWY', 'AD', 'ARP', 'AMSL', 'ELEV', //
  'AND', 'OF', 'THE', 'TO', 'FROM', 'AT', 'ON', 'IN', 'BY', 'FOR', 'WITH', //
  'TOP', 'TANK', 'MAST', 'TOWER', 'POLE', 'ANT', 'BLDG', 'TREE', 'HILL', //
  'DEG', 'MAG', 'TRUE', 'EGM', 'WGS', 'N', 'S', 'E', 'W', 'NE', 'NW', 'SE', //
  'SW', 'CH', 'X', 'Y', 'IAF', 'IF', 'FAF', 'MAPT', 'FAP', 'SDF', 'NIL', //
  'NORTH', 'SOUTH', 'EAST', 'WEST', 'ABEAM', 'NEAR', 'CNTR', 'END', 'APRON', //
  'PAPI', 'VASI', 'ALS', 'RVR', 'SMR', 'WDI', 'LDI', 'ATC', 'TWR', 'APP', //
  'FIRE', 'GND', 'UNL', 'FL', 'MSL', 'AGL', 'DIST', 'NOTE', 'CAT', 'II', //
  'III', 'REF', 'POS', 'LAT', 'LONG', 'COORD', 'PSN', 'AREA', 'ZONE', //
  'MAX', 'MIN', 'KIAS', 'IAS', 'GS', 'AAI', 'RADAR', 'INDIA', 'DELHI', //
  'MSA', 'TA', 'TL', 'VAR', 'BRG', 'ALT', 'HDG', 'TRK', 'CTR', 'CTA', 'TMA', //
};

final _coordinates = RegExp(
  r'(\d{2})(\d{2})(\d{2}(?:\.\d+)?)\s*([NS])\s*(\d{3})(\d{2})(\d{2}(?:\.\d+)?)\s*([EW])',
);
final _name = RegExp(r'(?<![A-Za-z0-9])([A-Z][A-Z0-9]{1,4})(?![A-Za-z0-9])');

/// Reads every `DDMMSS.ssN DDDMMSS.ssE` position in an AIP page, named by
/// the identifier-like words just before it.
///
/// Works across the eAIP's tables without knowing their layout: waypoint
/// lists put the name right before the position (`PABGU 283357.00N …`),
/// navaid tables put the ident a few columns before (`AGRA VOR/DME AGG
/// 112.000MHZ (57X) H24 270926.21N …`). A stray word picked up as a name
/// costs nothing: a chart has to label it next to a symbol for it to be
/// used.
PointDirectory parsePointPage(String page) {
  final text = nodeText(html.parse(page).body!);
  final directory = PointDirectory();
  var previousEnd = 0;
  for (final m in _coordinates.allMatches(text)) {
    final position = _toLatLng(m);
    if (position != null) {
      final from = m.start - 140 > previousEnd ? m.start - 140 : previousEnd;
      final before = text.substring(from, m.start);
      // The last two name-like words: a waypoint list's name, or a navaid
      // table's ident and the station name before it.
      final names = [
        for (final n in _name.allMatches(before))
          if (isFixName(n.group(1)!)) n.group(1)!,
      ];
      for (final name in names.skip(names.length > 2 ? names.length - 2 : 0)) {
        directory.add(name, position);
      }
    }
    previousEnd = m.end;
  }
  return directory;
}

/// The current text of an eAIP [node].
///
/// * Amended text is published as the old value in `<del>` beside the new
///   one in `<ins>`; only the new is kept. Reading both would mix an old
///   latitude with a new longitude into a place that doesn't exist.
/// * Block elements (cells, paragraphs, line breaks) are separated by
///   spaces, which `.text` omits (`DME` + `AGG` → `DMEAGG`); inline ones are
///   not, so an amended number (`94` `.` `6`) stays whole.
String nodeText(dom.Node node) {
  final parts = <String>[];
  void collect(dom.Node n) {
    if (n is dom.Text) {
      parts.add(n.data);
      return;
    }
    if (n is dom.Element) {
      if (n.localName == 'del' || n.className.contains('Deleted')) return;
      final block = _blockTags.contains(n.localName);
      if (block) parts.add(' ');
      n.nodes.forEach(collect);
      if (block) parts.add(' ');
      return;
    }
    n.nodes.forEach(collect);
  }

  collect(node);
  return parts
      .join()
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

const _blockTags = {
  'td', 'th', 'tr', 'table', 'tbody', 'thead', 'p', 'div', 'br', 'li', //
  'ul', 'ol', 'dt', 'dd', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'section', //
};

/// Whether [word] has the shape of a fix designator: a five-letter name
/// (`DUDUM`), a navaid ident (`DPN`, `AT`), or a terminal waypoint code
/// (`DP421`, `BL407`).
bool isFixName(String word) {
  if (_notNames.contains(word)) return false;
  return RegExp(r'^[A-Z]{5}$').hasMatch(word) ||
      RegExp(r'^[A-Z]{2,3}$').hasMatch(word) ||
      // Not a flight level (FL100).
      (RegExp(r'^[A-Z]{2}[0-9]{3}$').hasMatch(word) && !word.startsWith('FL'));
}

LatLng? _toLatLng(RegExpMatch m) {
  final latDeg = int.parse(m.group(1)!), latMin = int.parse(m.group(2)!);
  final latSec = double.parse(m.group(3)!);
  final lonDeg = int.parse(m.group(5)!), lonMin = int.parse(m.group(6)!);
  final lonSec = double.parse(m.group(7)!);
  if (latDeg > 90 || lonDeg > 180 || latMin >= 60 || lonMin >= 60) return null;
  if (latSec >= 60 || lonSec >= 60) return null;
  final lat = latDeg + latMin / 60 + latSec / 3600;
  final lon = lonDeg + lonMin / 60 + lonSec / 3600;
  return LatLng(m.group(4) == 'S' ? -lat : lat, m.group(8) == 'W' ? -lon : lon);
}
