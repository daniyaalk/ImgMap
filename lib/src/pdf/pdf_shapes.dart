// Symbol outlines come from PDFium's object API through FFI, which the web
// build doesn't have.
export 'pdf_shapes_stub.dart'
    if (dart.library.ffi) 'pdf_shapes_native.dart'
    show pageShapes;
