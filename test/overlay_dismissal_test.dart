import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_translate/main.dart';
import 'package:screen_translate/overlay_bridge.dart';
import 'package:screen_translate/overlay_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const overlayChannel = MethodChannel('x-slayer/overlay');
  const overlayMainChannel = MethodChannel('x-slayer/overlay_channel');
  const bridgeChannel = MethodChannel('id.web.noxymon.translatto/overlay_bridge');
  final List<MethodCall> log = [];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(overlayChannel, (MethodCall methodCall) async {
      log.add(methodCall);
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(overlayMainChannel, (MethodCall methodCall) async {
      log.add(methodCall);
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridgeChannel, (MethodCall methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'send') {
        // Forward message back to the listener on 'onMessage' method
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          'id.web.noxymon.translatto/overlay_bridge',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onMessage', methodCall.arguments),
          ),
          null,
        );
      }
      return null;
    });
    OverlayBridge.init();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(overlayChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(overlayMainChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridgeChannel, null);
  });

  testWidgets('Overlay dismissal Close FAB and swipe-up triggers resizing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // 1. Initially, it shows the FAB trigger (not the translation layer)
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.g_translate), findsOneWidget);

    // 2. Simulate success message from bridge
    await OverlayBridge.send({
      "status": "success",
      "translations": [
        {
          "text": "Hello",
          "rect": [10.0, 10.0, 100.0, 50.0]
        }
      ],
      "imageWidth": 1080.0,
      "imageHeight": 1920.0,
    });
    await tester.pumpAndSettle();

    // 3. Now the translation layer is shown, verify FAB (mini Close) is present
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // 4. Tap the Close button
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify that resizeOverlay(140, 140, true) was called
    final resizeCall = log.lastWhere((call) => call.method == 'resizeOverlay');
    expect(resizeCall.arguments['width'], equals(140));
    expect(resizeCall.arguments['height'], equals(140));
    expect(resizeCall.arguments['enableDrag'], isTrue);
  });

  testWidgets('Overlay dismissal swipe-up triggers resizing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // 1. Simulate success message from bridge
    await OverlayBridge.send({
      "status": "success",
      "translations": [
        {
          "text": "Hello",
          "rect": [10.0, 10.0, 100.0, 50.0]
        }
      ],
      "imageWidth": 1080.0,
      "imageHeight": 1920.0,
    });
    await tester.pumpAndSettle();

    // 2. Drag/Swipe up
    final finder = find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is OverlayPainter);
    await tester.fling(finder, const Offset(0, -300), 1000.0);
    await tester.pumpAndSettle();

    // Verify that resizeOverlay(140, 140, true) was called
    final resizeCall = log.lastWhere((call) => call.method == 'resizeOverlay');
    expect(resizeCall.arguments['width'], equals(140));
    expect(resizeCall.arguments['height'], equals(140));
    expect(resizeCall.arguments['enableDrag'], isTrue);
  });

  testWidgets('Overlay dismissal does NOT trigger when tapping elsewhere', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // 1. Simulate success message from bridge
    await OverlayBridge.send({
      "status": "success",
      "translations": [
        {
          "text": "Hello",
          "rect": [10.0, 10.0, 100.0, 50.0]
        }
      ],
      "imageWidth": 1080.0,
      "imageHeight": 1920.0,
    });
    await tester.pumpAndSettle();

    // 2. Tap elsewhere on the CustomPaint translation layer
    final finder = find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is OverlayPainter);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    // Verify that the ONLY resizeOverlay call was the initial one (to fullscreen), and no dismissal resize (140x140) was sent
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(1));
    expect(resizeCalls.first.arguments['width'], isNot(equals(140)));
  });
}
