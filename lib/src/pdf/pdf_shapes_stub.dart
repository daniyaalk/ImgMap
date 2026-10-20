import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

/// No PDFium object access in the browser build.
Future<List<Rect>> pageShapes(
  PdfDocument doc,
  PdfPage page,
  Size renderSize, {
  double maxPoints = 24,
}) async => const [];
