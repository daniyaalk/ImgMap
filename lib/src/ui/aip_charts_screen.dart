import 'package:flutter/material.dart';

import '../aip/aip_source.dart';
import '../aip/chart_importer.dart';
import '../data/chart_store.dart';
import '../geo/footprint.dart';
import '../location/app_location.dart';
import 'flight_widgets.dart' show gpsPosition;

/// Lists an airport's charts in its AIP and imports the chosen ones.
class AipChartsScreen extends StatefulWidget {
  const AipChartsScreen({
    super.key,
    required this.store,
    required this.source,
    required this.icao,
  });

  final ChartStore store;
  final AipSource source;
  final String icao;

  @override
  State<AipChartsScreen> createState() => _AipChartsScreenState();
}

class _AipChartsScreenState extends State<AipChartsScreen> {
  late final ChartImporter _importer = ChartImporter(
    widget.store,
    widget.source,
  );

  List<AipEdition>? _editions;
  AipEdition? _edition;
  List<ChartRef>? _charts;
  String? _error;
  final Set<String> _selected = {};

  /// Per-file progress while importing; null when idle.
  Map<String, ImportOutcome?>? _progress;
  bool _cancel = false;

  @override
  void initState() {
    super.initState();
    _loadEditions();
  }

  Future<void> _loadEditions() async {
    setState(() {
      _error = null;
      _editions = null;
      _charts = null;
    });
    try {
      final editions = await widget.source.editions();
      if (editions.isEmpty) throw AipException('No editions published.');
      final now = DateTime.now().toUtc();
      setState(() => _editions = editions);
      await _loadCharts(currentEdition(editions, now) ?? editions.last);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadCharts(AipEdition edition) async {
    setState(() {
      _edition = edition;
      _charts = null;
      _error = null;
      _selected.clear();
    });
    try {
      final charts = await widget.source.charts(widget.icao, edition);
      if (!mounted || _edition != edition) return;
      setState(() {
        _charts = charts;
        // First visit: suggest the charts worth flying with.
        if (widget.store
            .chartsFor(widget.icao)
            .every((c) => c.source == null)) {
          _selected.addAll([
            for (final c in charts)
              if (_suggested.contains(c.category)) c.fileName,
          ]);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool get _importing => _progress != null;

  Future<void> _import() async {
    final charts = _charts!
        .where((c) => _selected.contains(c.fileName))
        .toList();
    setState(() {
      _cancel = false;
      _progress = {for (final c in charts) c.fileName: null};
    });
    final outcomes = <ImportOutcome>[];
    for (final chart in charts) {
      if (_cancel || !mounted) break;
      final outcome = await _importer.importChart(chart);
      outcomes.add(outcome);
      if (mounted) setState(() => _progress![chart.fileName] = outcome);
    }
    if (!mounted) return;
    setState(() {
      _progress = null;
      _selected.clear();
    });
    _summarise(outcomes);
  }

  void _summarise(List<ImportOutcome> outcomes) {
    int count(ImportResult r) => outcomes.where((o) => o.result == r).length;
    final failed = outcomes.where((o) => o.result == ImportResult.failed);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import finished'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, n) in [
                (
                  'Georeferenced automatically',
                  count(ImportResult.georeferenced),
                ),
                (
                  'Couldn\'t be georeferenced, so not added',
                  count(ImportResult.unusable),
                ),
                ('Already up to date', count(ImportResult.upToDate)),
                ('Failed', failed.length),
              ])
                if (n > 0) Text('$label: $n'),
              if (count(ImportResult.georeferenced) > 0) ...[
                const SizedBox(height: 12),
                const Text(
                  'Automatic placement can be wrong. Open each chart and check '
                  'its markers before relying on it.',
                ),
              ],
              for (final f in failed) ...[
                const SizedBox(height: 8),
                Text(
                  '${f.chart.title}: ${f.detail}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_importing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _cancel = true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.icao} · ${widget.source.displayName}'),
          bottom: _importing
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(
                    value:
                        _progress!.values.where((o) => o != null).length /
                        _progress!.length,
                  ),
                )
              : null,
        ),
        // Rebuilt as the position changes, for the "covers you" marks.
        body: ListenableBuilder(
          listenable: AppLocation.of(context),
          builder: (context, _) => _body(context),
        ),
        bottomNavigationBar: _bottomBar(context),
      ),
    );
  }

  Widget? _bottomBar(BuildContext context) {
    if (_charts == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: _importing
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      'Importing ${_progress!.values.where((o) => o != null).length + 1}'
                      ' of ${_progress!.length}…',
                    ),
                  ),
                  TextButton(
                    onPressed: _cancel
                        ? null
                        : () => setState(() => _cancel = true),
                    child: Text(_cancel ? 'Stopping…' : 'Stop'),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: _selected.isEmpty ? null : _import,
                icon: const Icon(Icons.download),
                label: Text(
                  _selected.isEmpty
                      ? 'Select charts to import'
                      : 'Import ${_selected.length} chart${_selected.length == 1 ? '' : 's'}',
                ),
              ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _editions == null || _edition == null
                    ? _loadEditions
                    : () => _loadCharts(_edition!),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final charts = _charts;
    if (charts == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now().toUtc();
    // Only charts that can become a moving map are offered: the backend
    // says which it could georeference. Charts in the current import stay
    // visible until it ends.
    final visible = charts
        .where((c) => (_progress?.containsKey(c.fileName) ?? false) || c.usable)
        .toList();
    final hidden = charts.length - visible.length;
    final byCategory = <ChartCategory, List<ChartRef>>{};
    for (final c in visible) {
      (byCategory[c.category] ??= []).add(c);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _editions!)
                ChoiceChip(
                  label: Text(
                    '${e.name} · '
                    '${e.isEffectiveOn(now) ? 'from' : 'starts'} '
                    '${_date(e.effective)}',
                  ),
                  selected: e == _edition,
                  onSelected: _importing ? null : (_) => _loadCharts(e),
                ),
            ],
          ),
        ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              '$hidden chart${hidden == 1 ? ' is' : 's are'} hidden: tables, '
              'or charts that couldn\'t be georeferenced.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_edition != null && !_edition!.isEffectiveOn(now))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'This edition is not in force yet.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (charts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No charts are published for this airport.'),
          ),
        for (final category in ChartCategory.values)
          if (byCategory[category] case final list?) ...[
            _CategoryHeader(
              category: category,
              charts: list,
              selected: _selected,
              enabled: !_importing,
              onChanged: (names, value) => setState(() {
                value ? _selected.addAll(names) : _selected.removeAll(names);
              }),
            ),
            for (final c in list) _tile(c),
          ],
      ],
    );
  }

  Widget _tile(ChartRef c) {
    final progress = _progress?[c.fileName];
    final queued = _progress?.containsKey(c.fileName) ?? false;
    final stored = widget.store.chartFromSource(
      widget.source.id,
      c.icao,
      c.fileName,
    );
    final have = stored?.georeference != null ? stored : null;
    String? status;
    if (progress != null) {
      status = progress.detail;
    } else if (queued) {
      status = 'Waiting…';
    } else if (have != null) {
      status = have.source?.editionId == c.edition.id
          ? 'Imported'
          : 'Imported from ${have.source?.editionName}; this edition replaces it';
    }
    return CheckboxListTile(
      value: _selected.contains(c.fileName),
      onChanged: _importing
          ? null
          : (v) => setState(
              () =>
                  v! ? _selected.add(c.fileName) : _selected.remove(c.fileName),
            ),
      title: Row(
        children: [
          Expanded(child: Text(c.title)),
          if (_covers(c))
            Tooltip(
              message: 'Covers your position',
              child: Icon(
                Icons.my_location,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
      subtitle: status == null ? null : Text(status),
      secondary: _statusIcon(progress?.result, queued, have != null),
      dense: true,
    );
  }

  /// Whether the backend's footprint of [c] contains the GPS position.
  bool _covers(ChartRef c) {
    final here = gpsPosition(AppLocation.of(context));
    final footprint = c.georef?.footprint;
    return here != null &&
        footprint != null &&
        polygonContains(footprint, here);
  }

  Widget? _statusIcon(ImportResult? result, bool queued, bool have) {
    final scheme = Theme.of(context).colorScheme;
    return switch (result) {
      ImportResult.georeferenced => Icon(
        Icons.gps_fixed,
        color: scheme.primary,
      ),
      ImportResult.unusable => Icon(Icons.block, color: scheme.outline),
      ImportResult.upToDate => Icon(Icons.check, color: scheme.primary),
      ImportResult.failed => Icon(Icons.error_outline, color: scheme.error),
      null when queued => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      null when have => Icon(Icons.download_done, color: scheme.outline),
      null => null,
    };
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.charts,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final ChartCategory category;
  final List<ChartRef> charts;
  final Set<String> selected;
  final bool enabled;
  final void Function(Iterable<String> names, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final names = charts.map((c) => c.fileName);
    final all = names.every(selected.contains);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${category.label} (${charts.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton(
            onPressed: enabled ? () => onChanged(names, !all) : null,
            child: Text(all ? 'Clear' : 'Select all'),
          ),
        ],
      ),
    );
  }
}

const _suggested = {
  ChartCategory.aerodrome,
  ChartCategory.departure,
  ChartCategory.arrival,
  ChartCategory.approach,
};

String _date(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
