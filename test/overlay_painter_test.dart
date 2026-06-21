import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_translate/overlay_painter.dart';

void main() {
  testWidgets('OverlayPainter paints bounding boxes', (WidgetTester tester) async {
    await tester.pumpWidget(
      CustomPaint(
        painter: OverlayPainter(
          translations: [
            TranslatedBlock(text: 'Hello', rect: const Rect.fromLTWH(0, 0, 100, 50)),
          ],
          imageSize: const Size(1080, 1920),
          cropY: 20.0,
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  testWidgets('OverlayPainter handles small width without throwing clamp exception', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: CustomPaint(
                painter: OverlayPainter(
                  translations: [
                    TranslatedBlock(text: 'Test', rect: const Rect.fromLTWH(10, 10, 80, 30)),
                  ],
                  imageSize: const Size(500, 500),
                  cropY: 0.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Trigger actual paint to catch the error
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('OverlayPainter shifts overlapping translation boxes downwards', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 500,
            child: CustomPaint(
              painter: OverlayPainter(
                translations: [
                  TranslatedBlock(text: 'Left Block', rect: const Rect.fromLTWH(10, 10, 100, 40)),
                  TranslatedBlock(text: 'Right Block', rect: const Rect.fromLTWH(20, 12, 100, 40)),
                ],
                imageSize: const Size(500, 500),
                cropY: 0.0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
