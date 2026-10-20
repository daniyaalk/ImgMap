import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/chart_store.dart';
import '../data/models.dart';
import '../geo/georeference.dart';
import '../geo/lat_lng.dart';
import '../location/location_controller.dart';
import '../location/simulated_flight.dart';
import 'chart_viewport.dart';
import 'flight_widgets.dart';

class MovingMapScreen extends StatefulWidget {
  const MovingMapScreen({super.key, required this.store, required this.chart});

  final ChartStore store;
  final ChartRecord chart;

  @override
  State<MovingMapScreen> createState() => _MovingMapScreenState();
}

class _MovingMapScreenState extends State<MovingMapScreen> {
  late final Georeference _geo = widget.chart.georeference!;
  late final ChartViewController _view = ChartViewController(
    widget.chart.imageSize,
  );
  final LocationController _location = LocationController();
  bool _follow = true;
  bool _notToScaleDismissed = false;

  @override
  void initState() {
    super.initState();
    _location.addListener(_onLocation);
    _location.start();
    WakelockPlus.enable().catchError((Object _) {});
  }

  @override
  void dispose() {
    _setImmersive(false);
    WakelockPlus.disable().catchError((Object _) {});
    _location.removeListener(_onLocation);
    _location.dispose();
    _view.dispose();
    super.dispose();
  }

  void _onLocation() {
    final p = _location.position;
    if (!_follow || p == null || _view.viewportSize.isEmpty) return;
    final pixel = _geo.toPixel(LatLng(p.latitude, p.longitude));
    if (_onChart(pixel)) _view.centerOn(pixel);
  }

  bool _onChart(Offset pixel) =>
      (Offset.zero & widget.chart.imageSize).contains(pixel);

  void _toggleSimulation() {
    if (_location.simulating) {
      _location.stopSimulation();
    } else {
      _location.simulate(simulatedFlight(_geo, widget.chart.imageSize));
    }
    _setFollow(true);
    setState(() {});
  }

  void _setFollow(bool follow) {
    if (follow == _follow) return;
    setState(() => _follow = follow);
    if (follow) _onLocation();
  }

  /// Whether the system bars are currently hidden for landscape.
  bool _immersive = false;

