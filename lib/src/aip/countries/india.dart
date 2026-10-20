import 'package:html/parser.dart' as html;

import '../../geo/lat_lng.dart';
import '../aip_source.dart';
import '../eaip_country.dart';

/// AIP India, published by the Airports Authority of India at
/// aim-india.aai.aero.
///
/// The home page links each edition as `eaip/eaip-v2-MM-YYYY/` next to text
/// like "eAIP India AMDT 09/2026 (Effective Date: 01 OCT 2026)". Section
/// pages are named `IN-ENR 4.4-en-GB.html`; each aerodrome's charts are
/// listed in `eAIP/AD 2.1<ICAO>_BChart.html`.
final _home = Uri.parse('https://aim-india.aai.aero/');

final india = EaipCountry(
  id: 'in-aai',
  country: 'India',
  countryCode: 'IN',
  authority: 'AAI',
  icaoPrefixes: const ['VA', 'VE', 'VI', 'VO'],
  home: _home,
  findEditions: (get) async => parseEditions(await get(_home), _home),
  mapCenter: const LatLng(22, 80),
  pagePrefix: 'IN-',
  chartIndexPages: (icao) => [
    'AD 2.1${icao}_BChart.html',
    'AD 2.1${icao}_TChart.html',
  ],
  describeChart: describeIndianChart,
);

const _months = {
  'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6, //
  'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
};

/// Finds editions in the AAI home page, newest first.
List<AipEdition> parseEditions(String homePage, Uri home) {
  final doc = html.parse(homePage);
  final byId = <String, AipEdition>{};
  final link = RegExp(r'eaip/(eaip-v2-(\d{2})-(\d{4}))/');
  final date = RegExp(
    r'Effective Date:\s*(\d{1,2})\s+([A-Z]{3})\s+(\d{4})',
    caseSensitive: false,
  );
  for (final a in doc.querySelectorAll('a[href]')) {
    final m = link.firstMatch(a.attributes['href']!);
    if (m == null) continue;
    // The date sits in the link text or right after it.
    final context = '${a.text} ${a.parent?.text ?? ''}'.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final number = '${m.group(2)}/${m.group(3)}';
    final d =
        RegExp(
          'AMDT\\s*${RegExp.escape(number)}\\s*\\(${date.pattern}',
          caseSensitive: false,
        ).firstMatch(context) ??
        date.firstMatch(a.text);
    if (d == null) continue;
    final n = d.groupCount;
    final month = _months[d.group(n - 1)!.toUpperCase()];
    if (month == null) continue;
    final id = '${m.group(3)}-${m.group(2)}';
    byId[id] = AipEdition(
      id: id,
      name: 'AMDT $number',
      effective: DateTime.utc(
        int.parse(d.group(n)!),
        month,
        int.parse(d.group(n - 2)!),
      ),
      baseUrl: home.resolve('eaip/${m.group(1)}/'),
    );
  }
  return byId.values.toList()
    ..sort((a, b) => b.effective.compareTo(a.effective));
}

/// AAI file names read like `VIDP-SID-RNAV1-GNSS-RWY-09-AKRIB-DUDUM-6-E.pdf`.
({String title, ChartCategory category}) describeIndianChart(
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
  if (has(r'(^|-)(TABLE|CODING)(-|\d|$)')) {
    category = ChartCategory.tabular;
  } else if (has(r'^SID\b')) {
    category = ChartCategory.departure;
  } else if (has(r'^STAR\b')) {
    category = ChartCategory.arrival;
  } else if (has(r'^ADC\b')) {
    category = ChartCategory.aerodrome;
  } else if (has(r'^PDC\b')) {
    category = ChartCategory.parking;
  } else if (has(r'^(TWY|LVP|ILS-CAT-[I]+-CRTC)')) {
    category = ChartCategory.ground;
  } else if (has(r'^(AOC|PATC|TATFP|ATC-SMAC|MSA)')) {
    category = ChartCategory.terrain;
  } else if (has(r'^(ILS|LOC|VOR|NDB|RNP|RNAV|GLS|DME|VISUAL)')) {
    category = ChartCategory.approach;
  } else if (has(r'^(TORA|LDA|ASDA|TODA)')) {
    category = ChartCategory.tabular;
  } else {
    category = ChartCategory.other;
  }
  return (title: stem.replaceAll('-', ' '), category: category);
}
