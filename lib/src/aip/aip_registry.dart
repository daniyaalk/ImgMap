import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'aip_source.dart';
import 'backend.dart';

/// The countries the app can get charts for, as published by the backend.
///
/// The list is cached, so it's there offline, and refreshed in the
/// background: a country added to the backend appears without an app
/// release.
class AipRegistry extends ChangeNotifier {
  AipRegistry([List<AipSource>? sources]) : _sources = sources ?? [];

  static const _cacheName = 'countries.json';

  List<AipSource> _sources;
  Backend? _backend;
  ChartStorage? _storage;

  List<AipSource> get sources => _sources;

  /// Starts from the cached list and refreshes from [backend].
  static Future<AipRegistry> load(Backend backend, ChartStorage storage) async {
    final registry = AipRegistry()
      .._backend = backend
      .._storage = storage;
    final cached = await storage.readData(_cacheName);
    if (cached != null) {
      try {
        registry._sources = [
          for (final c in jsonDecode(cached) as List)
            if (BackendCountry.fromJson(c as Map<String, dynamic>)
                case final c?)
              BackendSource(backend, c),
        ];
      } on Object {
        // A damaged cache is replaced on refresh.
      }
    }
    registry.refresh();
    return registry;
  }

  /// Fetches the current list; keeps the cached one on failure.
  Future<void> refresh() async {
    final backend = _backend;
    if (backend == null || !backend.configured) return;
    try {
      final fresh = await backend.countries();
      _sources = fresh;
      notifyListeners();
      await _storage?.writeData(
        _cacheName,
        jsonEncode([for (final s in fresh) s.info.toJson()]),
      );
    } on Object {
      // Offline: the cached list stands.
    }
  }

  /// The source publishing [icao]'s charts, or null.
  AipSource? forAirport(String icao) {
    for (final s in _sources) {
      if (s.covers(icao)) return s;
    }
    return null;
  }

  AipSource? byId(String id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }
}
