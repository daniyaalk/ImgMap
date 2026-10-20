import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

/// Where the chart library's bytes live. The store above it deals only in
/// names, so it runs unchanged on platforms with and without a filesystem.
abstract class ChartStorage {
  /// The JSON index, or null if nothing has been saved yet.
  Future<String?> readIndex();

  /// Replaces the index. Must never leave a partially written index.
  Future<void> writeIndex(String json);

  Future<void> writeImage(String name, Uint8List bytes);
  Future<void> deleteImage(String name);
  Future<List<String>> listImages();

  /// Small data files (cached AIP data), by name; null if absent.
  Future<String?> readData(String name);
  Future<void> writeData(String name, String contents);

  /// An image provider that loads [name] without copying it into Dart.
  ImageProvider imageProvider(String name);
}