  void _setImmersive(bool on) {
    if (on == _immersive) return;
    _immersive = on;
    // Swiping from an edge still brings the bars back briefly.
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ).catchError((Object _) {});
  }

  void _fit() {
    _setFollow(false);
    _view.fit();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    // Defer: changing system UI mid-build would relayout under us.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setImmersive(landscape);
    });
    return landscape ? _landscape(context) : _portrait(context);
  }

  Widget _simulateButton() => IconButton(
    tooltip: _location.simulating
        ? 'Stop simulated flight'
        : 'Simulate a flight over this chart',
    isSelected: _location.simulating,
    icon: const Icon(Icons.flight_takeoff),
    selectedIcon: const Icon(Icons.flight),
    onPressed: _toggleSimulation,
  );

  Widget _fitButton() => IconButton(
    tooltip: 'Fit chart to screen',
    icon: const Icon(Icons.fit_screen),
    onPressed: _fit,
  );

  Widget _followButton({bool small = false}) => ListenableBuilder(
    listenable: _location,
    builder: (context, _) => _location.position == null
        ? const SizedBox.shrink()
        : FloatingActionButton(
            mini: small,
            heroTag: null,
            tooltip: _follow ? 'Following position' : 'Follow position',
            onPressed: () => _setFollow(true),
            child: Icon(_follow ? Icons.my_location : Icons.location_searching),
          ),
  );

  Widget _infoBar({required bool vertical}) => ListenableBuilder(
    listenable: _location,
    builder: (context, _) => FlightInfoBar(
      position: _location.position,
      simulated: _location.simulating,
      vertical: vertical,
    ),
  );

  Widget _portrait(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chart.name),
        actions: [_simulateButton(), _fitButton()],
      ),
      floatingActionButton: _followButton(),
      // As the bottom bar, so the follow button floats above it.
      bottomNavigationBar: _infoBar(vertical: false),
      body: _map(context, statusInset: 12),
    );
  }

  /// No app bar or bottom bar: controls float over the chart and flight
  /// data sits in a narrow column, so the chart gets the full height.
  Widget _landscape(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                _map(context, statusInset: 64),
                SafeArea(
                  right: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FloatingControls(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              icon: const BackButtonIcon(),
                              onPressed: () => Navigator.maybePop(context),
                            ),
                          ],
                        ),
                        const Spacer(),
                        FloatingControls(
                          children: [_simulateButton(), _fitButton()],
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _followButton(small: true),
                ),
              ],
            ),
          ),
          _infoBar(vertical: true),
        ],
      ),
    );
  }

  Widget _map(BuildContext context, {required double statusInset}) {
    return Stack(
      children: [
        ChartViewport(
          image: widget.store.imageFor(widget.chart.imageFile),
          controller: _view,
          onUserInteraction: () => _setFollow(false),
          overlay: (context) => ListenableBuilder(
            listenable: _location,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _NotToScalePainter(
                view: _view,
                areas: widget.chart.notToScaleAreas,
              ),
              foregroundPainter: _OwnshipPainter(
                view: _view,
                geo: _geo,
                position: _location.position,
                colors: Theme.of(context).colorScheme,
              ),
            ),
          ),
        ),
        if (widget.chart.notToScaleAreas.isNotEmpty && !_notToScaleDismissed)
          Positioned(
            left: 12,
            right: 84,
            bottom: 12,
            child: _NotToScaleNotice(
              onDismiss: () => setState(() => _notToScaleDismissed = true),
            ),
          ),
        Positioned(
          left: statusInset,
          right: statusInset,
          top: statusInset == 12 ? 12 : 8,
          child: SafeArea(
            bottom: false,
            child: ListenableBuilder(
              listenable: _location,
              builder: (context, _) => _StatusBanner(
                location: _location,
                geo: _geo,
                chartSize: widget.chart.imageSize,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.location,
    required this.geo,
    required this.chartSize,
  });

  final LocationController location;
  final Georeference geo;
  final Size chartSize;

  @override
  Widget build(BuildContext context) {
    String? offChart;
    final p = location.position;
    if (location.status == LocationStatus.tracking && p != null) {
      final here = LatLng(p.latitude, p.longitude);
      if (!(Offset.zero & chartSize).contains(geo.toPixel(here))) {
        final center = geo.toLatLng(
          Offset(chartSize.width, chartSize.height) / 2,
        );
        final nm = here.distanceTo(center) / 1852;
        final brg = here.bearingTo(center).round().toString().padLeft(3, '0');
        offChart =
            'Off chart. Chart center is ${nm.toStringAsFixed(1)} NM '
            'at $brg°T.';
      }
    }
    return LocationBanner(location: location, trackingNote: offChart);
  }
}

class _NotToScaleNotice extends StatelessWidget {
  const _NotToScaleNotice({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _amber.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Parts of this chart are marked NOT TO SCALE (outlined). '
                  'Fixes beyond a break symbol or inside an inset aren\'t at '
                  'their true positions; your own position is.',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, color: Colors.black),
              color: scheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

const _amber = Color(0xFFFFB300);

/// Outlines the chart's NOT TO SCALE labels, padded to take in the symbol
/// or inset they sit on.
class _NotToScalePainter extends CustomPainter {
  _NotToScalePainter({required this.view, required this.areas});

  final ChartViewController view;
  final List<Rect> areas;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = _amber.withValues(alpha: 0.18);
    final stroke = Paint()
      ..color = _amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final r in areas) {
      final pad = r.shortestSide * 1.5;
      final screen = Rect.fromPoints(
        view.toScreen(r.topLeft - Offset(pad, pad)),
        view.toScreen(r.bottomRight + Offset(pad, pad)),
      );
      final rr = RRect.fromRectAndRadius(screen, const Radius.circular(6));
      canvas
        ..drawRRect(rr, fill)
        ..drawRRect(rr, stroke);
    }
  }

  @override
  bool shouldRepaint(_NotToScalePainter old) => true;
}

class _OwnshipPainter extends CustomPainter {
  _OwnshipPainter({
    required this.view,
    required this.geo,
    required this.position,
    required this.colors,
  });

  final ChartViewController view;
  final Georeference geo;
  final Position? position;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final p = position;
    if (p == null) return;
    final here = LatLng(p.latitude, p.longitude);
    final c = view.toScreen(geo.toPixel(here));
    final color = const Color(0xFFE5007A);

    // Accuracy circle, in screen pixels at the current zoom.
    final radius = p.accuracy / geo.metersPerPixel * view.scale;
    if (radius > 14) {
      canvas.drawCircle(
        c,
        radius,
        Paint()..color = color.withValues(alpha: 0.12),
      );
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.5),
      );
    }

    paintOwnship(
      canvas,
      c,
      color: color,
      // GPS course is relative to true north; the chart may be rotated.
      angle: hasTrack(p)
          ? p.heading * math.pi / 180 + geo.northAngleAt(here)
          : null,
    );
  }

  @override
  bool shouldRepaint(_OwnshipPainter old) => true;
}
