import 'dart:async';
import 'dart:convert';

import '../aip/aip_source.dart';
import '../data/storage.dart';
import 'enroute_model.dart';

/// Fetches the airway network from the backend, and caches it.
class EnrouteLoader {
  EnrouteLoader(this.storage);

  final ChartStorage storage;

  static String _cacheName(String sourceId, String editionId) =>
      'enroute-$sourceId-$editionId.json';

  static String _latestName(String sourceId) => 'enroute-$sourceId.edition';

  /// The most recently downloaded network, whatever its edition; available
  /// offline.
  Future<EnrouteData?> latest(String sourceId) async {
    final edition = await storage.readData(_latestName(sourceId));
    return edition == null ? null : _read(sourceId, edition.trim());
  }

  /// The cached network for [edition], or null.
  Future<EnrouteData?> cached(AipSource source, AipEdition edition) =>
      _read(source.id, edition.id);

  Future<EnrouteData?> _read(String sourceId, String editionId) async {
    final text = await storage.readData(_cacheName(sourceId, editionId));
    if (text == null) return null;
    try {
      return EnrouteData.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      return null; // Unreadable cache: download again.
    }
  }

  /// Fetches [edition]'s network from the backend and caches it.
  Future<EnrouteData> download(AipSource source, AipEdition edition) async {
    final json = await source.enroute(edition);
    final data = EnrouteData.fromJson(json);
    await storage.writeData(
      _cacheName(source.id, edition.id),
      jsonEncode(json),
    );
    await storage.writeData(_latestName(source.id), edition.id);
    return data;
  }
}
