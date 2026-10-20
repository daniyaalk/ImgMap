import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'pdf_shapes.dart';

/// A run of text on a chart, with each character's box in rendered-image
/// pixels.
class ChartText {
  ChartText(this.text, this.charRects)
    : assert(text.length == charRects.length);

  final String text;
  final List<ui.Rect> charRects;

  ui.Rect boundsOf(int start, int end) {
    var r = charRects[start];
    for (var i = start + 1; i < end; i++) {
      r = r.expandToInclude(charRects[i]);
    }
    return r;
  }

  ui.Rect get bounds => boundsOf(0, text.length);
}

/// Page 1 of a chart PDF as an image, plus its text layer in the same
/// pixel space.
class RenderedChart {
  RenderedChart(
    this.png,
    this.size,
    this.texts, {
    required this.pointsPerPixel,
    this.shapes = const [],
  });

  /// Bounds of the small vector drawings (map symbols), in image pixels.
  final List<ui.Rect> shapes;
  final Uint8List png;
  final ui.Size size;
  final List<ChartText> texts;

  /// PDF points (1/72 inch on paper) per image pixel, to relate the
  /// image to the chart's printed scale.
  final double pointsPerPixel;
}

/// Renders page 1 of [pdf] with its longest side at [longSide] pixels.
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

    final raw = await page.loadText();
    final texts = raw == null
        ? <ChartText>[]
        : groupText(raw.fullText, [
            for (final r in raw.charRects)
              r.toRect(page: page, scaledPageSize: size),
          ]);
    List<ui.Rect> shapes;
    try {
      shapes = await pageShapes(doc, page, size);
    } catch (_) {
      shapes = const []; // Symbols are a bonus; text and image still work.
    }
    return RenderedChart(
      png.buffer.asUint8List(),
      size,
      texts,
      pointsPerPixel: 1 / scale,
      shapes: shapes,
    );
  } finally {
    await doc.dispose();
  }
}

/// Splits a page's characters into runs of neighbouring glyphs.
///
/// PDFs from word processors often place each glyph (or a few) separately,
/// so a label such as `077°10'E` may arrive as several fragments; joining by
/// geometry instead of by the PDF's own word breaks reassembles it. Spaces
/// inside a run are kept so text still reads naturally.
List<ChartText> groupText(String text, List<ui.Rect> rects) {
  final runs = <ChartText>[];
  var chars = StringBuffer();
  var boxes = <ui.Rect>[];

  void flush() {
    final s = chars.toString();
    if (s.trim().isNotEmpty) {
      // Trim surrounding whitespace with its boxes.
      var start = 0, end = s.length;
      while (start < end && s[start].trim().isEmpty) {
        start++;
      }
      while (end > start && s[end - 1].trim().isEmpty) {
        end--;
      }
      runs.add(ChartText(s.substring(start, end), boxes.sublist(start, end)));
    }
    chars = StringBuffer();
    boxes = [];
  }

  ui.Rect? last;
  for (var i = 0; i < text.length && i < rects.length; i++) {
    final c = text[i];
    final r = rects[i];
    if (c == '\n' || c == '\r') {
      flush();
      last = null;
      continue;
    }
    final blank = c.trim().isEmpty || r.isEmpty;
    if (!blank && last != null && !_adjacent(last, r)) flush();
    chars.write(c);
    // Whitespace often has a zero box; give it its neighbour's.
    boxes.add(blank ? (last ?? r) : r);
    if (!blank) last = r;
  }
  flush();
  return runs;
}

bool _adjacent(ui.Rect a, ui.Rect b) {
  final size = [
    a.width,
    a.height,
    b.width,
    b.height,
  ].reduce((x, y) => x > y ? x : y);
  // Gap between boxes, in either axis, relative to glyph size. Covers
  // horizontal and rotated (vertical) labels alike.
  final dx = (b.left > a.right)
      ? b.left - a.right
      : (a.left > b.right ? a.left - b.right : 0.0);
  final dy = (b.top > a.bottom)
      ? b.top - a.bottom
      : (a.top > b.bottom ? a.top - b.bottom : 0.0);
  return dx <= size * 0.9 && dy <= size * 0.9;
}
