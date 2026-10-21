import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Page 1 of a chart PDF as an image.
class RenderedChart {
  RenderedChart(this.png, this.size);
  final Uint8List png;

  /// The displayed page (rotation applied), in pixels.
  final ui.Size size;
}

/// Renders page 1 of [pdf] with its longest side at [longSide] pixels.
///
/// The backend gives positions as fractions of the displayed page, so any
/// size works; 4096 keeps chart text crisp when zoomed.
Future<RenderedChart> renderChartPdf(
  Uint8List pdf, {
  int longSide = 4096,
}) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openData(pdf, sourceName: 'chart');
  try {
    if (doc.pages.isEmpty) throw const FormatException('The PDF is empty.');
    final page = doc.pages.first;
    final scale =
        longSide / (page.width > page.height ? page.width : page.height);
    final size = ui.Size(
      (page.width * scale).roundToDouble(),
      (page.height * scale).roundToDouble(),
    );
    final image = await page.render(
      fullWidth: size.width,
      fullHeight: size.height,
      backgroundColor: 0xffffffff,
    );
    if (image == null) throw const FormatException('Could not draw the PDF.');
    final ui.Image uiImage;
    try {
      uiImage = await image.createImage();
    } finally {
      image.dispose();
    }
    final png = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    uiImage.dispose();
    if (png == null) throw const FormatException('Could not encode the chart.');
    return RenderedChart(png.buffer.asUint8List(), size);
  } finally {
    await doc.dispose();
  }
}
