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
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
