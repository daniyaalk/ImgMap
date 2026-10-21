import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aip/aip_registry.dart';
import '../data/chart_store.dart';
import '../data/models.dart';
import 'charts_screen.dart';
import '../location/app_location.dart';
import '../location/location_controller.dart';
import 'country_picker.dart';
import 'flight_widgets.dart';

class AirportsScreen extends StatelessWidget {
  const AirportsScreen({
    super.key,
    required this.store,
    required this.registry,
  });

  final ChartStore store;
  final AipRegistry registry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Airports'),
        actions: [
          const _GpsIndicator(),
          // Airway maps come from the AIP sources this build can reach.
          ListenableBuilder(
            listenable: registry,
            builder: (context, _) => registry.sources.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'En-route map',
                    icon: const Icon(Icons.route),
                    onPressed: () => openEnrouteMap(context, store, registry),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addAirport(context),
        icon: const Icon(Icons.add),
        label: const Text('Add airport'),
      ),
      body: ListenableBuilder(
        listenable: store,
        // Named apart from the screen's context: this one is replaced as
        // soon as the list changes, so it can't be used after an await.
        builder: (listContext, _) {
          final airports = store.airports;
          if (airports.isEmpty) {
            return _EmptyState(
              icon: Icons.flight_land,
              message:
                  'Add an airport by its ICAO code to start '
                  'collecting charts for it.',
              action: OutlinedButton.icon(
                onPressed: () => _tryDemo(context),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Try the demo'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: airports.length + (kIsWeb ? 1 : 0),
            itemBuilder: (context, i) {
              if (kIsWeb && i == 0) {
                return const ListTile(
                  leading: Icon(Icons.info_outline),
                  subtitle: Text(
                    'Browser version: charts are kept only '
                    'until the page is reloaded.',
                  ),
                );
              }
              final a = airports[i - (kIsWeb ? 1 : 0)];
              final count = store.usableChartsFor(a.icao).length;
              return ListTile(
                leading: const Icon(Icons.local_airport),
                title: Text(
                  a.icao,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    if (a.name.isNotEmpty) a.name,
                    '$count chart${count == 1 ? '' : 's'}',
                  ].join(' · '),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _confirmDelete(context, a, count),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChartsScreen(
                      store: store,
                      registry: registry,
                      icao: a.icao,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addAirport(BuildContext context) async {
    final airport = await showDialog<Airport>(
      context: context,
      builder: (_) => _AddAirportDialog(store: store),
    );
    if (airport == null || !context.mounted) return;
    await store.addAirport(airport);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChartsScreen(
          store: store,
          registry: registry,
          icao: airport.icao,
          // A new airport whose AIP we can read: go straight to its charts.
          openAip: registry.forAirport(airport.icao) != null,
        ),
      ),
    );
  }

  Future<void> _tryDemo(BuildContext context) async {
    const demo = Airport(icao: 'VIDP', name: 'Demo');
    if (store.airport(demo.icao) == null) await store.addAirport(demo);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChartsScreen(store: store, registry: registry, icao: demo.icao),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Airport airport,
    int charts,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${airport.icao}?'),
        content: Text(
          charts == 0
              ? 'This airport has no charts.'
              : 'Its $charts chart${charts == 1 ? '' : 's'} will be deleted '
                    'too.',
        ),
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
    if (ok == true) await store.deleteAirport(airport.icao);
  }
}

class _AddAirportDialog extends StatefulWidget {
  const _AddAirportDialog({required this.store});
  final ChartStore store;

  @override
  State<_AddAirportDialog> createState() => _AddAirportDialogState();
}

class _AddAirportDialogState extends State<_AddAirportDialog> {
  final _form = GlobalKey<FormState>();
  final _icao = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _icao.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      Airport(icao: _icao.text.trim(), name: _name.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add airport'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _icao,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ICAO code',
                hintText: 'VIDP',
              ),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(4),
                _UpperCaseFormatter(),
              ],
              validator: (v) {
                final s = v?.trim() ?? '';
                if (!RegExp(r'^[A-Z]{2}[A-Z0-9]{2}$').hasMatch(s)) {
                  return 'Enter a 4-character ICAO code';
                }
                if (widget.store.airport(s) != null) {
                  return 'Already in your list';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
              textCapitalization: TextCapitalization.words,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Shared with the charts list.
Widget emptyState(IconData icon, String message, {Widget? action}) =>
    _EmptyState(icon: icon, message: message, action: action);

/// The shared GPS session's state; tap for details and a fix when it needs
/// the user (permission, location services).
class _GpsIndicator extends StatelessWidget {
  const _GpsIndicator();

  @override
  Widget build(BuildContext context) {
    final location = AppLocation.of(context);
    return ListenableBuilder(
      listenable: location,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final (icon, color, tooltip) = switch (location.status) {
          LocationStatus.tracking => (
            Icons.gps_fixed,
            scheme.primary,
            'GPS fixed',
          ),
          LocationStatus.starting || LocationStatus.waitingForFix => (
            Icons.gps_not_fixed,
            scheme.onSurfaceVariant,
            'Finding GPS position',
          ),
          _ => (Icons.gps_off, scheme.error, 'GPS unavailable'),
        };
        return IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: color),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(tooltip),
              content: ListenableBuilder(
                listenable: location,
                builder: (context, _) =>
                    location.status == LocationStatus.tracking
                    ? Text(
                        'Accurate to about '
                        '${location.position?.accuracy.round() ?? '?'} m. '
                        'Charts open with your position already fixed.',
                      )
                    : LocationBanner(location: location),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
