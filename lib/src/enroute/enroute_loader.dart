import 'dart:async';
import 'dart:convert';

import '../aip/aip_source.dart';
import '../data/storage.dart';
import 'enroute_model.dart';
import 'route_parser.dart';

/// Builds the airway network from an AIP's route pages, and caches it.
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

  /// Fetches every route page of [edition] (a few hundred), a few at a
  /// time, then caches the result.
  Future<EnrouteData> download(
    AipSource source,
    AipEdition edition, {
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final pages = await source.routePages(edition);
    if (pages.isEmpty) throw AipException('No route pages found.');
    final parsed = <List<ParsedRoute>>[];
    final unread = <String>[];
    var done = 0;
    var next = 0;

    Future<void> worker() async {
      while (next < pages.length) {
        if (cancelled?.call() ?? false) return;
        final name = pages[next++];
        try {
          parsed.add(parseRoutePage(await source.page(edition, name)));
        } on Object {
          unread.add(name);
        }
        onProgress?.call(++done, pages.length);
      }
    }

    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
    if (cancelled?.call() ?? false) throw AipException('Cancelled.');

    final data = build(source.id, edition, [
      for (final p in parsed) ...p,
    ], unread);
    await storage.writeData(
      _cacheName(source.id, edition.id),
      jsonEncode(data.toJson()),
    );
    await storage.writeData(_latestName(source.id), edition.id);
    return data;
  }

  /// Links parsed routes into one network: a point shared by several
  /// routes becomes one point.
  static EnrouteData build(
    String sourceId,
    AipEdition edition,
    List<ParsedRoute> parsed,
    List<String> unread,
  ) {
    final points = <String, EnroutePoint>{};
    EnroutePoint point(ParsedPoint p) {
      final key =
          '${p.ident ?? p.name}|${p.position.latitude.toStringAsFixed(4)}|'
          '${p.position.longitude.toStringAsFixed(4)}';
      final existing = points[key];
      // Compulsory on any route makes it compulsory to draw.
      if (existing != null && (existing.compulsory || !p.compulsory)) {
        return existing;
      }
      return points[key] = EnroutePoint(
        name: p.name,
        ident: p.ident,
        position: p.position,
        kind: p.kind,
        compulsory: p.compulsory || (existing?.compulsory ?? false),
      );
    }

    // Two passes so every route refers to the final, merged points.
    for (final r in parsed) {
      r.points.forEach(point);
    }
    final routes = [
      for (final r in parsed)
        AirRoute(
          designator: r.designator,
          navigationSpec: r.navigationSpec,
          segments: [
            for (var i = 0; i + 1 < r.points.length; i++)
              RouteSegment(
                from: point(r.points[i]),
                to: point(r.points[i + 1]),
                trackMagnetic: _leg(r, i)?.trackMagnetic,
                distanceNm: _leg(r, i)?.distanceNm,
                upper: _leg(r, i)?.upper,
                lower: _leg(r, i)?.lower,
                airspaceClass: _leg(r, i)?.airspaceClass,
                mocaFt: _leg(r, i)?.mocaFt,
                widthNm: _leg(r, i)?.widthNm,
              ),
          ],
        ),
    ];
    return EnrouteData(
      sourceId: sourceId,
      editionId: edition.id,
      editionName: edition.name,
      points: points.values.toList(),
      routes: routes,
      unreadPages: unread,
    );
  }

  static ParsedLeg? _leg(ParsedRoute r, int i) =>
      i < r.legs.length ? r.legs[i] : null;
}
