import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage.dart';

/// Opens the platform default storage: the app support directory.
Future<ChartStorage> openDefaultStorage() async => FileChartStorage(
  Directory(p.join((await getApplicationSupportDirectory()).path, 'imgmap')),
);

/// Metadata in `library.json`, images as plain files in `charts/`.
///
/// Keeping images out of a database avoids row-size limits and lets the
/// image decoder stream straight from disk.
class FileChartStorage implements ChartStorage {
  FileChartStorage(this.root);

  final Directory root;

  Directory get _images => Directory(p.join(root.path, 'charts'));
  File get _index => File(p.join(root.path, 'library.json'));
  File _image(String name) => File(p.join(_images.path, name));

  @override
  Future<String?> readIndex() async =>
      await _index.exists() ? _index.readAsString() : null;

  @override
  Future<void> writeIndex(String json) async {
    await root.create(recursive: true);
    await _writeAtomic(_index, utf8.encode(json));
  }

  @override
  Future<void> writeImage(String name, Uint8List bytes) async {
    await _images.create(recursive: true);
    await _writeAtomic(_image(name), bytes);
  }

  @override
  Future<void> deleteImage(String name) async {
    try {
      await _image(name).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }

  @override
  Future<List<String>> listImages() async {
    if (!await _images.exists()) return [];
    return [
      await for (final e in _images.list())
        if (e is File) p.basename(e.path),
    ];
  }

  @override
  ImageProvider imageProvider(String name) => FileImage(_image(name));

  File _data(String name) => File(p.join(root.path, 'data', name));

  @override
  Future<String?> readData(String name) async {
    final f = _data(name);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> writeData(String name, String contents) async {
    await Directory(p.join(root.path, 'data')).create(recursive: true);
    await _writeAtomic(_data(name), utf8.encode(contents));
  }

  /// Writes to a temp file and renames, so a crash never leaves a
  /// half-written file behind.
  static Future<void> _writeAtomic(File file, Uint8List bytes) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}
