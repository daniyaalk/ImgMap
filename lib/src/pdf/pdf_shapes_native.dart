import 'dart:ffi' as ffi;
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx/pdfrx.dart';

pdfium.PDFium? _lib;
pdfium.PDFium get _pdfium =>
    _lib ??= pdfium.getPdfium(modulePath: Pdfrx.pdfiumModulePath);

/// Bounding boxes, in pixels of [page] rendered at [renderSize], of the
/// small vector drawings on it: map symbols such as waypoint triangles,
/// navaid roses and runway thresholds. Text and images are left out, and
/// form groups are looked into.
Future<List<Rect>> pageShapes(
  PdfDocument doc,
  PdfPage page,
  Size renderSize, {
  double maxPoints = 24,
}) {
  return doc.useNativeDocumentHandle((handle) {
    final lib = _pdfium;
    final document = pdfium.FPDF_DOCUMENT.fromAddress(handle);
    final p = lib.FPDF_LoadPage(document, page.pageNumber - 1);
    if (p == ffi.nullptr) return const <Rect>[];
    final shapes = <_PdfBox>[];
    final arena = Arena();
    try {
      final l = arena<ffi.Float>(), b = arena<ffi.Float>();
      final r = arena<ffi.Float>(), t = arena<ffi.Float>();
      final m = arena<pdfium.FS_MATRIX>();

      void visit(pdfium.FPDF_PAGEOBJECT obj, _Affine toPage) {
        final type = lib.FPDFPageObj_GetType(obj);
        if (type != pdfium.FPDF_PAGEOBJ_PATH &&
            type != pdfium.FPDF_PAGEOBJ_FORM) {
          return;
        }
        if (lib.FPDFPageObj_GetBounds(obj, l, b, r, t) == 0) return;
        final box = toPage.box(l.value, b.value, r.value, t.value);
        final w = box.r - box.l, h = box.t - box.b;
        final small = w <= maxPoints && h <= maxPoints && w + h >= 2;
        if (type == pdfium.FPDF_PAGEOBJ_PATH) {
          if (small) shapes.add(box);
          return;
        }
        // A form's children are in its own space; its matrix maps them to
        // the parent's.
        if (small) shapes.add(box);
        if (lib.FPDFPageObj_GetMatrix(obj, m) == 0) return;
        final inner = toPage.then(
          _Affine(m.ref.a, m.ref.b, m.ref.c, m.ref.d, m.ref.e, m.ref.f),
        );
        final n = lib.FPDFFormObj_CountObjects(obj);
        for (var i = 0; i < n; i++) {
          visit(lib.FPDFFormObj_GetObject(obj, i), inner);
        }
      }

      final n = lib.FPDFPage_CountObjects(p);
      for (var i = 0; i < n; i++) {
        visit(lib.FPDFPage_GetObject(p, i), _Affine.identity);
      }
    } finally {
      arena.releaseAll();
      lib.FPDF_ClosePage(p);
    }
    return [
      for (final s in shapes)
        PdfRect(
          s.l,
          s.t,
          s.r,
          s.b,
        ).toRect(page: page, scaledPageSize: renderSize),
    ];
  });
}

/// A 2-D affine transform in PDF's `[a b c d e f]` form.
class _Affine {
  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  final double a, b, c, d, e, f;

  static const identity = _Affine(1, 0, 0, 1, 0, 0);

  /// This transform applied after [inner].
  _Affine then(_Affine inner) => _Affine(
    inner.a * a + inner.b * c,
    inner.a * b + inner.b * d,
    inner.c * a + inner.d * c,
    inner.c * b + inner.d * d,
    inner.e * a + inner.f * c + e,
    inner.e * b + inner.f * d + f,
  );

  /// Bounding box of the transformed rectangle.
  _PdfBox box(double l, double bt, double r, double t) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final (x, y) in [(l, bt), (r, bt), (l, t), (r, t)]) {
      final px = a * x + c * y + e, py = b * x + d * y + f;
      if (px < minX) minX = px;
      if (px > maxX) maxX = px;
      if (py < minY) minY = py;
      if (py > maxY) maxY = py;
    }
    return (l: minX, b: minY, r: maxX, t: maxY);
  }
}

/// A box in PDF page space (points, y up).
typedef _PdfBox = ({double l, double b, double r, double t});
