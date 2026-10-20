import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pan/zoom state for a chart image, in the image's own pixel space.
///
/// The scene inside the viewer is the image at its native resolution, so a
/// "scene" point is simply an image pixel. Anything placed on the chart is
/// therefore stored in image pixels and mapped to the screen through this
/// transform; the display size never leaks into stored data.
class ChartViewController extends TransformationController {
  ChartViewController(this.imageSize);

  final Size imageSize;
  Size _viewport = Size.zero;
  bool _hasLayout = false;

  Size get viewportSize => _viewport;

  /// Screen pixels per image pixel. Not `getMaxScaleOnAxis`, which also
  /// counts the untouched z axis and so never reports less than 1.
  double get scale {
    final m = value.storage;
    return math.sqrt(m[0] * m[0] + m[1] * m[1]);
  }

  double get fitScale => _viewport.isEmpty
      ? 1
      : math.min(
          _viewport.width / imageSize.width,
          _viewport.height / imageSize.height,
        );

  Offset toScreen(Offset imagePixel) =>
      MatrixUtils.transformPoint(value, imagePixel);

  Offset toImage(Offset screen) => toScene(screen);

  /// Whether [imagePixel] is currently on screen.
  bool isVisible(Offset imagePixel, {double margin = 0}) =>
      (Offset.zero & _viewport).deflate(margin).contains(toScreen(imagePixel));

  void fit() => _set(fitScale, Offset(imageSize.width, imageSize.height) / 2);

  void centerOn(Offset imagePixel) => _set(scale, imagePixel);

  void _set(double s, Offset center) {
    value = Matrix4.diagonal3Values(s, s, 1)
      ..setTranslationRaw(
        _viewport.width / 2 - center.dx * s,
        _viewport.height / 2 - center.dy * s,
        0,
      );
  }

  void _updateViewport(Size size) {
    if (size == _viewport) return;
    if (!_hasLayout) {
      _viewport = size;
      _hasLayout = true;
      fit();
      return;
    }
    // Keep the same chart point centered across rotation/resizes.
    final center = toImage(_viewport.center(Offset.zero));
    _viewport = size;
    _set(scale, center);
  }
}

/// A zoomable chart image with an overlay drawn in screen space, so markers
/// stay a constant size while the chart zooms beneath them.
class ChartViewport extends StatelessWidget {
  const ChartViewport({
    super.key,
    required this.image,
    required this.controller,
    this.overlay,
    this.onTap,
    this.onUserInteraction,
  });

  final ImageProvider image;
  final ChartViewController controller;

  /// Painted above the chart; rebuilt whenever the view moves.
  final Widget Function(BuildContext context)? overlay;

  /// Called with the tapped image pixel.
  final ValueChanged<Offset>? onTap;

  /// Called when the user starts panning or zooming.
  final VoidCallback? onUserInteraction;

  @override
  Widget build(BuildContext context) {
    final size = controller.imageSize;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        // Layout must not mutate listeners mid-build; defer to after frame.
        if (viewport != controller.viewportSize) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => controller._updateViewport(viewport),
          );
        }
        final fit = math.min(
          viewport.width / size.width,
          viewport.height / size.height,
        );
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              InteractiveViewer(
                transformationController: controller,
                constrained: false,
                boundaryMargin: EdgeInsets.symmetric(
                  horizontal: viewport.width / 2,
                  vertical: viewport.height / 2,
                ),
                minScale: fit / 2,
                maxScale: math.max(8, fit * 16),
                onInteractionStart: (_) => onUserInteraction?.call(),
                child: GestureDetector(
                  onTapUp: onTap == null
                      ? null
                      : (d) => onTap!(d.localPosition),
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Image(
                      image: image,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, _) => const Center(
                        child: Text('Chart image could not be loaded'),
                      ),
                    ),
                  ),
                ),
              ),
              if (overlay != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => overlay!(context),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
