import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aip/aip_registry.dart';
import '../geo/footprint.dart';
import '../location/app_location.dart';
import 'flight_widgets.dart' show PositionBadge, gpsPosition;
import '../aip/aip_source.dart';
import '../aip/chart_importer.dart' show ChartImporter, formatAccuracy;
import '../data/chart_store.dart';
import '../data/models.dart';
import 'aip_charts_screen.dart';
import 'airports_screen.dart' show emptyState;
import 'georeference_screen.dart';
import 'moving_map_screen.dart';

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({
    super.key,
    required this.store,
    required this.registry,
    required this.icao,
    this.openAip = false,
  });

  final ChartStore store;
  final AipRegistry registry;
  final String icao;

  /// Open the AIP chart list straight away.
  final bool openAip;

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  bool _importing = false;

  ChartStore get store => widget.store;
  late final AipSource? _aip = widget.registry.forAirport(widget.icao);

  @override
  void initState() {
    super.initState();
    _refreshGeoreferences();
    if (widget.openAip && _aip != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAip());
    }
  }

  /// Picks up better georeferencing the backend has published since
  /// these charts were imported.
  Future<void> _refreshGeoreferences() async {
    final aip = _aip;
    if (aip == null) return;
    try {
      final n = await ChartImporter(
        store,
        aip,
      ).refreshGeoreferences(widget.icao);
      if (n > 0) {
        _snack(
          'Improved georeferencing applied to $n chart${n == 1 ? '' : 's'}.',
        );
      }
    } on Object {
      // Offline: the charts as stored are still good.
    }
  }

  void _openAip() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          AipChartsScreen(store: store, source: _aip!, icao: widget.icao),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final airport = store.airport(widget.icao);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.icao),
        actions: [
          if (_aip != null)
            IconButton(
              tooltip: 'Get charts from ${_aip.displayName}',
              icon: const Icon(Icons.cloud_download_outlined),
              onPressed: _importing ? null : _openAip,
            ),
          PopupMenuButton<String>(
            enabled: !_importing,
            onSelected: (_) => _importDemo(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'demo', child: Text('Add demo chart')),
            ],
          ),
        ],
        bottom: _importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importChart,
        icon: const Icon(Icons.add_photo_alternate),
        label: const Text('Add chart'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, AppLocation.of(context)]),
        builder: (context, _) {
          // Only charts that work as a moving map are listed.
          final charts = store.usableChartsFor(widget.icao);
          final here = gpsPosition(AppLocation.of(context));
          if (charts.isEmpty) {
            return emptyState(
              Icons.map_outlined,
              _aip != null
                  ? 'No charts yet. Fetch them from ${_aip.displayName}, '
                        'or add your own chart image.'
                  : 'No charts for ${airport?.name.isNotEmpty == true ? airport!.name : widget.icao} yet. '
                        'Add a chart image, then mark points on it whose '
                        'coordinates you know.',
              action: _aip == null
                  ? null
                  : FilledButton.icon(
                      onPressed: _openAip,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Get AIP charts'),
                    ),
            );
          }
          // Charts covering the current position first: the ones you
          // most likely want right now.
          final covering = <ChartRecord>[], others = <ChartRecord>[];
          for (final c in charts) {
            final footprint = chartFootprint(c);
            (here != null &&
                        footprint != null &&
                        polygonContains(footprint, here)
                    ? covering
                    : others)
                .add(c);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (covering.isNotEmpty) ...[
                const _SectionHeader('Covers your position'),
                for (final c in covering)
                  _ChartTile(store: store, chart: c, coversPosition: true),
                const _SectionHeader('Other charts'),
              ],
              for (final c in others) _ChartTile(store: store, chart: c),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importChart() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(type: FileType.image);
    } catch (e) {
      _snack('Could not open the file picker: $e');
      return;
    }
    if (file == null) return;
    await _import(
      () => file!.xFile.readAsBytes(),
      file.extension ?? '',
      file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    );
  }

  /// A generated, deliberately rotated chart with fixes whose coordinates
  /// are printed on it; see tool/make_demo_chart.py.
  Future<void> _importDemo() => _import(
    () async =>
        (await rootBundle.load('assets/demo_chart.png')).buffer.asUint8List(),
    'png',
    'Demo chart',
  );

  Future<void> _import(
    Future<Uint8List> Function() read,
    String extension,
    String suggestedName,
  ) async {
    setState(() => _importing = true);
    final ImportedImage image;
    try {
      image = await store.importImage(await read(), extension);
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    } catch (e) {
      _snack('Could not import the image: $e');
      return;
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (image.downscaled) {
      _snack(
        'Large image reduced to ${image.size.width.round()}×'
        '${image.size.height.round()} px to fit in memory.',
      );
    }
    if (!mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GeoreferenceScreen(
          store: store,
          draft: ChartRecord(
            id: store.newChartId(),
            airportIcao: widget.icao,
            name: suggestedName,
            imageFile: image.fileName,
            imageSize: image.size,
            controlPoints: const [],
          ),
        ),
      ),
    );
    if (saved != true) await store.discardImage(image.fileName);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ChartTile extends StatelessWidget {
  const _ChartTile({
    required this.store,
    required this.chart,
    this.coversPosition = false,
  });

  final ChartStore store;
  final ChartRecord chart;

  /// The current GPS fix lies on this chart.
  final bool coversPosition;

  @override
  Widget build(BuildContext context) {
    final geo = chart.georeference;
    final rms = geo?.rmsErrorMeters;
    final String status;
    final source = chart.source;
    if (chart.autoMethod != null) {
      status =
          'Auto from ${chart.autoMethod}'
          '${chart.autoAccuracyMeters == null ? '' : ' · ${formatAccuracy(chart.autoAccuracyMeters!, estimated: chart.autoAccuracyEstimated)}'}'
          '${source == null ? '' : ' · ${source.editionName}'}';
    } else if (rms == null) {
      status = '${chart.controlPoints.length} points · accuracy unchecked';
    } else {
      status =
          '${chart.controlPoints.length} points · '
          '±${rms.toStringAsFixed(0)} m';
    }
    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: ResizeImage(
          store.imageFor(chart.imageFile),
          width: 96,
          policy: ResizeImagePolicy.fit,
        ),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.broken_image),
        ),
      ),
    );
    return ListTile(
      leading: coversPosition ? PositionBadge(child: thumbnail) : thumbnail,
      title: Text(chart.name),
      subtitle: coversPosition
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Your position is on this chart\n',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: status),
                ],
              ),
            )
          : Text(status),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GeoreferenceScreen(store: store, draft: chart),
              ),
            );
          } else if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Delete "${chart.name}"?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (ok == true) await store.deleteChart(chart.id);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit points')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MovingMapScreen(store: store, chart: chart),
        ),
      ),
    );
  }
}
