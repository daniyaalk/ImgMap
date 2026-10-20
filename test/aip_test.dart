import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imgmap/src/aip/aip_source.dart';
import 'package:imgmap/src/aip/countries/india.dart';
import 'package:imgmap/src/aip/eaip_country.dart';

// Shaped like the AAI home page's sidebar.
const _home = '''
<div class="region-sidebar-first well"><ul>
<li><a href="/">Home</a></li>
<li><a href="https://aim-india.aai.aero/eaip/eaip-v2-10-2026/index-en-GB.html">
  eAIP India AMDT 10/2026 (Effective Date: 29 OCT 2026)</a></li>
<li><a href="https://aim-india.aai.aero/eaip/eaip-v2-09-2026/index-en-GB.html">
  eAIP India AMDT 09/2026 (Effective Date: 01 OCT 2026)</a></li>
<li><a href="/aip-supplements">AIP Supplements</a></li>
</ul></div>
''';

// Shaped like eAIP/AD 2.1VIDP_BChart.html.
const _chartIndex = '''
﻿ <table cellspacing='0'>
<TR><td></td><td><A class='graphic-box '><IMG src="../images/application_pdf.png"/><A href='VIDP-ADC.pdf' target='eAISContent'>  VIDP-ADC.pdf</A></td></TR>
<TR><td></td><td><A class='graphic-box '><A href='VIDP-ADC-HOT SPOT.pdf'>VIDP-ADC-HOT SPOT.pdf</A></td></TR>
<TR><td></td><td><A href='VIDP-SID-RNAV1-GNSS-RWY-09-AKRIB-DUDUM-6-E.pdf'>x</A></td></TR>
<TR><td></td><td><A href='VIDP-SID-RNAV1-GNSS-RWY-09-AKRIB-DUDUM-6-E-TABLE.pdf'>x</A></td></TR>
<TR><td></td><td><A href='VIDP-ADC.pdf'>duplicate</A></td></TR>
</table>
''';

void main() {
  test('finds editions and their effective dates', () {
    final editions = parseEditions(_home, india.home);
    expect(editions.map((e) => e.name), ['AMDT 10/2026', 'AMDT 09/2026']);
    expect(editions.last.effective, DateTime.utc(2026, 10, 1));
    expect(
      editions.last.baseUrl.toString(),
      'https://aim-india.aai.aero/eaip/eaip-v2-09-2026/',
    );
    // On 20 Oct the September amendment is in force, not the next one.
    expect(
      currentEdition(editions, DateTime.utc(2026, 10, 20))!.name,
      'AMDT 09/2026',
    );
    expect(
      currentEdition(editions, DateTime.utc(2026, 10, 29))!.name,
      'AMDT 10/2026',
    );
  });

  test('classifies charts by file name', () {
    ChartCategory c(String f) => describeIndianChart('VIDP', f).category;
    expect(c('VIDP-ADC.pdf'), ChartCategory.aerodrome);
    expect(c('VIDP-PDC-APN-II.pdf'), ChartCategory.parking);
    expect(
      c('VIDP-SID-RNAV1-GNSS-RWY-09-AKRIB-DUDUM-6-E.pdf'),
      ChartCategory.departure,
    );
    expect(
      c('VIDP-SID-RNAV1-GNSS-RWY-09-AKRIB-DUDUM-6-E-TABLE.pdf'),
      ChartCategory.tabular,
    );
    expect(
      c('VIDP-STAR-RNAV1-GNSS-RWY-27-28-29R-29L-BAVOX-POSIG-6-A-B-C-D.pdf'),
      ChartCategory.arrival,
    );
    expect(c('VIDP-ILS-LOC-RWY-27.pdf'), ChartCategory.approach);
    expect(c('VIDP-RNP-Y-RWY-10-CODING-1.pdf'), ChartCategory.tabular);
    expect(c('VIDP-ILS-CAT-III-CRTC-SENS-RWY-11R.pdf'), ChartCategory.ground);
    expect(c('VIDP-AOCTA-RWY-09.pdf'), ChartCategory.terrain);
    expect(
      describeIndianChart('VIDP', 'VIDP-ILS-LOC-RWY-27.pdf').title,
      'ILS LOC RWY 27',
    );
  });

  test('covers Indian ICAO codes only', () {
    final s = ConfiguredEaipSource(india);
    for (final icao in ['VIDP', 'VABB', 'VOBL', 'VECC']) {
      expect(s.covers(icao), isTrue, reason: icao);
    }
    for (final icao in ['VTBS', 'OPKC', 'EGLL', 'VA']) {
      expect(s.covers(icao), isFalse, reason: icao);
    }
    expect(s.country, 'India');
    expect(s.countryCode, 'IN');
    expect(s.sharedPointPages(), [
      'IN-ENR 4.4-en-GB.html',
      'IN-ENR 4.1-en-GB.html',
    ]);
    expect(s.aerodromePointPages('VIDP'), ['IN-AD 2.1VIDP-en-GB.html']);
  });

  test('lists and downloads charts from the eAIP', () async {
    final requested = <Uri>[];
    final client = MockClient((req) async {
      requested.add(req.url);
      final path = Uri.decodeComponent(req.url.path);
      if (path.endsWith('AD 2.1VIDP_BChart.html')) {
        return http.Response.bytes(utf8.encode(_chartIndex), 200);
      }
      if (path.endsWith('VIDP-ADC-HOT SPOT.pdf')) {
        return http.Response.bytes('%PDF-1.7 fake'.codeUnits, 200);
      }
      return http.Response('not found', 404);
    });
    final source = ConfiguredEaipSource(india, client: client);
    final edition = parseEditions(_home, india.home).last;

    final charts = await source.charts('VIDP', edition);
    expect(charts.map((c) => c.fileName), [
      'VIDP-ADC.pdf',
      'VIDP-ADC-HOT SPOT.pdf',
      'VIDP-SID-RNAV1-GNSS-RWY-09-AKRIB-DUDUM-6-E.pdf',
      'VIDP-SID-RNAV1-GNSS-RWY-09-AKRIB-DUDUM-6-E-TABLE.pdf',
    ]);
    final hotSpot = charts[1];
    expect(
      hotSpot.url.toString(),
      'https://aim-india.aai.aero/eaip/eaip-v2-09-2026/eAIP/VIDP-ADC-HOT%20SPOT.pdf',
    );

    final bytes = await source.download(hotSpot);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    await expectLater(
      source.download(charts.first),
      throwsA(isA<AipException>()),
    );

    // A server or network failure is an error, not "no charts".
    final down = ConfiguredEaipSource(
      india,
      client: MockClient((_) async => http.Response('busy', 503)),
    );
    await expectLater(
      down.charts('VIDP', edition),
      throwsA(isA<AipException>()),
    );
  });
}
