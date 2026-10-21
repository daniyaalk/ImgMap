import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imgmap/main.dart';
import 'package:imgmap/src/aip/aip_registry.dart';
import 'package:imgmap/src/data/chart_store.dart';
import 'package:imgmap/src/data/storage_memory.dart';
import 'package:imgmap/src/ui/disclaimer.dart';

void main() {
  testWidgets(
    'the disclaimer must be accepted once, then stays out of the way',
    (tester) async {
      final storage = MemoryChartStorage();
      var store = await ChartStore.open(storage: storage);
      await tester.pumpWidget(ImgMapApp(store: store, registry: AipRegistry()));
      await tester.pump();

      expect(find.text('Before you start'), findsOneWidget);
      expect(
        find.textContaining('Never use this for actual navigation'),
        findsOneWidget,
      );
      expect(find.textContaining(contactEmail), findsOneWidget);
      expect(find.text('Airports'), findsNothing);

      // On a small screen the button is below the text: scroll to it, as a
      // reader would. Continue does nothing until the user confirms.
      await tester.scrollUntilVisible(find.text('Continue'), 200);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Airports'), findsNothing);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Airports'), findsOneWidget);
      expect(store.disclaimerAccepted, disclaimerVersion);

      // Readable again from the home screen.
      await tester.tap(find.byTooltip('About & disclaimer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Never use this for actual navigation'),
        findsOneWidget,
      );

      // Remembered: the next launch goes straight to the app.
      await tester.pumpWidget(const SizedBox());
      store = await ChartStore.open(storage: storage);
      await tester.pumpWidget(ImgMapApp(store: store, registry: AipRegistry()));
      await tester.pump();
      expect(find.text('Before you start'), findsNothing);
      expect(find.text('Airports'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
