import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:geolocator/geolocator.dart';

enum LocationStatus {
  starting,
  serviceDisabled,
  denied,
  deniedForever,
  unsupported,
  waitingForFix,
  tracking,
  error,
}

/// Owns the location permission flow and the GPS position stream.
///
/// Permission is always resolved before subscribing, so a missing grant
/// shows up as a [status] rather than an exception, and the stream is
/// restarted automatically when location services are switched back on.
class LocationController extends ChangeNotifier {
  LocationStatus _status = LocationStatus.starting;
  Position? _position;
  bool _reducedAccuracy = false;
  String? _error;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  bool _disposed = false;
  bool _simulating = false;

  /// Bumped by every [start]/[simulate] so a slow permission prompt from an
  /// earlier call can't subscribe over a newer source.
  int _session = 0;

  LocationStatus get status => _status;
  Position? get position => _position;

  /// True when the user granted only approximate location.
  bool get reducedAccuracy => _reducedAccuracy;
  String? get error => _error;

  /// True while positions come from [simulate] instead of the device.
  bool get simulating => _simulating;

  /// Replaces the device GPS with [source], skipping permission checks.
  void simulate(Stream<Position> source) {
    _session++;
    _simulating = true;
    _stopPositions();
    _position = null;
    _set(LocationStatus.waitingForFix);
    _listen(source);
  }

  /// Sets a device fix directly, as GPS would; for tests.
  @visibleForTesting
  void debugSetPosition(Position position) {
    _position = position;
    _set(LocationStatus.tracking);
  }

  /// Stops listening while the app is in the background. The last fix is
  /// dropped: shown later it would look current when it isn't.
  void pause() {
    if (_simulating) return;
    _session++; // Abandon a start still waiting on permission.
    _stopPositions();
    _position = null;
    _set(LocationStatus.starting);
  }

  /// Picks up again after [pause].
  Future<void> resume() => _simulating ? Future.value() : start();

  /// Returns to the device GPS.
  Future<void> stopSimulation() {
    _simulating = false;
    _stopPositions(); // End the simulated feed now, not after GPS restarts.
    _position = null;
    return start();
  }

  Future<void> start() async {
    final session = ++_session;

    _set(LocationStatus.starting);
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      // Subscribed only once the plugin has answered, so platforms without
      // one never open the channel.
      _serviceSub ??= _serviceStatusStream()?.listen((s) {
        if (_simulating) return;
        if (s == ServiceStatus.enabled) {
          start();
        } else {
          _stopPositions();
          _set(LocationStatus.serviceDisabled);
        }
      });
      if (!serviceOn) {
        return _setIf(session, LocationStatus.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return _setIf(session, LocationStatus.denied);
        case LocationPermission.deniedForever:
          return _setIf(session, LocationStatus.deniedForever);
        case LocationPermission.unableToDetermine:
          return _setIf(session, LocationStatus.unsupported);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      _reducedAccuracy = await _isReducedAccuracy();
    } on MissingPluginException {
      return _setIf(session, LocationStatus.unsupported);
    } catch (e) {
      _error = '$e';
      return _setIf(session, LocationStatus.error);
    }

    if (_disposed || session != _session) return;
    _stopPositions();
    _set(
      _position == null
          ? LocationStatus.waitingForFix
          : LocationStatus.tracking,
    );
    _listen(Geolocator.getPositionStream(locationSettings: _settings()));
  }

  void _listen(Stream<Position> source) {
    _positionSub = source.listen(
      (p) {
        _position = p;
        _error = null;
        _set(LocationStatus.tracking);
      },
      onError: (Object e) {
        if (e is LocationServiceDisabledException) {
          _set(LocationStatus.serviceDisabled);
        } else if (e is PermissionDeniedException) {
          _set(LocationStatus.denied);
        } else {
          _error = '$e';
          _set(LocationStatus.error);
        }
      },
    );
  }

  Future<void> openSettings() async {
    if (_status == LocationStatus.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  LocationSettings _settings() {
    if (kIsWeb) {
      return const LocationSettings(accuracy: LocationAccuracy.best);
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          intervalDuration: const Duration(seconds: 1),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.airborne,
          pauseLocationUpdatesAutomatically: false,
          // Foreground only; background updates need extra entitlements.
          allowBackgroundLocationUpdates: false,
        );
      default:
        return const LocationSettings(accuracy: LocationAccuracy.best);
    }
  }

  Stream<ServiceStatus>? _serviceStatusStream() {
    // Only Android and Apple platforms report service changes.
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return Geolocator.getServiceStatusStream().handleError((Object _) {});
      default:
        return null;
    }
  }

  Future<bool> _isReducedAccuracy() async {
    try {
      return await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  void _stopPositions() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _setIf(int session, LocationStatus status) {
    if (session == _session) _set(status);
  }

  void _set(LocationStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPositions();
    _serviceSub?.cancel();
    super.dispose();
  }
}
