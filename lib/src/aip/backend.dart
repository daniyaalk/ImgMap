import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../geo/lat_lng.dart';
import 'aip_source.dart';

/// Where the backend publishes (see the imgmap-backend repository).
/// Override at build time, e.g. for a local test server:
/// `--dart-define=IMGMAP_BACKEND=http://localhost:8766/`.
const backendBaseUrl = String.fromEnvironment(
  'IMGMAP_BACKEND',
  defaultValue: 'https://charts.daniyaalkhan.com/',
);

/// Reads the backend's static files. The app never contacts an eAIP: the
/// backend reads each once per AIRAC cycle, however many people use the
/// app.
class Backend {
  Backend({Uri? base, http.Client? client})
    : base = base ?? Uri.parse(backendBaseUrl),
      _client = client ?? http.Client();

  final Uri base;
  final http.Client _client;

  static const _timeout = Duration(seconds: 45);

  bool get configured => base.hasScheme;

  Future<Map<String, dynamic>> json(String path) async {
    final body = await _get(path);
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, dynamic>) {
      throw AipException('Unexpected data at $path.');
    }
    return decoded;
  }

  Future<Uint8List> bytes(String path) => _get(path);

  Future<Uint8List> _get(String path) async {
    if (!configured) throw AipException('No chart server is configured.');
    final url = base.resolve(path);
    final http.Response r;
    try {
      r = await _client.get(url).timeout(_timeout);
    } on TimeoutException {
      throw AipException('The chart server did not respond.');
    } catch (e) {
      throw AipException('Could not reach the chart server: $e');
    }
    if (r.statusCode != 200) {
      throw AipException(
        'The chart server returned ${r.statusCode} for $path',
        statusCode: r.statusCode,
      );
    }
    return r.bodyBytes;
  }

  /// Countries the backend publishes.
  Future<List<BackendSource>> countries() async {
    final j = await json('v1/countries.json');
    return [
      for (final c in j['countries'] as List)
        if (BackendCountry.fromJson(c as Map<String, dynamic>) case final c?)
          BackendSource(this, c),
    ];
  }
}

class BackendCountry {
  const BackendCountry({
    required this.id,
    required this.country,
    required this.countryCode,
    required this.authority,
    required this.icaoPrefixes,
    required this.mapCenter,
  });

  final String id, country, countryCode, authority;
  final List<String> icaoPrefixes;
  final LatLng mapCenter;

  static BackendCountry? fromJson(Map<String, dynamic> j) {
    try {
      final c = j['mapCenter'] as Map<String, dynamic>;
      return BackendCountry(
        id: j['id'] as String,
        country: j['country'] as String,
        countryCode: j['countryCode'] as String,
        authority: j['authority'] as String,
        icaoPrefixes: [for (final p in j['icaoPrefixes'] as List) p as String],
        mapCenter: LatLng(
          (c['lat'] as num).toDouble(),
          (c['lon'] as num).toDouble(),
        ),
      );
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'country': country,
    'countryCode': countryCode,
    'authority': authority,
    'icaoPrefixes': icaoPrefixes,
    'mapCenter': {'lat': mapCenter.latitude, 'lon': mapCenter.longitude},
  };
}

/// One country's AIP as published by the backend.
class BackendSource implements AipSource {
  BackendSource(this.backend, this.info);

  final Backend backend;
  final BackendCountry info;

  @override
  String get id => info.id;
  @override
  String get displayName => 'AIP ${info.country} (${info.authority})';
  @override
  String get country => info.country;
  @override
  String get countryCode => info.countryCode;
  @override
  LatLng get mapCenter => info.mapCenter;

  @override
  bool covers(String icao) =>
      icao.length == 4 && info.icaoPrefixes.any(icao.startsWith);

  @override
  Future<List<AipEdition>> editions() async {
    final j = await backend.json('v1/$id/editions.json');
    return [
      for (final e in j['editions'] as List)
        AipEdition.fromJson(e as Map<String, dynamic>),
    ]..sort((a, b) => b.effective.compareTo(a.effective));
  }

  @override
  Future<List<ChartRef>> charts(String icao, AipEdition edition) async {
    final Map<String, dynamic> j;
    try {
      j = await backend.json('v1/$id/${edition.id}/ad/$icao.json');
    } on AipException catch (e) {
      if (e.statusCode == 404) return const []; // No charts published.
      rethrow;
    }
    return [
      for (final c in j['charts'] as List)
        ?_chart(c as Map<String, dynamic>, icao, edition),
    ];
  }

  static ChartRef? _chart(
    Map<String, dynamic> c,
    String icao,
    AipEdition edition,
  ) {
    final file = c['file'], title = c['title'];
    if (file is! String || title is! String) return null;
    final pdf = c['pdf'] as Map<String, dynamic>?;
    // An unknown category is skipped rather than guessed.
    final category = ChartCategory.byNameOrNull(c['category'] as String?);
    return ChartRef(
      icao: icao,
      fileName: file,
      title: title,
      category: category ?? ChartCategory.other,
      edition: edition,
      pdfPath: pdf?['path'] as String?,
      sha256: pdf?['sha256'] as String?,
      bytes: (pdf?['bytes'] as num?)?.toInt(),
      georef: category == null
          ? null
          : ChartGeoref.fromJson(c['georef'] as Map<String, dynamic>?),
      unusableReason: c['unusable'] as String?,
    );
  }

  @override
  Future<Uint8List> download(ChartRef chart) async {
    final path = chart.pdfPath;
    if (path == null) throw AipException('${chart.title} has no PDF.');
    final data = await backend.bytes(path);
    if (chart.sha256 != null &&
        sha256.convert(data).toString() != chart.sha256) {
      throw AipException('${chart.title} arrived damaged; try again.');
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> enroute(AipEdition edition) =>
      backend.json('v1/$id/${edition.id}/enroute.json');
}
