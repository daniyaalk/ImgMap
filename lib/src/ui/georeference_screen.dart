import 'package:flutter/material.dart';

import '../data/chart_store.dart';
import '../data/models.dart';
import '../geo/coordinate_format.dart';
import '../geo/georeference.dart';
import '../geo/lat_lng.dart';
import 'chart_viewport.dart';

/// Places control points on a chart image and saves the chart.
///
/// Tapping the chart records the tapped image pixel directly, so what is
/// stored is independent of screen size, zoom or letterboxing.
class GeoreferenceScreen extends StatefulWidget {
  const GeoreferenceScreen({
    super.key,
    required this.store,
    required this.draft,
  });

  final ChartStore store;
  final ChartRecord draft;

  @override
  State<GeoreferenceScreen> createState() => _GeoreferenceScreenState();
}

class _GeoreferenceScreenState extends State<GeoreferenceScreen> {
  late final ChartViewController _view = ChartViewController(
    widget.draft.imageSize,
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.draft.name,
  );
  late List<ControlPoint> _points = [...widget.draft.controlPoints];
  bool _dirty = false;

  /// Whether a person has changed the points, making them no longer
  /// automatic.
  bool _pointsEdited = false;
  bool _saving = false;

  /// Index of a point waiting for a tap to be moved to.
  int? _repositioning;

  Georeference? _geo;
  String? _fitError;

