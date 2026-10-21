import 'package:flutter/material.dart';

import 'src/aip/aip_registry.dart';
import 'src/aip/backend.dart';
import 'src/data/chart_store.dart';
import 'src/location/app_location.dart';
import 'src/location/location_controller.dart';
import 'src/ui/airports_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ChartStore.open();
  // Countries come from the backend; the cached list is used until it
  // answers, and offline.
  final registry = await AipRegistry.load(Backend(), store.storage);
  runApp(ImgMapApp(store: store, registry: registry));
}

class ImgMapApp extends StatelessWidget {
  ImgMapApp({super.key, required this.store, AipRegistry? registry})
    : registry = registry ?? AipRegistry();

  final ChartStore store;
  final AipRegistry registry;
  final LocationController _location = LocationController();

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
      // One location session for the whole app, started on the home
      // screen so maps open with a fix.
      builder: (context, child) =>
          AppLocation(controller: _location, child: child!),
      home: AirportsScreen(store: store, registry: registry),
    );
  }
}
