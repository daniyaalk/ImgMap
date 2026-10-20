import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../geo/lat_lng.dart';
import '../geo/projection.dart';
import 'enroute_model.dart';

/// Where the en-route map looks: a Web Mercator centre and scale.
class EnrouteView extends ChangeNotifier {
  /// Centred on [_center] (Mercator meters) at [_mpp] meters per pixel.
  EnrouteView(this._center, this._mpp);

  static const _merc = MapProjection.webMercator;
  static const double minMpp = 4, maxMpp = 20000;

  Offset _center;
  double _mpp;
  Size viewport = Size.zero;

  /// Mercator meters per screen pixel at the centre.
  double get metersPerPixel => _mpp;

  /// Ground nautical miles per pixel at the centre, for scale decisions.
  double get nmPerPixel {
    final lat = _merc.inverse(_center).latitude;
    return _mpp * math.cos(lat * math.pi / 180) / 1852;
  }

  LatLng get center => _merc.inverse(_center);

  static Offset project(LatLng p) => _merc.forward(p);

  Offset toScreen(Offset merc) => Offset(
    (merc.dx - _center.dx) / _mpp + viewport.width / 2,
    (_center.dy - merc.dy) / _mpp + viewport.height / 2,
  );

  Offset toMerc(Offset screen) => Offset(
    _center.dx + (screen.dx - viewport.width / 2) * _mpp,
    _center.dy - (screen.dy - viewport.height / 2) * _mpp,
  );

  /// The visible area in Mercator meters, padded by [margin] pixels.
  Rect visible({double margin = 0}) => Rect.fromPoints(
    toMerc(Offset(-margin, -margin)),
    toMerc(Offset(viewport.width + margin, viewport.height + margin)),
  );

  void panBy(Offset screenDelta) {
    _center -= Offset(screenDelta.dx * _mpp, -screenDelta.dy * _mpp);
    notifyListeners();
  }

  /// Zooms by [factor] (>1 zooms in) keeping [focal] fixed on screen.
  void zoomAt(double factor, Offset focal) {
    final before = toMerc(focal);
    _mpp = (_mpp / factor).clamp(minMpp, maxMpp);
    final after = toMerc(focal);
    _center += before - after;
    notifyListeners();
  }

  void setScale(double metersPerPixel, Offset focal) =>
      zoomAt(_mpp / metersPerPixel.clamp(minMpp, maxMpp), focal);

  void centerOn(LatLng p) {
    _center = project(p);
    notifyListeners();
  }

  /// Shows all of [points] with some room around them.
  void fit(Iterable<LatLng> points) {
    final m = points.map(project).toList();
    if (m.isEmpty || viewport.isEmpty) return;
    var r = Rect.fromPoints(m.first, m.first);
    for (final p in m) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    _center = r.center;
    _mpp = math
        .max(
          r.width / (viewport.width * 0.85),
          r.height / (viewport.height * 0.85),
        )
        .clamp(minMpp, maxMpp);
    notifyListeners();
  }
}

/// What a tap on the map hit.
sealed class MapHit {}

class PointHit extends MapHit {
  PointHit(this.point);
  final EnroutePoint point;
}

class SegmentHit extends MapHit {
  SegmentHit(this.route, this.segment);
  final AirRoute route;
  final RouteSegment segment;
}

/// The airway network drawn as a vector map.
class EnrouteMap extends StatefulWidget {
  const EnrouteMap({
    super.key,
    required this.data,
    required this.view,
    this.selected,
    this.overlay,
    this.onTap,
    this.onUserInteraction,
  });

  final EnrouteData data;
  final EnrouteView view;

  /// A route to highlight.
  final AirRoute? selected;

  /// Drawn above the network (the aircraft), in screen space.
  final void Function(Canvas canvas, EnrouteView view)? overlay;
  final ValueChanged<MapHit?>? onTap;
  final VoidCallback? onUserInteraction;

  @override
  State<EnrouteMap> createState() => _EnrouteMapState();
}

class _EnrouteMapState extends State<EnrouteMap> {
  late Map<EnroutePoint, Offset> _merc = _project(widget.data);
  double _startMpp = 1;

  static Map<EnroutePoint, Offset> _project(EnrouteData d) => {
    for (final p in d.points) p: EnrouteView.project(p.position),
  };

