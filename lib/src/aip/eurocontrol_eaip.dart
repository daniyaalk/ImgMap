import 'dart:async';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'aip_points.dart';
import 'aip_source.dart';

/// Shared logic for AIPs published in the Eurocontrol eAIP format, which
/// many states use: an edition folder with `index-<lang>.html`, an `eAIP/`
/// folder of section pages, and aerodrome charts as PDFs linked from each
/// aerodrome's pages.
///
/// Subclasses say how to find editions and which page lists an aerodrome's
/// charts; the rest is common.
abstract class EurocontrolEaipSource implements AipSource {
  EurocontrolEaipSource({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 45);
  static const _headers = {'User-Agent': 'ImgMap (chart viewer)'};

  /// Pages, relative to the edition's `eAIP/` folder, that link [icao]'s
  /// chart PDFs.
  List<String> chartIndexPages(String icao);

  /// Pages, relative to the edition's `eAIP/` folder, listing points
  /// shared by every aerodrome: en-route waypoints and navaids.
  List<String> sharedPointPages();

  /// Pages listing [icao]'s own points: reference point, terminal
  /// waypoints, aerodrome navaids.
  List<String> aerodromePointPages(String icao);

  final Map<String, Future<PointDirectory>> _sharedPoints = {};

  @override
  Future<PointDirectory> points(String icao, AipEdition edition) async {
    final folder = eaipFolder(edition);
    Future<PointDirectory> load(List<String> pages) async {
      final all = PointDirectory();
      for (final page in pages) {
        try {
          all.addAll(
            parsePointPage(
              await getText(folder.resolve(Uri.encodeComponent(page))),
            ),
          );
        } on AipException catch (e) {
          if (e.statusCode != 404) rethrow;
        }
      }
      return all;
    }

    // En-route lists are large and the same for every airport.
    final shared = _sharedPoints[edition.id] ??= load(sharedPointPages());
    final PointDirectory sharedPoints;
    try {
      sharedPoints = await shared;
    } catch (_) {
      _sharedPoints.remove(edition.id); // Let the next call retry.
      rethrow;
    }
    final result = PointDirectory()
      ..addAll(sharedPoints)
      ..addAll(await load(aerodromePointPages(icao)));
    return result;
  }

  /// The eAIP's table-of-contents page, relative to `eAIP/`.
  String get menuPage => 'Menu-en-GB.html';

  @override
  Future<String> page(AipEdition edition, String name) =>
      getText(eaipFolder(edition).resolve(Uri.encodeComponent(name)));

  @override
  Future<List<String>> routePages(AipEdition edition) async {
    final menu = await page(edition, menuPage);
    // One page per route: `IN-ENR 3.1A474-en-GB.html`, `IN-ENR 3.2Q2-…`.
    final link = RegExp(
      r'''href=['"]([^'"]*ENR 3\.\d+(?:\.\d+)?[A-Z]{1,2}\d+[A-Z]?-[^'"]*\.html)['"]''',
    );
    return {for (final m in link.allMatches(menu)) Uri.decodeFull(m.group(1)!)}
        .toList();
  }

  /// Title and category for a chart, from its file name.
  ({String title, ChartCategory category}) describe(
    String icao,
    String fileName,
  );

  Uri eaipFolder(AipEdition edition) => edition.baseUrl.resolve('eAIP/');

  @override
  Future<List<ChartRef>> charts(String icao, AipEdition edition) async {
    final folder = eaipFolder(edition);
    final seen = <String>{};
    final charts = <ChartRef>[];
    for (final page in chartIndexPages(icao)) {
      final pageUrl = folder.resolve(Uri.encodeComponent(page));
      final String body;
      try {
        body = await getText(pageUrl);
      } on AipException catch (e) {
        // Not every index page exists for every aerodrome.
        if (e.statusCode == 404) continue;
        rethrow;
      }
      for (final a in html.parse(body).querySelectorAll('a[href]')) {
        final href = a.attributes['href']!.trim();
        if (!href.toLowerCase().endsWith('.pdf')) continue;
        final fileName = Uri.decodeFull(href.split('/').last);
        if (!seen.add(fileName)) continue;
        final d = describe(icao, fileName);
        charts.add(
          ChartRef(
            icao: icao,
            fileName: fileName,
            title: d.title,
            category: d.category,
            url: pageUrl.resolve(Uri.encodeFull(href)),
            edition: edition,
          ),
        );
      }
    }
    return charts;
  }

  @override
  Future<Uint8List> download(ChartRef chart) async {
    final response = await _get(chart.url);
    final bytes = response.bodyBytes;
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw AipException('${chart.fileName} is not a PDF.');
    }
    return bytes;
  }

  Future<String> getText(Uri url) async => (await _get(url)).body;

  Future<http.Response> _get(Uri url) async {
    final http.Response response;
    try {
      response = await _client.get(url, headers: _headers).timeout(_timeout);
    } on TimeoutException {
      throw AipException('${url.host} did not respond.');
    } catch (e) {
      throw AipException('Could not reach ${url.host}: $e');
    }
    if (response.statusCode != 200) {
      throw AipException(
        '${url.host} returned ${response.statusCode} for ${url.path}',
        statusCode: response.statusCode,
      );
    }
    return response;
  }
}
