import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_translate/main.dart';

void main() {
  testWidgets('Dashboard UI renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify title and main widgets are rendered
    expect(find.text('Screen Translator'), findsOneWidget);
    expect(find.text('Local Model'), findsOneWidget);
    expect(find.text('Grant Overlay Permission'), findsOneWidget);
    expect(find.text('Start Screen Overlay'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}

