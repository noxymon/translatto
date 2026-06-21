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
      if (methodCall.method == 'send' && methodCall.arguments != 'capture') {
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

  testWidgets('Tapping trigger FAB immediately triggers resizeOverlay(1, 1, false)', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // Tap trigger FAB
    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(); // Start execution

    // Check that we immediately called resizeOverlay(1, 1, false)
    final shrinkCall = log.firstWhere((call) => call.method == 'resizeOverlay');
    expect(shrinkCall.arguments['width'], equals(1));
    expect(shrinkCall.arguments['height'], equals(1));
    expect(shrinkCall.arguments['enableDrag'], isFalse);

    // Clean up: wait 100ms for delay to complete, then cancel the watchdog timer
    await tester.pump(const Duration(milliseconds: 100));
    await OverlayBridge.send({"status": "no_text"});
    await tester.pumpAndSettle();
  });

  testWidgets('Successful translation flow resizes to fullscreen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // Tap trigger FAB and wait 100ms
    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 100));

    // Send success
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

    // Verify it resized to fullscreen (accounting for test environment devicePixelRatio)
    final BuildContext context = tester.element(find.byType(OverlayWindowScreen));
    final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2));
    expect(resizeCalls[1].arguments['width'], equals((1080.0 / devicePixelRatio).round()));
    expect(resizeCalls[1].arguments['height'], equals((1920.0 / devicePixelRatio).round()));
    expect(resizeCalls[1].arguments['enableDrag'], isFalse);
  });

  testWidgets('Failed loop: no text found restores to 140x140', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // Tap trigger FAB and wait 100ms
    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 100));

    // Simulate "no_text"
    await OverlayBridge.send({"status": "no_text"});
    await tester.pumpAndSettle();

    // Verify restoration call
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2)); // shrink (1x1) + restore (140x140)
    expect(resizeCalls[1].arguments['width'], equals(140));
    expect(resizeCalls[1].arguments['height'], equals(140));
    expect(resizeCalls[1].arguments['enableDrag'], isTrue);
  });

  testWidgets('Failed loop: error status restores to 140x140 and displays the error message', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // Tap trigger FAB and wait 100ms
    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 100));

    // Simulate "error"
    await OverlayBridge.send({
      "status": "error",
      "message": "OCR failed"
    });
    await tester.pump(); // Render state with error message

    // Verify restoration call
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2));
    expect(resizeCalls[1].arguments['width'], equals(140));
    expect(resizeCalls[1].arguments['height'], equals(140));
    expect(resizeCalls[1].arguments['enableDrag'], isTrue);

    // Verify error text is displayed
    expect(find.text("OCR failed"), findsOneWidget);

    // Clean up: let the 4-second message timer complete
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Watchdog timeout: restores to 140x140 and displays the timeout message after 15s', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // Tap trigger FAB and wait 100ms
    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 100));

    // Advance clock past 15 seconds watchdog limit
    await tester.pump(const Duration(seconds: 15));

    // Verify watchdog restoration call
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2));
    expect(resizeCalls[1].arguments['width'], equals(140));
    expect(resizeCalls[1].arguments['height'], equals(140));
    expect(resizeCalls[1].arguments['enableDrag'], isTrue);

    // Verify timeout message is displayed
    expect(find.text("Timeout. Please open the main app."), findsOneWidget);

    // Clean up: let the 4-second message timer complete
    await tester.pump(const Duration(seconds: 4));
  });
}
