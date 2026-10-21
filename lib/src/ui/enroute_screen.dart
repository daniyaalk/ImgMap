import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../aip/aip_registry.dart';
import '../aip/aip_source.dart';
import '../data/chart_store.dart';
import '../enroute/enroute_loader.dart';
import '../enroute/enroute_map.dart';
import '../enroute/enroute_model.dart';
import '../geo/coordinate_format.dart';
import '../geo/lat_lng.dart';
import '../location/app_location.dart';
import '../location/location_controller.dart';
import '../location/simulated_flight.dart';
import 'country_picker.dart';
import 'flight_widgets.dart';

/// A moving map of the airway network, drawn from the AIP's own data.
class EnrouteScreen extends StatefulWidget {
  const EnrouteScreen({
    super.key,
    required this.store,
    required this.registry,
    required this.source,
  });

  final ChartStore store;
  final AipRegistry registry;

  /// The country whose airways to show.
  final AipSource source;

  @override
  State<EnrouteScreen> createState() => _EnrouteScreenState();
}

class _EnrouteScreenState extends State<EnrouteScreen> {
  late final EnrouteLoader _loader = EnrouteLoader(widget.store.storage);
  late final LocationController _location = AppLocation.of(context);
  // Country-wide until data arrives.
  late final EnrouteView _view = EnrouteView(
    EnrouteView.project(widget.source.mapCenter),
    4000,
  );

  EnrouteData? _data;

  /// The edition in force, once known (needs the network).
  AipEdition? _current;
  bool _offline = false;
  String? _error;

  /// Download progress as (done, total) while downloading.
  (int, int)? _progress;
  bool _cancel = false;

  AirRoute? _selected;
  bool _follow = true;
  bool _immersive = false;
  bool _issuesDismissed = false;

  @override
  void initState() {
    super.initState();
    _location.addListener(_onLocation);
    WakelockPlus.enable().catchError((Object _) {});
    _open();
  }

  @override
  void dispose() {
    _setImmersive(false);
    WakelockPlus.disable().catchError((Object _) {});
    _cancel = true;
    _location.removeListener(_onLocation);
    // Shared with the rest of the app: hand it back on real GPS.
    // After the tree settles: other screens listen to it.
    final location = _location;
    if (location.simulating) Future.microtask(location.stopSimulation);
    _view.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final cached = await _loader.latest(widget.source.id);
    if (!mounted) return;
    if (cached != null) _show(cached);
    try {
      final editions = await widget.source.editions();
      final current = currentEdition(editions, DateTime.now().toUtc());
      if (!mounted) return;
      setState(() => _current = current);
      if (current != null && cached?.editionId != current.id) {
        final other = await _loader.cached(widget.source, current);
        if (other != null && mounted) _show(other);
      }
    } catch (e) {
      if (mounted) setState(() => _offline = true);
    }
  }

