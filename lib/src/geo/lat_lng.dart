import 'dart:math' as math;

/// A WGS-84 position in decimal degrees.
class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  static const double earthRadiusMeters = 6371008.8;

  /// Great-circle distance to [other] in meters.
  double distanceTo(LatLng other) {
    final lat1 = _rad(latitude);
    final lat2 = _rad(other.latitude);
    final dLat = lat2 - lat1;
    final dLon = _rad(other.longitude - longitude);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Initial great-circle bearing to [other], degrees true (0–360).
  double bearingTo(LatLng other) {
    final lat1 = _rad(latitude), lat2 = _rad(other.latitude);
    final dLon = _rad(other.longitude - longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Map<String, dynamic> toJson() => {'lat': latitude, 'lon': longitude};

  factory LatLng.fromJson(Map<String, dynamic> json) =>
      LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

double _rad(double deg) => deg * math.pi / 180;