  @override
  void initState() {
    super.initState();
    _refit();
    _name.addListener(() {
      if (_name.text != widget.draft.name && !_dirty) {
        setState(() => _dirty = true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _view.dispose();
    _name.dispose();
    super.dispose();
  }

  void _refit() {
    if (_points.length < Georeference.minPoints) {
      _geo = null;
      _fitError = null;
      return;
    }
    try {
      _geo = Georeference.fit(_points);
      _fitError = null;
    } on GeoreferenceException catch (e) {
      _geo = null;
      _fitError = e.message;
    }
  }

  void _update(List<ControlPoint> points) {
    setState(() {
      _points = points;
      _dirty = true;
      _pointsEdited = true;
      _refit();
    });
  }

  bool get _canSave => !_saving && _geo != null && _name.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.store.saveChart(
        widget.draft.copyWith(
          name: _name.text.trim(),
          controlPoints: List.unmodifiable(_points),
          clearAuto: _pointsEdited,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _onTap(Offset pixel) async {
    final size = widget.draft.imageSize;
    if (pixel.dx < 0 ||
        pixel.dy < 0 ||
        pixel.dx > size.width ||
        pixel.dy > size.height) {
      return;
    }
    final moving = _repositioning;
    if (moving != null) {
      setState(() => _repositioning = null);
      _update([
        for (var i = 0; i < _points.length; i++)
          i == moving
              ? ControlPoint(pixel: pixel, position: _points[i].position)
              : _points[i],
      ]);
      return;
    }
    // A tap close to an existing marker edits it rather than adding one.
    final tolerance = 24 / _view.scale;
    for (var i = 0; i < _points.length; i++) {
      if ((_points[i].pixel - pixel).distance <= tolerance) {
        return _editPoint(i);
      }
    }
    final position = await showDialog<LatLng>(
      context: context,
      builder: (_) => _PointDialog(title: 'Point ${_points.length + 1}'),
    );
    if (position == null) return;
    _update([..._points, ControlPoint(pixel: pixel, position: position)]);
  }

  Future<void> _editPoint(int index) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _PointDialog(
        title: 'Point ${index + 1}',
        initial: _points[index].position,
        editing: true,
      ),
    );
    if (result is LatLng) {
      _update([
        for (var i = 0; i < _points.length; i++)
          i == index
              ? ControlPoint(pixel: _points[i].pixel, position: result)
              : _points[i],
      ]);
    } else if (result == _PointAction.delete) {
      _update([..._points]..removeAt(index));
    } else if (result == _PointAction.move) {
      setState(() => _repositioning = index);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final residuals = _geo?.residualsMeters();
    final viewport = Stack(
      children: [
        ChartViewport(
          image: widget.store.imageFor(widget.draft.imageFile),
          controller: _view,
          onTap: _onTap,
          overlay: (context) => CustomPaint(
            size: Size.infinite,
            painter: _MarkersPainter(
              view: _view,
              points: _points,
              residuals: _points.length >= 3 ? residuals : null,
              highlight: _repositioning,
              colors: Theme.of(context).colorScheme,
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          // Taps go through to the chart beneath.
          child: IgnorePointer(
            child: _Hint(
              text: _repositioning != null
                  ? 'Tap the new position for point ${_repositioning! + 1}'
                  : _points.isEmpty
                  ? 'Zoom in and tap a point whose coordinates you know — '
                        'a runway threshold, VOR or fix.'
                  : _points.length == 1
                  ? 'Tap a second point, ideally far from the first.'
                  : widget.draft.autoMethod != null && !_pointsEdited
                  ? 'Placed automatically from ${widget.draft.autoMethod}. '
                        '${widget.draft.autoMethod!.contains('named fixes') ? 'Check each marker sits on its fix symbol.' : 'Check the markers sit on the chart\'s grid lines.'}'
                  : null,
            ),
          ),
        ),
      ],
    );

    final panel = _Panel(
      name: _name,
      points: _points,
      residuals: residuals,
      geo: _geo,
      fitError: _fitError,
      onEdit: _editPoint,
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          // Short landscape screens need every pixel for the chart.
          toolbarHeight: MediaQuery.sizeOf(context).height < 500 ? 44 : null,
          title: const Text('Georeference chart'),
          actions: [
            IconButton(
              tooltip: 'Fit chart to screen',
              icon: const Icon(Icons.fit_screen),
              onPressed: _view.fit,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 720) {
              return Row(
                children: [
                  Expanded(child: viewport),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 360, child: panel),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: viewport),
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.42,
                  ),
                  child: panel,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text!, style: TextStyle(color: scheme.onInverseSurface)),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.name,
    required this.points,
    required this.residuals,
    required this.geo,
    required this.fitError,
    required this.onEdit,
  });

  final TextEditingController name;
  final List<ControlPoint> points;
  final List<double>? residuals;
  final Georeference? geo;
  final String? fitError;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rms = geo?.rmsErrorMeters;
    final String summary;
    Color? summaryColor;
    if (fitError != null) {
      summary = fitError!;
      summaryColor = theme.colorScheme.error;
    } else if (points.length < 2) {
      summary =
          'Add at least 2 points. 3 or more let the app check '
          'accuracy and correct for skew in scans.';
    } else if (rms == null) {
      summary =
          'Two points set scale and rotation. Add a third point to '
          'check accuracy.';
    } else {
      summary =
          'Accuracy ±${rms.toStringAsFixed(0)} m RMS '
          '(${geo!.metersPerPixel.toStringAsFixed(1)} m per pixel). '
          'A large error usually means a mistyped coordinate.';
      // More than ~20 pixels off is beyond tapping error.
      if (rms / geo!.metersPerPixel > 20) {
        summaryColor = theme.colorScheme.error;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Chart name',
            hintText: 'e.g. RNAV STAR 28',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          summary,
          style: theme.textTheme.bodyMedium?.copyWith(color: summaryColor),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < points.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
            title: Text(
              '${formatCoordinate(points[i].position.latitude, CoordAxis.latitude)}  '
              '${formatCoordinate(points[i].position.longitude, CoordAxis.longitude)}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            subtitle: Text(
              'Pixel ${points[i].pixel.dx.round()}, '
              '${points[i].pixel.dy.round()}'
              '${points.length >= 3 && residuals != null ? ' · off by ${residuals![i].toStringAsFixed(0)} m' : ''}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => onEdit(i),
          ),
      ],
    );
  }
}

enum _PointAction { delete, move }

class _PointDialog extends StatefulWidget {
  const _PointDialog({required this.title, this.initial, this.editing = false});

  final String title;
  final LatLng? initial;
  final bool editing;

  @override
  State<_PointDialog> createState() => _PointDialogState();
}

class _PointDialogState extends State<_PointDialog> {
  final _form = GlobalKey<FormState>();
  late final _lat = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatCoordinate(widget.initial!.latitude, CoordAxis.latitude),
  );
  late final _lon = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatCoordinate(widget.initial!.longitude, CoordAxis.longitude),
  );

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  String? _validate(String? v, CoordAxis axis) {
    try {
      parseCoordinate(v ?? '', axis);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      LatLng(
        parseCoordinate(_lat.text, CoordAxis.latitude),
        parseCoordinate(_lon.text, CoordAxis.longitude),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _lat,
              autofocus: !widget.editing,
              decoration: const InputDecoration(
                labelText: 'Latitude',
                hintText: "N28°34.12'  or  283407N  or  28.5687",
              ),
              validator: (v) => _validate(v, CoordAxis.latitude),
              textInputAction: TextInputAction.next,
            ),
            TextFormField(
              controller: _lon,
              decoration: const InputDecoration(
                labelText: 'Longitude',
                hintText: "E077°06.20'  or  0770612E  or  77.1033",
              ),
              validator: (v) => _validate(v, CoordAxis.longitude),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.editing) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, _PointAction.delete),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _PointAction.move),
            child: const Text('Move'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

class _MarkersPainter extends CustomPainter {
  _MarkersPainter({
    required this.view,
    required this.points,
    required this.residuals,
    required this.highlight,
    required this.colors,
  });

  final ChartViewController view;
  final List<ControlPoint> points;
  final List<double>? residuals;
  final int? highlight;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < points.length; i++) {
      final c = view.toScreen(points[i].pixel);
      final color = i == highlight ? colors.tertiary : colors.primary;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color;
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = colors.surface.withValues(alpha: 0.9);
      // Crosshair with a gap so the exact pixel stays visible.
      for (final paint in [halo, ring]) {
        canvas.drawCircle(c, 12, paint);
        for (final d in const [Offset(1, 0), Offset(0, 1)]) {
          canvas.drawLine(c + d * 4, c + d * 18, paint);
          canvas.drawLine(c - d * 4, c - d * 18, paint);
        }
      }
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: colors.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tag = Rect.fromLTWH(
        c.dx + 14,
        c.dy - 30,
        label.width + 10,
        label.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(tag, const Radius.circular(4)),
        Paint()..color = color,
      );
      label.paint(canvas, tag.topLeft + const Offset(5, 2));
    }
  }

  @override
  bool shouldRepaint(_MarkersPainter old) => true;
}