  @override
  void didUpdateWidget(EnrouteMap old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _merc = _project(widget.data);
  }

  MapHit? _hitTest(Offset at) {
    final view = widget.view;
    EnroutePoint? point;
    var best = 22.0;
    for (final e in _merc.entries) {
      final d = (view.toScreen(e.value) - at).distance;
      if (d < best) {
        best = d;
        point = e.key;
      }
    }
    if (point != null) return PointHit(point);

    SegmentHit? segment;
    var bestSeg = 14.0;
    for (final r in widget.data.routes) {
      for (final s in r.segments) {
        final d = _distanceToSegment(
          at,
          view.toScreen(_merc[s.from]!),
          view.toScreen(_merc[s.to]!),
        );
        if (d < bestSeg) {
          bestSeg = d;
          segment = SegmentHit(r, s);
        }
      }
    }
    return segment;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    return LayoutBuilder(
      builder: (context, constraints) {
        view.viewport = constraints.biggest;
        return Listener(
          // Mouse wheel and trackpad zoom on desktop and web.
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              widget.onUserInteraction?.call();
              view.zoomAt(
                math.pow(2, -e.scrollDelta.dy / 240).toDouble(),
                e.localPosition,
              );
            }
          },
          child: GestureDetector(
            onScaleStart: (_) {
              _startMpp = view.metersPerPixel;
              widget.onUserInteraction?.call();
            },
            onScaleUpdate: (d) {
              view.panBy(d.focalPointDelta);
              if (d.scale != 1) {
                view.setScale(_startMpp / d.scale, d.localFocalPoint);
              }
            },
            onTapUp: widget.onTap == null
                ? null
                : (d) => widget.onTap!(_hitTest(d.localPosition)),
            child: CustomPaint(
              size: Size.infinite,
              painter: _NetworkPainter(
                data: widget.data,
                merc: _merc,
                view: view,
                selected: widget.selected,
                overlay: widget.overlay,
                scheme: Theme.of(context).colorScheme,
              ),
            ),
          ),
        );
      },
    );
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

class _NetworkPainter extends CustomPainter {
  _NetworkPainter({
    required this.data,
    required this.merc,
    required this.view,
    required this.selected,
    required this.overlay,
    required this.scheme,
  }) : super(repaint: view);

  final EnrouteData data;
  final Map<EnroutePoint, Offset> merc;
  final EnrouteView view;
  final AirRoute? selected;
  final void Function(Canvas, EnrouteView)? overlay;
  final ColorScheme scheme;

  static final _textCache = <String, TextPainter>{};

  static const _conventional = Color(0xFF3F6FB5);
  static const _rnav = Color(0xFF14917F);
  static const _suspect = Color(0xFFD32F2F);
  static const _highlight = Color(0xFFFFB300);

