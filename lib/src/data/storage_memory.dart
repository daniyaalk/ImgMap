import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import 'storage.dart';

/// Used on the web, where there is no filesystem: the library lasts until
/// the page is reloaded.
Future<ChartStorage> openDefaultStorage() async => MemoryChartStorage();

class MemoryChartStorage implements ChartStorage {
  String? _index;
  final Map<String, Uint8List> _images = {};

  @override
  Future<String?> readIndex() async => _index;

  @override
  Future<void> writeIndex(String json) async => _index = json;

  @override
  Future<void> writeImage(String name, Uint8List bytes) async =>
      _images[name] = bytes;

  @override
  Future<void> deleteImage(String name) async => _images.remove(name);

  @override
  Future<List<String>> listImages() async => _images.keys.toList();

  final Map<String, String> _data = {};

  @override
  Future<String?> readData(String name) async => _data[name];

  @override
  Future<void> writeData(String name, String contents) async =>
      _data[name] = contents;

  @override
  ImageProvider imageProvider(String name) =>
      MemoryImage(_images[name] ?? Uint8List(0));
}
