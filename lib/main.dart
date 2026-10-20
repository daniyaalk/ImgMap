import 'package:flutter/material.dart';

import 'src/aip/aip_registry.dart';
import 'src/data/chart_store.dart';
import 'src/ui/airports_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ChartStore.open();
  runApp(ImgMapApp(store: store));
}

class ImgMapApp extends StatelessWidget {
  ImgMapApp({super.key, required this.store, AipRegistry? registry})
    : registry = registry ?? AipRegistry();

  final ChartStore store;
  final AipRegistry registry;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1E5AA8);
    return MaterialApp(
      title: 'ImgMap',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: AirportsScreen(store: store, registry: registry),
    );
  }
}
