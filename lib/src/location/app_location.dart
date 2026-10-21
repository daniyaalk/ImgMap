import 'package:flutter/widgets.dart';

import 'location_controller.dart';

/// The app's single location session, available to every screen.
///
/// Started when the app opens, so a chart or map opened later already has
/// a fix instead of waiting for one. Paused while the app is in the
/// background.
class AppLocation extends StatefulWidget {
  const AppLocation({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final LocationController controller;
  final Widget child;

  /// GPS starts once this is true (after the disclaimer is accepted, so the
  /// permission prompt doesn't appear over it).
  final bool enabled;

  /// The session; screens listen to it themselves, so looking it up doesn't
  /// rebuild them on every fix.
  static LocationController of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_Scope>();
    assert(scope != null, 'No AppLocation above this widget.');
    return scope!.controller;
  }

  @override
  State<AppLocation> createState() => _AppLocationState();
}

class _AppLocationState extends State<AppLocation> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) widget.controller.start();
  }

  @override
  void didUpdateWidget(AppLocation old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) widget.controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.enabled) widget.controller.resume();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        widget.controller.pause();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Scope(controller: widget.controller, child: widget.child);
}

class _Scope extends InheritedWidget {
  const _Scope({required this.controller, required super.child});
  final LocationController controller;

  @override
  bool updateShouldNotify(_Scope old) => old.controller != controller;
}
