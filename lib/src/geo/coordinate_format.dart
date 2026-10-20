/// Parsing and formatting of latitude/longitude in the notations found on
/// aeronautical charts.
library;

enum CoordAxis { latitude, longitude }

/// Parses a latitude or longitude in decimal degrees.
///
/// Accepted forms (hemisphere letter before or after, case-insensitive):
///  * decimal degrees: `28.5665`, `-77.1031`, `N28.5665`
///  * degrees and minutes: `N28°34.0'`, `28 34.0 N`, `E077 06.2`
///  * degrees, minutes, seconds: `28°34'00"N`, `28:34:00 N`
///  * packed ICAO style: `2834N`, `283400N`, `283400.5N`, `0770600E`
///
/// Throws [FormatException] with a user-facing message on bad input.
double parseCoordinate(String input, CoordAxis axis) {
  var s = input.trim().toUpperCase();
  if (s.isEmpty) throw const FormatException('Required');

  final positive = axis == CoordAxis.latitude ? 'N' : 'E';
  final negative = axis == CoordAxis.latitude ? 'S' : 'W';
  final wrong = axis == CoordAxis.latitude ? RegExp('[EW]') : RegExp('[NS]');
  if (wrong.hasMatch(s)) {
    throw FormatException(
      axis == CoordAxis.latitude
          ? 'Latitude takes N or S'
          : 'Longitude takes E or W',
    );
  }

  var sign = 1.0;
  String? hemisphere;
  if (s.startsWith(positive) || s.startsWith(negative)) {
    hemisphere = s[0];
    s = s.substring(1).trim();
  } else if (s.endsWith(positive) || s.endsWith(negative)) {
    hemisphere = s[s.length - 1];
    s = s.substring(0, s.length - 1).trim();
  }
  if (s.startsWith('-')) {
    if (hemisphere != null) {
      throw const FormatException('Use either a sign or N/S/E/W, not both');
    }
    sign = -1;
    s = s.substring(1).trim();
  } else if (s.startsWith('+')) {
    s = s.substring(1).trim();
  }
  if (hemisphere == negative) sign = -1;

  final parts = s
      .split(RegExp(r'''[\s°º:'"′″]+'''))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.length > 3) {
    throw const FormatException('Not a coordinate');
  }
  final number = RegExp(r'^\d+(\.\d+)?$');
  if (!parts.every(number.hasMatch)) {
    throw const FormatException('Not a coordinate');
  }

  double deg, min = 0, sec = 0;
  if (parts.length == 1 && hemisphere != null && _isPacked(parts[0], axis)) {
    final whole = parts[0].split('.')[0];
    final frac = parts[0].contains('.') ? '.${parts[0].split('.')[1]}' : '';
    final degDigits = axis == CoordAxis.latitude ? 2 : 3;
    deg = double.parse(whole.substring(0, degDigits));
    final rest = whole.substring(degDigits);
    if (rest.length == 2) {
      min = double.parse(rest + frac);
    } else {
      min = double.parse(rest.substring(0, 2));
      sec = double.parse(rest.substring(2) + frac);
    }
  } else {
    deg = double.parse(parts[0]);
    if (parts.length > 1) {
      if (parts[0].contains('.')) {
        throw const FormatException('Only the last part may have decimals');
      }
      min = double.parse(parts[1]);
    }
    if (parts.length > 2) {
      if (parts[1].contains('.')) {
        throw const FormatException('Only the last part may have decimals');
      }
      sec = double.parse(parts[2]);
    }
  }
  if (min >= 60) throw const FormatException('Minutes must be under 60');
  if (sec >= 60) throw const FormatException('Seconds must be under 60');

  final value = sign * (deg + min / 60 + sec / 3600);
  final limit = axis == CoordAxis.latitude ? 90 : 180;
  if (value.abs() > limit) {
    throw FormatException('Must be within ±$limit°');
  }
  return value;
}

/// Packed forms are digit runs longer than a plain degree value:
/// DDMM / DDMMSS for latitude, DDDMM / DDDMMSS for longitude.
bool _isPacked(String s, CoordAxis axis) {
  final whole = s.split('.')[0].length;
  return axis == CoordAxis.latitude
      ? (whole == 4 || whole == 6)
      : (whole == 5 || whole == 7);
}

/// Formats as degrees and decimal minutes, e.g. `N28°34.00'`.
String formatCoordinate(double value, CoordAxis axis) {
  final hemi = axis == CoordAxis.latitude
      ? (value < 0 ? 'S' : 'N')
      : (value < 0 ? 'W' : 'E');
  final abs = value.abs();
  var deg = abs.floor();
  var min = (abs - deg) * 60;
  // Avoid "59.999" rounding up to an invalid "60.00".
  if (double.parse(min.toStringAsFixed(2)) >= 60) {
    deg += 1;
    min = 0;
  }
  final degWidth = axis == CoordAxis.latitude ? 2 : 3;
  return "$hemi${deg.toString().padLeft(degWidth, '0')}°"
      "${min.toStringAsFixed(2).padLeft(5, '0')}'";
}
