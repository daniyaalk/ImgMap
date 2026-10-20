import 'package:flutter/material.dart';

import '../aip/aip_registry.dart';
import '../aip/aip_source.dart';
import '../data/chart_store.dart';
import 'enroute_screen.dart';

/// A country's flag emoji from its ISO 3166-1 alpha-2 code.
String flagOf(String countryCode) => String.fromCharCodes(
  countryCode.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
);

/// Asks which country's AIP to use; null if dismissed.
Future<AipSource?> pickCountry(
  BuildContext context,
  AipRegistry registry, {
  String? currentId,
}) {
  final sources = [...registry.sources]
    ..sort((a, b) => a.country.compareTo(b.country));
  return showDialog<AipSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Country'),
      children: [
        for (final s in sources)
          ListTile(
            leading: Text(
              flagOf(s.countryCode),
              style: const TextStyle(fontSize: 28),
            ),
            title: Text(s.country),
            subtitle: Text(s.displayName),
            trailing: s.id == currentId ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, s),
          ),
      ],
    ),
  );
}

/// Opens the en-route map for the remembered country, asking for one the
/// first time when there's a choice.
Future<void> openEnrouteMap(
  BuildContext context,
  ChartStore store,
  AipRegistry registry,
) async {
  var source = registry.byId(store.enrouteSourceId ?? '');
  if (source == null) {
    source = registry.sources.length == 1
        ? registry.sources.single
        : await pickCountry(context, registry);
    if (source == null) return;
    await store.setEnrouteSourceId(source.id);
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          EnrouteScreen(store: store, registry: registry, source: source!),
    ),
  );
}
