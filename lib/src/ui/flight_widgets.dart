import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../geo/coordinate_format.dart';
import '../geo/lat_lng.dart';
import '../location/location_controller.dart';

/// Below this ground speed the GPS course is noise, so no track is drawn.
const double minTrackSpeedMps = 1.5;

/// iOS reports a negative course when it has none.
bool hasTrack(Position p) => p.speed >= minTrackSpeedMps && p.heading >= 0;

/// The aircraft symbol at [c]: an arrow along [angle] (radians clockwise
/// from screen up) with a short track line, or a dot when there's no
/// track.
void paintOwnship(
  Canvas canvas,
  Offset c, {
  required Color color,
  double? angle,
}) {
  final halo = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeJoin = StrokeJoin.round;
  final fill = Paint()..color = color;
  if (angle == null) {
    canvas.drawCircle(c, 9, halo);
    canvas.drawCircle(c, 9, fill);
    return;
  }
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(angle);
  // Track line ahead of the aircraft.
  canvas.drawLine(
    const Offset(0, -16),
    const Offset(0, -90),
    Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2,
  );
  final arrow = Path()
    ..moveTo(0, -16)
    ..lineTo(11, 12)
    ..lineTo(0, 6)
    ..lineTo(-11, 12)
    ..close();
  canvas.drawPath(arrow, halo);
  canvas.drawPath(arrow, fill);
  canvas.restore();
}

/// A translucent pill of buttons floating over the chart.
class FloatingControls extends StatelessWidget {
  const FloatingControls({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer.withValues(alpha: 0.88),
      elevation: 2,
      borderRadius: BorderRadius.circular(24),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Ground speed, track, altitude, accuracy and position.
class FlightInfoBar extends StatelessWidget {
  const FlightInfoBar({
    super.key,
    required this.position,
    required this.simulated,
    this.vertical = false,
  });
  final Position? position;
  final bool simulated;

  /// A narrow column beside the chart (landscape) instead of a bar below.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final tracking = p != null && hasTrack(p);
    final items = <(String, String)>[
      (
        'GS',
        p == null || p.speed < 0 ? '—' : '${(p.speed * 1.943844).round()} kt',
      ),
      (
        'TRK',
        tracking ? '${p.heading.round().toString().padLeft(3, '0')}°' : '—',
      ),
      (
        'ALT',
        p == null || !p.hasAltitude
            ? '—'
            : '${(p.altitude * 3.28084).round()} ft',
      ),
      ('ACC', p == null ? '—' : '±${p.accuracy.round()} m'),
    ];
    final theme = Theme.of(context);
    final mono = theme.textTheme.titleMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    final small = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget item(String label, String value) => Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, style: mono),
      ],
    );
    final lat = p == null
        ? null
        : formatCoordinate(p.latitude, CoordAxis.latitude);
    final lon = p == null
        ? null
        : formatCoordinate(p.longitude, CoordAxis.longitude);

    if (vertical) {
      return Material(
        color: theme.colorScheme.surfaceContainer,
        child: SafeArea(
          left: false,
          child: SizedBox(
            width: 104,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (label, value) in items) item(label, value),
                if (p != null)
                  Text(
                    '${simulated ? 'SIM\n' : ''}$lat\n$lon',
                    textAlign: TextAlign.center,
                    style: small,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final (label, value) in items)
                    Expanded(child: item(label, value)),
                ],
              ),
              if (p != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${simulated ? 'SIMULATED (time sped up)  ' : ''}'
                    '$lat  $lon',
                    style: small,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// GPS state, with a way to fix it when it needs the user.
class LocationBanner extends StatelessWidget {
  const LocationBanner({super.key, required this.location, this.trackingNote});

  final LocationController location;

  /// Shown while tracking normally, e.g. "Off chart".
  final String? trackingNote;

  @override
  Widget build(BuildContext context) {
    String? message;
    String? action;
    VoidCallback? onAction;

    switch (location.status) {
      case LocationStatus.starting:
        message = 'Starting GPS…';
      case LocationStatus.waitingForFix:
        message = 'Waiting for a GPS fix. A clear view of the sky helps.';
      case LocationStatus.serviceDisabled:
        message = 'Location services are off.';
        action = 'Turn on';
        onAction = location.openSettings;
      case LocationStatus.denied:
        message = 'Location permission is needed to show your position.';
        action = 'Allow';
        onAction = location.start;
      case LocationStatus.deniedForever:
        message = 'Location permission was denied. Enable it in settings.';
        action = 'Settings';
        onAction = location.openSettings;
      case LocationStatus.unsupported:
        message =
            'Location is not available here. Use the plane button '
            'to simulate a flight.';
      case LocationStatus.error:
        message = 'Location error: ${location.error}';
        action = 'Retry';
        onAction = location.start;
      case LocationStatus.tracking:
        if (trackingNote != null) {
          message = trackingNote;
        } else if (location.reducedAccuracy) {
          message =
              'Only approximate location was allowed; the position '
              'may be off by kilometers.';
          action = 'Settings';
          onAction = location.openSettings;
        }
    }
    if (message == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  message,
                  style: TextStyle(color: scheme.onInverseSurface),
                ),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.inversePrimary,
                ),
                child: Text(action),
              ),
          ],
        ),
      ),
    );
  }
}

/// The current position from real GPS, or null. A simulated flight doesn't
/// count: it says nothing about where the user actually is.
LatLng? gpsPosition(LocationController location) {
  final p = location.position;
  if (p == null || location.simulating) return null;
  return LatLng(p.latitude, p.longitude);
}

/// Marks a chart's thumbnail as covering the current position.
class PositionBadge extends StatelessWidget {
  const PositionBadge({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -6,
          bottom: -6,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
            child: Icon(Icons.my_location, size: 14, color: scheme.onPrimary),
          ),
        ),
      ],
    );
  }
}