  void _show(EnrouteData data) {
    final first = _data == null;
    setState(() => _data = data);
    if (first) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _view.fit(data.points.map((p) => p.position));
        _onLocation();
      });
    }
  }

  Future<void> _download() async {
    final edition = _current;
    if (edition == null) return;
    setState(() {
      _error = null;
      _cancel = false;
      _progress = (0, 0);
    });
    try {
      final data = await _loader.download(widget.source, edition);
      if (!mounted) return;
      _data = null; // Refit to the new network.
      _show(data);
    } catch (e) {
      if (mounted && !_cancel) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  void _onLocation() {
    final p = _location.position;
    if (_follow && p != null && !_view.viewport.isEmpty) {
      _view.centerOn(LatLng(p.latitude, p.longitude));
    }
  }

  void _setFollow(bool follow) {
    if (follow == _follow) return;
    setState(() => _follow = follow);
    if (follow) _onLocation();
  }

  void _setImmersive(bool on) {
    if (on == _immersive) return;
    _immersive = on;
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ).catchError((Object _) {});
  }

  void _simulate([AirRoute? route]) {
    if (_location.simulating && route == null) {
      _location.stopSimulation();
      setState(() {});
      return;
    }
    final data = _data;
    if (data == null || data.routes.isEmpty) return;
    route ??= _selected ?? _routeNear(_view.center, data);
    setState(() => _selected = route);
    _location.simulate(
      simulatedPath([for (final p in route.points) p.position]),
    );
    _setFollow(true);
  }

  /// The longest route passing near [p]: a good default to fly.
  static AirRoute _routeNear(LatLng p, EnrouteData data) {
    double distance(AirRoute r) =>
        r.points.map((q) => q.position.distanceTo(p)).reduce(math.min);
    final routes = [...data.routes]
      ..sort((a, b) => distance(a).compareTo(distance(b)));
    final near = routes.take(5).toList()
      ..sort((a, b) => b.segments.length.compareTo(a.segments.length));
    return near.first;
  }

  void _selectRoute(AirRoute route) {
    setState(() => _selected = route);
    _setFollow(false);
    _view.fit(route.points.map((p) => p.position));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setImmersive(landscape && _data != null);
    });
    final data = _data;
    if (data == null) return _setup(context);
    return landscape ? _landscape(context, data) : _portrait(context, data);
  }

  String get _title =>
      'En-route${_data == null ? '' : ' · ${_data!.editionName}'}';

  Future<void> _changeCountry() async {
    final picked = await pickCountry(
      context,
      widget.registry,
      currentId: widget.source.id,
    );
    if (picked == null || picked.id == widget.source.id || !mounted) return;
    await widget.store.setEnrouteSourceId(picked.id);
    if (!mounted) return;
    // Each country's network is cached separately; switching back is
    // instant.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EnrouteScreen(
          store: widget.store,
          registry: widget.registry,
          source: picked,
        ),
      ),
    );
  }

  Widget _countryButton({bool compact = false}) => TextButton.icon(
    onPressed: _progress == null ? _changeCountry : null,
    icon: Text(
      flagOf(widget.source.countryCode),
      style: const TextStyle(fontSize: 20),
    ),
    label: Text(compact ? widget.source.countryCode : widget.source.country),
  );

  Widget _setup(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progress;
    Widget body;
    if (progress != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Downloading the airway map…',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      );
    } else if (_current == null && !_offline) {
      body = const CircularProgressIndicator();
    } else if (_current == null) {
      body = Text(
        'You\'re offline and no en-route data has been downloaded yet.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge,
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Build the airway map from ${widget.source.displayName}, '
            '${_current!.name}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'A small download, stored for offline use.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_title), actions: [_countryButton()]),
      body: Center(
        child: Padding(padding: const EdgeInsets.all(32), child: body),
      ),
    );
  }

  List<Widget> _actions(EnrouteData data) => [
    IconButton(
      tooltip: 'Find a fix or route',
      icon: const Icon(Icons.search),
      onPressed: () => _search(data),
    ),
    IconButton(
      tooltip: _location.simulating
          ? 'Stop simulated flight'
          : 'Simulate a flight along a route',
      isSelected: _location.simulating,
      icon: const Icon(Icons.flight_takeoff),
      selectedIcon: const Icon(Icons.flight),
      onPressed: _simulate,
    ),
    IconButton(
      tooltip: 'Show the whole network',
      icon: const Icon(Icons.zoom_out_map),
      onPressed: () {
        _setFollow(false);
        _view.fit(data.points.map((p) => p.position));
      },
    ),
  ];

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

  Widget _portrait(BuildContext context, EnrouteData data) => Scaffold(
    appBar: AppBar(
      title: Text(_title),
      actions: [_countryButton(compact: true), ..._actions(data)],
    ),
    floatingActionButton: _followButton(),
    bottomNavigationBar: _infoBar(vertical: false),
    body: _map(context, data, bannerInset: 12),
  );

  Widget _landscape(BuildContext context, EnrouteData data) => Scaffold(
    body: Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              _map(context, data, bannerInset: 64),
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
                          _countryButton(compact: true),
                        ],
                      ),
                      const Spacer(),
                      FloatingControls(children: _actions(data)),
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

  Widget _map(
    BuildContext context,
    EnrouteData data, {
    required double bannerInset,
  }) {
    final notices = <Widget>[
      ListenableBuilder(
        listenable: _location,
        builder: (context, _) => LocationBanner(location: _location),
      ),
      if (_offline)
        _Notice(
          'Offline: showing ${data.editionName}, which may be out of date.',
        )
      else if (_current != null && _current!.id != data.editionId)
        _Notice(
          '${_current!.name} is now in force; this map is '
          '${data.editionName}.',
          action: _progress == null ? 'Update' : 'Updating…',
          onAction: _progress == null ? _download : null,
          warning: true,
        ),
      if (data.issues.isNotEmpty && !_issuesDismissed)
        _Notice(
          '${data.issues.length} route segment'
          '${data.issues.length == 1 ? '' : 's'} (dashed red) don\'t match '
          'their published length or track. Tap one for details.',
          action: 'OK',
          onAction: () => setState(() => _issuesDismissed = true),
        ),
    ];
    return Stack(
      children: [
        ListenableBuilder(
          listenable: _location,
          builder: (context, _) => EnrouteMap(
            data: data,
            view: _view,
            selected: _selected,
            onUserInteraction: () => _setFollow(false),
            onTap: (hit) => _onTap(context, data, hit),
            overlay: _paintOwnship,
          ),
        ),
        Positioned(
          left: bannerInset,
          right: bannerInset,
          top: bannerInset == 12 ? 12 : 8,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                for (final n in notices)
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: n),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _paintOwnship(Canvas canvas, EnrouteView view) {
    final p = _location.position;
    if (p == null) return;
    final here = LatLng(p.latitude, p.longitude);
    final c = view.toScreen(EnrouteView.project(here));
    const color = Color(0xFFE5007A);
    // Mercator scale grows as 1/cos(latitude).
    final radius =
        p.accuracy / math.cos(p.latitude * math.pi / 180) / view.metersPerPixel;
    if (radius > 14) {
      canvas.drawCircle(
        c,
        radius,
        Paint()..color = color.withValues(alpha: 0.12),
      );
    }
    // The map is north-up Mercator, so a true course points straight.
    paintOwnship(
      canvas,
      c,
      color: color,
      angle: hasTrack(p) ? p.heading * math.pi / 180 : null,
    );
  }

  void _onTap(BuildContext context, EnrouteData data, MapHit? hit) {
    switch (hit) {
      case null:
        if (_selected != null) setState(() => _selected = null);
      case PointHit(:final point):
        _showPoint(context, data, point);
      case SegmentHit(:final route, :final segment):
        setState(() => _selected = route);
        _showSegment(context, data, route, segment);
    }
  }

  void _showPoint(BuildContext context, EnrouteData data, EnroutePoint p) {
    final routes = [
      for (final r in data.routes)
        if (r.segments.any((s) => s.from == p || s.to == p)) r,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _Sheet(
        title: p.label,
        subtitle: [
          if (p.ident != null) p.name,
          p.kind == PointKind.navaid
              ? 'Navaid'
              : p.compulsory
              ? 'Compulsory reporting point'
              : 'Reporting point on request',
        ].join(' · '),
        rows: [
          (
            'Position',
            '${formatCoordinate(p.position.latitude, CoordAxis.latitude)}  '
                '${formatCoordinate(p.position.longitude, CoordAxis.longitude)}',
          ),
        ],
        chips: [
          for (final r in routes)
            ActionChip(
              label: Text(r.designator),
              onPressed: () {
                Navigator.pop(context);
                _selectRoute(r);
              },
            ),
        ],
      ),
    );
  }

  void _showSegment(
    BuildContext context,
    EnrouteData data,
    AirRoute route,
    RouteSegment s,
  ) {
    final issue = data.issues.where((i) => i.segment == s).firstOrNull;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _Sheet(
        title: route.designator,
        subtitle:
            '${s.from.label} → ${s.to.label}'
            '${route.navigationSpec == null ? '' : ' · ${route.navigationSpec}'}',
        warning: issue?.message,
        rows: [
          (
            'Track',
            '${s.trackMagnetic == null ? '—' : '${s.trackMagnetic.toString().padLeft(3, '0')}°M'}'
                '  (${s.computedTrackTrue.round().toString().padLeft(3, '0')}°T)',
          ),
          (
            'Distance',
            s.distanceNm == null
                ? '${s.computedDistanceNm.toStringAsFixed(1)} NM'
                : '${s.distanceNm!.toStringAsFixed(1)} NM',
          ),
          if (s.upper != null || s.lower != null)
            ('Levels', '${s.lower ?? '—'} to ${s.upper ?? '—'}'),
          if (s.mocaFt != null) ('MOCA', '${s.mocaFt} ft'),
          if (s.airspaceClass != null) ('Class', s.airspaceClass!),
          if (s.widthNm != null)
            ('Width', '${s.widthNm!.toStringAsFixed(0)} NM'),
        ],
        chips: [
          ActionChip(
            avatar: const Icon(Icons.route, size: 18),
            label: const Text('Show whole route'),
            onPressed: () {
              Navigator.pop(context);
              _selectRoute(route);
            },
          ),
          ActionChip(
            avatar: const Icon(Icons.flight, size: 18),
            label: const Text('Simulate along it'),
            onPressed: () {
              Navigator.pop(context);
              _simulate(route);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _search(EnrouteData data) async {
    final picked = await showDialog<Object>(
      context: context,
      builder: (_) => _SearchDialog(data: data),
    );
    if (picked is EnroutePoint) {
      _setFollow(false);
      _view.centerOn(picked.position);
      // Close enough in to see its name.
      if (_view.nmPerPixel > 0.5) {
        _view.setScale(400, _view.viewport.center(Offset.zero));
      }
    } else if (picked is AirRoute) {
      _selectRoute(picked);
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.action, this.onAction, this.warning = false});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = warning ? scheme.errorContainer : scheme.inverseSurface;
    final fg = warning ? scheme.onErrorContainer : scheme.onInverseSurface;
    return Material(
      color: bg.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(text, style: TextStyle(color: fg)),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: fg),
                child: Text(action!),
              ),
          ],
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.subtitle,
    required this.rows,
    this.chips = const [],
    this.warning,
  });

  final String title, subtitle;
  final List<(String, String)> rows;
  final List<Widget> chips;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.headlineSmall),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            if (warning != null) ...[
              const SizedBox(height: 8),
              Text(
                'Check this segment: $warning',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(k, style: theme.textTheme.labelLarge),
                    ),
                    Expanded(
                      child: Text(
                        v,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: chips),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.data});
  final EnrouteData data;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toUpperCase();
    final points = q.isEmpty
        ? <EnroutePoint>[]
        : widget.data.points
              .where(
                (p) =>
                    p.label.startsWith(q) || p.name.toUpperCase().startsWith(q),
              )
              .take(20)
              .toList();
    final routes = q.isEmpty
        ? <AirRoute>[]
        : widget.data.routes
              .where((r) => r.designator.startsWith(q))
              .take(10)
              .toList();
    return AlertDialog(
      title: TextField(
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          hintText: 'Fix, navaid or route (DUDUM, DPN, A474)',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
      content: SizedBox(
        width: 360,
        height: 320,
        child: ListView(
          children: [
            for (final r in routes)
              ListTile(
                leading: const Icon(Icons.route),
                title: Text(r.designator),
                subtitle: Text(
                  '${r.points.first.label} – ${r.points.last.label}'
                  '${r.navigationSpec == null ? '' : ' · ${r.navigationSpec}'}',
                ),
                onTap: () => Navigator.pop(context, r),
              ),
            for (final p in points)
              ListTile(
                leading: Icon(
                  p.kind == PointKind.navaid
                      ? Icons.hexagon_outlined
                      : Icons.change_history,
                ),
                title: Text(p.label),
                subtitle: p.ident == null ? null : Text(p.name),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
  }
}
