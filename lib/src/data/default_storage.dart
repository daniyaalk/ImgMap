// Picks the filesystem backend where dart:io exists, memory otherwise (web).
export 'storage_memory.dart'
    if (dart.library.io) 'storage_io.dart'
    show openDefaultStorage;
