import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:uuid/uuid.dart';

import 'default_storage.dart';
import 'models.dart';
import 'storage.dart';

/// An image copied into the store but not yet attached to a saved chart.
class ImportedImage {
  const ImportedImage(this.fileName, this.size, {this.downscaled = false});
  final String fileName;
  final ui.Size size;

  /// True if the source was larger than [ChartStore.maxImageDimension].
  final bool downscaled;
}

/// The airports and charts library, backed by a [ChartStorage].
class ChartStore extends ChangeNotifier {
  ChartStore._(this._storage);

  /// Longest image side kept on import. Bigger images are downscaled so the
  /// decoded bitmap fits comfortably in memory and in a GPU texture.
  static const int maxImageDimension = 6000;

  static const int _schemaVersion = 1;
  static const _uuid = Uuid();

  final ChartStorage _storage;
  final Map<String, Airport> _airports = {};
  final Map<String, ChartRecord> _charts = {};

  /// The country whose airways the en-route map shows, by AIP source id.
  String? _enrouteSourceId;

  String? get enrouteSourceId => _enrouteSourceId;

  Future<void> setEnrouteSourceId(String id) async {
    _enrouteSourceId = id;
    await _commit();
  }

  Future<void> _pendingWrite = Future.value();

  /// Opens the store on [storage], defaulting to the platform's own.
  static Future<ChartStore> open({ChartStorage? storage}) async {
    final store = ChartStore._(storage ?? await openDefaultStorage());
    await store._load();
    await store._removeOrphanImages();
    return store;
  }

  List<Airport> get airports =>
      _airports.values.toList()..sort((a, b) => a.icao.compareTo(b.icao));

  Airport? airport(String icao) => _airports[icao];

  List<ChartRecord> chartsFor(String icao) =>
      _charts.values.where((c) => c.airportIcao == icao).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Charts that can be used as a moving map: those with a georeference.
  List<ChartRecord> usableChartsFor(String icao) =>
      chartsFor(icao).where((c) => c.georeference != null).toList();

  ChartRecord? chart(String id) => _charts[id];

  /// The stored copy of an AIP chart, from any edition.
  ChartRecord? chartFromSource(String sourceId, String icao, String fileName) {
    for (final c in _charts.values) {
      final s = c.source;
      if (s != null &&
          c.airportIcao == icao &&
          s.sourceId == sourceId &&
          s.fileName == fileName) {
        return c;
      }
    }
    return null;
  }

  /// Storage for cached data beyond charts (the en-route network).
  ChartStorage get storage => _storage;

  ImageProvider imageFor(String fileName) => _storage.imageProvider(fileName);

  Future<void> addAirport(Airport airport) async {
    if (_airports.containsKey(airport.icao)) {
      throw StateError('${airport.icao} is already in your list');
    }
    _airports[airport.icao] = airport;
    await _commit();
  }

  Future<void> updateAirport(Airport airport) async {
    _airports[airport.icao] = airport;
    await _commit();
  }

  Future<void> deleteAirport(String icao) async {
    final charts = chartsFor(icao);
    _airports.remove(icao);
    for (final c in charts) {
      _charts.remove(c.id);
    }
    await _commit();
    for (final c in charts) {
      await _storage.deleteImage(c.imageFile);
    }
  }

  /// Copies [bytes] into the store, downscaling if needed. Call
  /// [discardImage] if the chart is never saved; otherwise the next
  /// [open] cleans it up.
  Future<ImportedImage> importImage(Uint8List bytes, String extension) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      buffer.dispose();
      throw const FormatException('That file is not a supported image.');
    }
    final width = descriptor.width, height = descriptor.height;
    final longest = width > height ? width : height;
    final id = _uuid.v4();

    if (longest <= maxImageDimension) {
      descriptor.dispose();
      buffer.dispose();
      final ext = extension.isEmpty ? '' : '.${extension.toLowerCase()}';
      final name = '$id$ext';
      await _storage.writeImage(name, bytes);
      return ImportedImage(name, ui.Size(width.toDouble(), height.toDouble()));
    }

    final scale = maxImageDimension / longest;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (width * scale).round(),
      targetHeight: (height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final size = ui.Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (png == null) throw const FormatException('Could not process image.');

    final name = '$id.png';
    await _storage.writeImage(name, png.buffer.asUint8List());
    return ImportedImage(name, size, downscaled: true);
  }

  Future<void> discardImage(String fileName) async {
    if (_charts.values.any((c) => c.imageFile == fileName)) return;
    await _storage.deleteImage(fileName);
  }

  String newChartId() => _uuid.v4();

  Future<void> saveChart(ChartRecord chart) async {
    if (!_airports.containsKey(chart.airportIcao)) {
      throw StateError('Unknown airport ${chart.airportIcao}');
    }
    _charts[chart.id] = chart;
    await _commit();
  }

  Future<void> deleteChart(String id) async {
    final chart = _charts.remove(id);
    if (chart == null) return;
    await _commit();
    await _storage.deleteImage(chart.imageFile);
  }

  Future<void> _load() async {
    final text = await _storage.readIndex();
    if (text == null) return;
    final json = jsonDecode(text) as Map<String, dynamic>;
    for (final a in json['airports'] as List) {
      final airport = Airport.fromJson(a as Map<String, dynamic>);
      _airports[airport.icao] = airport;
    }
    for (final c in json['charts'] as List) {
      final chart = ChartRecord.fromJson(c as Map<String, dynamic>);
      _charts[chart.id] = chart;
    }
    final settings = json['settings'] as Map<String, dynamic>? ?? const {};
    _enrouteSourceId = settings['enrouteSource'] as String?;
  }

  Future<void> _removeOrphanImages() async {
    final used = _charts.values.map((c) => c.imageFile).toSet();
    for (final name in await _storage.listImages()) {
      if (!used.contains(name)) await _storage.deleteImage(name);
    }
  }

  Future<void> _commit() {
    notifyListeners();
    final data = jsonEncode({
      'version': _schemaVersion,
      'airports': [for (final a in _airports.values) a.toJson()],
      'charts': [for (final c in _charts.values) c.toJson()],
      'settings': {
        if (_enrouteSourceId != null) 'enrouteSource': _enrouteSourceId,
      },
    });
    // Chain writes so a slow write can never land after a newer one.
    return _pendingWrite = _pendingWrite.then((_) => _storage.writeIndex(data));
  }
}
