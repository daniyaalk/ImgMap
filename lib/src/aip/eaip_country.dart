import '../geo/lat_lng.dart';
import 'aip_source.dart';
import 'eurocontrol_eaip.dart';

/// Everything that differs between countries publishing a Eurocontrol-style
/// eAIP. Adding a country means writing one of these and listing it in
/// `aip_countries.dart`; no other code changes.
class EaipCountry {
  const EaipCountry({
    required this.id,
    required this.country,
    required this.countryCode,
    required this.authority,
    required this.icaoPrefixes,
    required this.home,
    required this.findEditions,
    required this.mapCenter,
    this.pagePrefix = '',
    this.language = 'en-GB',
    this.chartIndexPages = _noChartIndex,
    this.describeChart = describeChartByName,
  });

  /// Stable id stored with downloaded data, e.g. `in-aai`.
  final String id;

  /// e.g. `India`.
  final String country;

  /// ISO 3166-1 alpha-2, e.g. `IN`.
  final String countryCode;

  /// The publishing service, e.g. `AAI`.
  final String authority;

  /// ICAO location indicator prefixes of the country's aerodromes, e.g.
  /// `VA`, `VE`, `VI`, `VO` for India.
  final List<String> icaoPrefixes;

  /// Where editions are announced.
  final Uri home;

  /// Reads the published editions, newest first. [get] fetches a page.
  final Future<List<AipEdition>> Function(Future<String> Function(Uri) get)
  findEditions;

  /// Roughly the middle of the country, for the first view of its map.
  final LatLng mapCenter;

  /// Prefix of the eAIP's section page names, e.g. `IN-` in
  /// `IN-ENR 4.4-en-GB.html`.
  final String pagePrefix;

  /// Language suffix of page names.
  final String language;

  /// Pages, relative to `eAIP/`, linking an aerodrome's chart PDFs.
  final List<String> Function(String icao) chartIndexPages;

  /// Title and category for a chart, from its file name.
  final ({String title, ChartCategory category}) Function(
    String icao,
    String fileName,
  )
  describeChart;

  static List<String> _noChartIndex(String icao) => const [];
}

/// An AIP source for any [EaipCountry].
class ConfiguredEaipSource extends EurocontrolEaipSource {
  ConfiguredEaipSource(this.config, {super.client});

  final EaipCountry config;

  @override
  String get id => config.id;

  @override
  String get displayName => 'AIP ${config.country} (${config.authority})';

  @override
  String get country => config.country;

  @override
  String get countryCode => config.countryCode;

  @override
  LatLng get mapCenter => config.mapCenter;

  @override
  bool covers(String icao) =>
      icao.length == 4 && config.icaoPrefixes.any(icao.startsWith);

  @override
  Future<List<AipEdition>> editions() => config.findEditions(getText);

  String _page(String section) =>
      '${config.pagePrefix}$section-${config.language}.html';

  @override
  String get menuPage => 'Menu-${config.language}.html';

  @override
  List<String> sharedPointPages() => [_page('ENR 4.4'), _page('ENR 4.1')];

  @override
  List<String> aerodromePointPages(String icao) => [_page('AD 2.1$icao')];

  @override
  List<String> chartIndexPages(String icao) => config.chartIndexPages(icao);

  @override
  ({String title, ChartCategory category}) describe(
    String icao,
    String fileName,
  ) => config.describeChart(icao, fileName);
}

/// A fallback chart description from common ICAO chart abbreviations.
({String title, ChartCategory category}) describeChartByName(
  String icao,
  String fileName,
) {
  var stem = fileName.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
  if (stem.toUpperCase().startsWith('$icao-')) {
    stem = stem.substring(icao.length + 1);
  }
  final u = stem.toUpperCase();
  bool has(String pattern) => RegExp(pattern).hasMatch(u);
  final ChartCategory category;
  if (has(r'(^|[-_ ])(TABLE|CODING)([-_ ]|\d|$)')) {
    category = ChartCategory.tabular;
  } else if (has(r'(^|[-_ ])SID\b')) {
    category = ChartCategory.departure;
  } else if (has(r'(^|[-_ ])STAR\b')) {
    category = ChartCategory.arrival;
  } else if (has(r'(^|[-_ ])(ADC|AD[-_ ]?CHART)\b')) {
    category = ChartCategory.aerodrome;
  } else if (has(r'(^|[-_ ])(PDC|APDC)\b')) {
    category = ChartCategory.parking;
  } else if (has(r'(^|[-_ ])(GMC|TWY|LVP)\b')) {
    category = ChartCategory.ground;
  } else if (has(r'(^|[-_ ])(AOC|PATC|TATFP|ATCSMAC|MSA)')) {
    category = ChartCategory.terrain;
  } else if (has(r'(^|[-_ ])(IAC|ILS|LOC|VOR|NDB|RNP|RNAV|GLS|DME|VAC)')) {
    category = ChartCategory.approach;
  } else {
    category = ChartCategory.other;
  }
  return (title: stem.replaceAll(RegExp('[-_]'), ' '), category: category);
}
