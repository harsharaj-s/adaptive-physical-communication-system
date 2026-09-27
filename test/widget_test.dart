import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/main.dart';
import 'package:adaptive_physical_communication/ui/screens/home_screen.dart';

void main() {
  testWidgets('home screen renders send and receive', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AdaptiveCommApp());
    await tester.pumpAndSettle();

    expect(find.text(HomeScreen.appName), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Simulation Lab'), findsNothing);
  });
}