  TextPainter _text(String s, {required bool dark, bool bold = false}) {
    final key = '$s|$dark|$bold';
    return _textCache[key] ??= TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: dark ? Colors.white : const Color(0xFF1B1B1F),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dark = scheme.brightness == Brightness.dark;
    canvas.drawRect(Offset.zero & size, Paint()..color = scheme.surface);
    final visible = view.visible(margin: 40);
    final nmPx = view.nmPerPixel;
    // Labels that would land on each other are skipped.
    final taken = <(int, int)>{};
    bool claim(Rect r) {
      const cell = 22.0;
      final cells = [
        for (
          var x = (r.left / cell).floor();
          x <= (r.right / cell).floor();
          x++
        )
          for (
            var y = (r.top / cell).floor();
            y <= (r.bottom / cell).floor();
            y++
          )
            (x, y),
      ];
      if (cells.any(taken.contains)) return false;
      taken.addAll(cells);
      return true;
    }

    bool onScreen(Offset a, Offset b) =>
        visible.overlaps(Rect.fromPoints(a, b));

    // Selected route underneath, wide.
    if (selected != null) {
      final paint = Paint()
        ..color = _highlight.withValues(alpha: 0.75)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      for (final s in selected!.segments) {
        final a = merc[s.from]!, b = merc[s.to]!;
        if (onScreen(a, b)) {
          canvas.drawLine(view.toScreen(a), view.toScreen(b), paint);
        }
      }
    }

    final conventional = Paint()
      ..color = _conventional
      ..strokeWidth = 1.4;
    final rnav = Paint()
      ..color = _rnav
      ..strokeWidth = 1.4;
    final suspect = Paint()
      ..color = _suspect
      ..strokeWidth = 2;
    final designators = <(Offset, String, bool)>[];
    for (final r in data.routes) {
      for (final s in r.segments) {
        final a = merc[s.from]!, b = merc[s.to]!;
        if (!onScreen(a, b)) continue;
        final sa = view.toScreen(a), sb = view.toScreen(b);
        if (data.suspect.contains(s)) {
          _dashed(canvas, sa, sb, suspect);
        } else {
          canvas.drawLine(sa, sb, r.isRnav ? rnav : conventional);
        }
        if (nmPx < 1.2 && (sb - sa).distance > 140) {
          designators.add(((sa + sb) / 2, r.designator, r.isRnav));
        }
      }
    }

    // Points: navaids always, waypoints once zoomed in a little.
    final symbolPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final fill = Paint();
    final labels = <(Offset, EnroutePoint)>[];
    for (final e in merc.entries) {
      final p = e.key;
      if (!visible.contains(e.value)) continue;
      final navaid = p.kind == PointKind.navaid;
      if (!navaid && nmPx > 2.5) continue;
      if (!navaid && !p.compulsory && nmPx > 1.2) continue;
      final c = view.toScreen(e.value);
      final ink = dark ? Colors.white : const Color(0xFF1B1B1F);
      symbolPaint.color = ink;
      fill.color = ink;
      if (navaid) {
        canvas.drawPath(_polygon(c, 6, 6), symbolPaint);
        canvas.drawCircle(c, 1.5, fill);
      } else {
        final tri = _polygon(c, 5.5, 3, rotation: -math.pi / 2);
        canvas.drawPath(tri, p.compulsory ? fill : symbolPaint);
      }
      if (navaid ? nmPx < 2 : nmPx < 0.8) labels.add((c, p));
    }

    // Navaid labels claim space first, then waypoints, then route names.
    labels.sort((a, b) => a.$2.kind.index.compareTo(b.$2.kind.index));
    for (final (c, p) in labels) {
      final t = _text(p.label, dark: dark, bold: p.kind == PointKind.navaid);
      final at = c + const Offset(8, -14);
      if (!claim(at & t.size)) continue;
      t.paint(canvas, at);
    }
    for (final (c, name, isRnav) in designators) {
      final t = _text(name, dark: true, bold: true);
      final box = Rect.fromCenter(
        center: c,
        width: t.width + 8,
        height: t.height + 2,
      );
      if (!claim(box)) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()..color = isRnav ? _rnav : _conventional,
      );
      t.paint(canvas, box.topLeft + const Offset(4, 1));
    }

    _scaleBar(canvas, size, dark);
    overlay?.call(canvas, view);
  }

  void _scaleBar(Canvas canvas, Size size, bool dark) {
    final nmPx = view.nmPerPixel;
    // The largest round distance under ~120 px.
    const steps = [1, 2, 5, 10, 20, 50, 100, 200, 500];
    var nm = steps.first;
    for (final s in steps) {
      if (s / nmPx <= 120) nm = s;
    }
    final w = nm / nmPx;
    final o = Offset(12, size.height - 18);
    final ink = Paint()
      ..color = dark ? Colors.white : Colors.black
      ..strokeWidth = 2;
    canvas.drawLine(o, o + Offset(w, 0), ink);
    canvas.drawLine(o, o - const Offset(0, 6), ink);
    canvas.drawLine(o + Offset(w, 0), o + Offset(w, -6), ink);
    _text('$nm NM', dark: dark).paint(canvas, o + const Offset(4, -18));
  }

  static Path _polygon(Offset c, double r, int n, {double rotation = 0}) {
    final path = Path();
    for (var i = 0; i < n; i++) {
      final a = rotation + 2 * math.pi * i / n;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += 12) {
      canvas.drawLine(a + u * t, a + u * math.min(t + 7, len), paint);
    }
  }

  @override
  bool shouldRepaint(_NetworkPainter old) =>
      old.data != data ||
      old.selected != selected ||
      old.scheme != scheme ||
      old.overlay != overlay;
}
