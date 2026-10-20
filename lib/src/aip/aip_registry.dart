import 'package:flutter/foundation.dart';

import 'aip_source.dart';
import 'aip_countries.dart';
import 'eaip_country.dart';

/// Every AIP the app can fetch from. Add new states here.
class AipRegistry {
  AipRegistry([List<AipSource>? sources])
    : sources =
          sources ?? [for (final c in aipCountries) ConfiguredEaipSource(c)];

  final List<AipSource> sources;

  /// The source publishing [icao]'s charts, or null.
  ///
  /// The browser build has none: AIP sites don't send CORS headers, so a
  /// page can't read them without a proxy.
  AipSource? forAirport(String icao) {
    if (kIsWeb) return null;
    for (final s in sources) {
      if (s.covers(icao)) return s;
    }
    return null;
  }

  AipSource? byId(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }
}
