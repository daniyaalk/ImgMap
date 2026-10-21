import 'dart:typed_data';

import 'package:imgmap/src/aip/aip_source.dart';
import 'package:imgmap/src/geo/lat_lng.dart';

final edition = AipEdition(
  id: '2026-09',
  name: 'AMDT 09/2026',
  effective: DateTime.utc(2026, 10, 1),
);

/// An airway network in the backend's enroute.json form: A474 and Q2 share
/// DPN–DUDUM–IGOLU, and Q2's second leg publishes a wrong length (99 NM
/// where the points are 20).
Map<String, dynamic> enrouteJson({String source = 'in-aai'}) => {
  'version': 1,
  'source': source,
  'edition': edition.id,
  'editionName': edition.name,
  'points': [
    {
      'n': 'DELHI DVOR DVOR/DME',
      'i': 'DPN',
      'lat': 28.5669,
      'lon': 77.0936,
      'k': 'navaid',
      'c': true,
    },
    {'n': 'DUDUM', 'lat': 27.8003, 'lon': 76.5225, 'k': 'waypoint', 'c': true},
    {'n': 'IGOLU', 'lat': 27.5231, 'lon': 76.3139, 'k': 'waypoint'},
  ],
  'routes': [
    {
      'id': 'A474',
      'seg': [
        {
          'f': 0,
          't': 1,
          'trk': 213,
          'd': 55.0,
          'u': 'FL 460',
          'l': 'FL 75',
          'cls': 'D',
          'moca': 3200,
          'w': 20.0,
        },
        {
          'f': 1,
          't': 2,
          'trk': 213,
          'd': 20.0,
          'u': 'FL 460',
          'l': 'FL 75',
          'cls': 'D',
          'moca': 4100,
          'w': 20.0,
        },
      ],
    },
    {
      'id': 'Q2',
      'spec': 'RNAV 5',
      'seg': [
        {'f': 0, 't': 1, 'trk': 213, 'd': 55.0},
        {'f': 1, 't': 2, 'trk': 213, 'd': 99.0},
      ],
      // A field from a newer backend: ignored.
      'future': 'ignored',
    },
  ],
  'unread': <String>[],
};

/// A backend source answering from memory.
class FakeSource implements AipSource {
  FakeSource({
    this.id = 'in-aai',
    this.country = 'India',
    this.countryCode = 'IN',
    this.chartList = const [],
    this.pdf,
  });

  @override
  final String id;
  @override
  final String country;
  @override
  final String countryCode;
  List<ChartRef> chartList;
  final Uint8List? pdf;

  @override
  String get displayName => 'AIP $country';
  @override
  LatLng get mapCenter => const LatLng(22, 80);
  @override
  bool covers(String icao) => icao.startsWith('V');
  @override
  Future<List<AipEdition>> editions() async => [edition];
  @override
  Future<List<ChartRef>> charts(String icao, AipEdition e) async => [
    for (final c in chartList)
      if (c.icao == icao) c,
  ];
  @override
  Future<Uint8List> download(ChartRef c) async => pdf ?? Uint8List(0);
  @override
  Future<Map<String, dynamic>> enroute(AipEdition e) async =>
      enrouteJson(source: id);
}
