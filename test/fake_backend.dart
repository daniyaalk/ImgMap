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
  // Two sectors stacked over the routes, inside a FIR whose drawn boundary
  // (it follows a border) stops short of them.
  'airspaces': [
    {
      'n': 'Delhi FIR',
      'k': 'fir',
      'rings': [
        [
          [25.0, 70.9],
          [27.0, 82.0],
          [25.0, 79.0],
        ],
      ],
      'approx': true,
      'u': 'UNL',
      'l': 'GND',
      'lft': 0,
      'units': [
        {
          'n': 'Delhi Radio (MWARA)',
          'cs': 'Delhi Radio',
          'h': 'H24',
          'f': [10018, 3467],
        },
      ],
    },
    for (final (name, lower, upper, freqs) in [
      ('Delhi- LDP4', 15500, 25500, [124550, 134075]),
      ('Delhi- UDP4', 25500, 46000, [132975]),
    ])
      {
        'n': name,
        'k': 'cta',
        'rings': [
          [
            [29.0, 76.0],
            [29.0, 77.5],
            [27.0, 77.5],
            [27.0, 76.0],
          ],
        ],
        'u': 'FL ${upper ~/ 100}',
        'uft': upper,
        'l': 'FL ${lower ~/ 100}',
        'lft': lower,
        'cls': 'D',
        'units': [
          {
            'n': 'Delhi ACC',
            'cs': 'Delhi Control/Delhi Radar (RSR)',
            'h': 'H24',
            'f': freqs,
          },
        ],
      },
    // A kind from a newer backend: skipped.
    {'n': 'Somewhere', 'k': 'future', 'units': []},
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
