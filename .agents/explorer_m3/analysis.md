# Analysis: Implementing Resizing State Transitions

This document provides a comprehensive analysis and implementation plan for introducing Resizing State Transitions within the screen translator overlay window.

---

## 1. Class and Methods Managing Translation States

In `lib/main.dart`, the overlay window's user interface, lifecycle, and resizing behavior are encapsulated within the following widgets and state management classes:

### Core Classes
*   **`OverlayWindowScreen`** (`StatefulWidget`): The entry point for the overlay window layout, bootstrapped in `overlayMain()`.
*   **`_OverlayWindowScreenState`** (`State`): Manages the internal overlay states, handles communication from the main isolate via `OverlayBridge`, and interacts with the platform channels via `FlutterOverlayWindow`.

### Key State Fields in `_OverlayWindowScreenState`
*   `bool _isTranslating`: Tracks if a translation loop is running (i.e. capturing or waiting for ML processing). When `true`, it replaces the trigger icon with a circular progress indicator.
*   `bool _showTranslationLayer`: Tracks whether the overlay displays the interactive translation layer (`true`) or the compact FAB trigger button (`false`).
*   `List<TranslatedBlock> _translations`: The translation blocks extracted and translated by the main isolate.
*   `Size _imageSize`: Stores the dimensions of the screen capture image, used to scale translation coordinates.
*   `String? _errorMessage`: Holds temporary error messages to be displayed in a popup banner.

### State Transition Methods
1.  **`initState()`**:
    *   Subscribes to `OverlayBridge.messages`.
    *   Listens for platform messages containing the status (`success`, `no_text`, or `error`) from the main app isolate.
    *   Upon receiving `success`, it extracts translation boxes, sets `_showTranslationLayer = true`, and resizes the window to full-screen:
        ```dart
        final int widthDp = (imageWidth / devicePixelRatio).round();
        final int heightDp = (imageHeight / devicePixelRatio).round();
        FlutterOverlayWindow.resizeOverlay(widthDp, heightDp, false);
        ```
2.  **`_startTranslationFlow()`**:
    *   Called when the user taps the trigger button.
    *   Sets `_isTranslating = true` and resets error messages.
    *   Starts a 15-second watchdog watchdog timer (`_translationTimeoutTimer`) that fails the flow if the main app is unresponsive.
    *   Requests the main app to capture/process by sending a `"capture"` message via `OverlayBridge.send("capture")`.
3.  **`_closeTranslationLayer()`**:
    *   Called when the close button is tapped or a swipe-up gesture is detected.
    *   Sets `_showTranslationLayer = false` and clears translations.
    *   Restores the overlay window to its small trigger dimensions (140x140) and enables dragging:
        ```dart
        await FlutterOverlayWindow.resizeOverlay(140, 140, true);
        ```

---

## 2. Implementing the Resizing State Transitions

To prevent the overlay trigger button from appearing in the screen capture itself, the overlay window must temporarily shrink to `1x1` before the capture is initiated and restore its size once the capture concludes.

### The Problem
When the user taps the overlay trigger button, the capture request is sent to the main app isolate immediately. Because the overlay is 140x140 and drawn over the target screen, it is captured in the screenshot.

### The Solution: 1x1 Resize & 100ms Delay
1.  **Shrink overlay**: As soon as `_startTranslationFlow()` is entered, resize the overlay to `1x1` pixels.
2.  **Allow window transition**: Delay execution by 100ms using a `Future.delayed` timer, giving the Android WindowManager time to hide the overlay.
3.  **Perform capture**: Trigger `OverlayBridge.send("capture")`.
4.  **Restore overlay size**:
    *   **Success**: Resize to fullscreen (handled by the existing `success` payload callback).
    *   **No Text**: Resize back to `140x140` with `enableDrag = true` in the `no_text` callback.
    *   **Error**: Resize back to `140x140` with `enableDrag = true` in the `error` callback.
    *   **Watchdog Timeout**: Resize back to `140x140` with `enableDrag = true` when the 15-second watchdog timer expires.

### Proposed Code Changes in `lib/main.dart`

```dart
// Modify _startTranslationFlow()
Future<void> _startTranslationFlow() async {
  if (_isTranslating) return;
  setState(() {
    _isTranslating = true;
    _errorMessage = null;
  });

  // Start watchdog timer
  _translationTimeoutTimer?.cancel();
  _translationTimeoutTimer = Timer(const Duration(seconds: 15), () {
    if (mounted && _isTranslating) {
      setState(() {
        _isTranslating = false;
        _errorMessage = "Timeout. Please open the main app.";
      });
      // Watchdog restoration back to 140x140
      FlutterOverlayWindow.resizeOverlay(140, 140, true);
      _errorTimer?.cancel();
      _errorTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      });
    }
  });

  // 1. Shrink overlay to 1x1 to clear the screen for screen capture
  try {
    await FlutterOverlayWindow.resizeOverlay(1, 1, false);
  } catch (e) {
    debugPrint("[Overlay] Failed to shrink overlay: $e");
  }

  // 2. Wait 100ms for OS WindowManager to update layout
  await Future.delayed(const Duration(milliseconds: 100));

  // 3. Request capture
  try {
    await OverlayBridge.send("capture");
  } catch (e) {
    debugPrint("[Overlay] OverlayBridge.send ERROR: $e");
  }
}
```

```dart
// Modify initState() overlay bridge subscription callback to handle failures restoration
_overlaySubscription = OverlayBridge.messages.listen((data) {
  _translationTimeoutTimer?.cancel();
  if (data is Map) {
    if (data["status"] == "no_text") {
      setState(() {
        _isTranslating = false;
        _translations = [];
        _showTranslationLayer = false;
        _errorMessage = null;
      });
      // Restore size back to 140x140 on no_text
      FlutterOverlayWindow.resizeOverlay(140, 140, true);
    } else if (data["status"] == "error") {
      setState(() {
        _isTranslating = false;
        _translations = [];
        _showTranslationLayer = false;
        _errorMessage = data["message"] as String?;
      });
      _errorTimer?.cancel();
      _errorTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      });
      // Restore size back to 140x140 on error
      FlutterOverlayWindow.resizeOverlay(140, 140, true);
    } else if (data["status"] == "success") {
      // Existing success resizing logic ...
      final int widthDp = (imageWidth / devicePixelRatio).round();
      final int heightDp = (imageHeight / devicePixelRatio).round();
      FlutterOverlayWindow.resizeOverlay(widthDp, heightDp, false);
    }
  }
});
```

---

## 3. Mocking and Spying on Overlay Resizing in Widget Tests

Since `FlutterOverlayWindow.resizeOverlay` communicates with native code via a `MethodChannel`, we can intercept and spy on these channel calls using the standard Flutter testing framework.

### Setup Mock Platform Channels
1.  **Define MethodChannels**:
    ```dart
    const overlayChannel = MethodChannel('x-slayer/overlay');
    ```
2.  **Define Call Log**:
    ```dart
    final List<MethodCall> log = [];
    ```
3.  **Register Mock Handler**:
    ```dart
    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(overlayChannel, (MethodCall methodCall) async {
        log.add(methodCall);
        return true; // Return mock response expected by plugin
      });
    });
    ```

### Asserting on Resizing Events
To verify that the correct resize operations occurred, inspect the `log` list:
```dart
// Check if 1x1 resize was requested
final shrinkCall = log.firstWhere((call) => call.method == 'resizeOverlay');
expect(shrinkCall.arguments['width'], equals(1));
expect(shrinkCall.arguments['height'], equals(1));
expect(shrinkCall.arguments['enableDrag'], isFalse);

// Check if 140x140 restoration was requested
final restoreCall = log.lastWhere((call) => call.method == 'resizeOverlay');
expect(restoreCall.arguments['width'], equals(140));
expect(restoreCall.arguments['height'], equals(140));
expect(restoreCall.arguments['enableDrag'], isTrue);
```

---

## 4. Designing Widget Tests for Resize Transitions

The following widget tests should be written in a new file `test/overlay_resize_transition_test.dart` (or appended to `test/overlay_dismissal_test.dart`) to verify the state machine behavior and method channel calls.

### A. Successful Translation Loop Test
*   **Goal**: Verifies that pressing the FAB shrinks the overlay to 1x1, delays, and then expands it to fullscreen on receiving success.
*   **Test Steps**:
    1.  Render `OverlayWindowScreen`.
    2.  Tap the `g_translate` trigger button.
    3.  Assert `resizeOverlay(1, 1, false)` is logged.
    4.  Advance the clock by 100ms via `tester.pump(const Duration(milliseconds: 100))`.
    5.  Simulate `success` status payload sent from the bridge.
    6.  Call `tester.pumpAndSettle()`.
    7.  Assert that `resizeOverlay` was called with device-pixel-ratio fullscreen dimensions, and translations are shown.

### B. Failed Translation Loop Test (No Text Found)
*   **Goal**: Verifies that when OCR finds no text, the overlay restores to 140x140.
*   **Test Steps**:
    1.  Render `OverlayWindowScreen`.
    2.  Tap the `g_translate` trigger button.
    3.  Assert `resizeOverlay(1, 1, false)` is logged.
    4.  Advance the clock by 100ms.
    5.  Simulate `no_text` status payload sent from the bridge.
    6.  Call `tester.pumpAndSettle()`.
    7.  Assert that `resizeOverlay(140, 140, true)` is logged, and the trigger button is visible again.

### C. Failed Translation Loop Test (Error Display)
*   **Goal**: Verifies that on an OCR/translation error, the overlay restores to 140x140 and displays the error banner.
*   **Test Steps**:
    1.  Render `OverlayWindowScreen`.
    2.  Tap the `g_translate` trigger button.
    3.  Assert `resizeOverlay(1, 1, false)` is logged.
    4.  Advance the clock by 100ms.
    5.  Simulate `error` status payload containing a message `"Capture failed: OCR Timeout"`.
    6.  Call `tester.pumpAndSettle()`.
    7.  Assert that `resizeOverlay(140, 140, true)` is logged, the trigger button is visible, and the error text is rendered on-screen.

### D. Watchdog Timeout Restoration Test
*   **Goal**: Verifies that if the main app does not respond within 15 seconds, the overlay restores to 140x140 and shows a timeout error.
*   **Test Steps**:
    1.  Render `OverlayWindowScreen`.
    2.  Tap the `g_translate` trigger button.
    3.  Assert `resizeOverlay(1, 1, false)` is logged.
    4.  Advance clock by 15 seconds: `await tester.pump(const Duration(seconds: 15));`.
    5.  Assert that `resizeOverlay(140, 140, true)` is logged, the trigger button is visible, and the timeout message is displayed.

### Sample Test Implementation Code

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_translate/main.dart';
import 'package:screen_translate/overlay_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const overlayChannel = MethodChannel('x-slayer/overlay');
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
        .setMockMethodCallHandler(bridgeChannel, (MethodCall methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'send') {
        // Forward message to the overlay listeners
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
        .setMockMethodCallHandler(bridgeChannel, null);
  });

  testWidgets('Successful translation loop: shrinks, delays, expands to fullscreen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // Tap the translate button to start the flow
    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(); // Start execution

    // Verify overlay immediately shrunk to 1x1
    final shrinkCall = log.firstWhere((call) => call.method == 'resizeOverlay');
    expect(shrinkCall.arguments['width'], equals(1));
    expect(shrinkCall.arguments['height'], equals(1));
    expect(shrinkCall.arguments['enableDrag'], isFalse);

    // Wait 100ms for delay to complete
    await tester.pump(const Duration(milliseconds: 100));

    // Send successful response
    await OverlayBridge.send({
      "status": "success",
      "translations": [
        {"text": "Subtitles", "rect": [10.0, 10.0, 100.0, 50.0]}
      ],
      "imageWidth": 1080.0,
      "imageHeight": 1920.0,
    });
    await tester.pumpAndSettle();

    // Verify it resized to fullscreen (devicePixelRatio is default 1.0 in test)
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2));
    expect(resizeCalls[1].arguments['width'], equals(1080));
    expect(resizeCalls[1].arguments['height'], equals(1920));
    expect(resizeCalls[1].arguments['enableDrag'], isFalse);
  });

  testWidgets('Failed loop: no text found shrinks then restores to 140x140', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 100));

    // Simulate "no_text"
    await OverlayBridge.send({"status": "no_text"});
    await tester.pumpAndSettle();

    // Verify restoration call
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2)); // shrink + restore
    expect(resizeCalls[1].arguments['width'], equals(140));
    expect(resizeCalls[1].arguments['height'], equals(140));
    expect(resizeCalls[1].arguments['enableDrag'], isTrue);
  });

  testWidgets('Failed loop: error status shrinks, restores, and shows message', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 100));

    // Simulate "error"
    await OverlayBridge.send({
      "status": "error",
      "message": "Connection broken"
    });
    await tester.pumpAndSettle();

    // Verify restoration call and error presentation
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2));
    expect(resizeCalls[1].arguments['width'], equals(140));
    expect(resizeCalls[1].arguments['height'], equals(140));
    expect(resizeCalls[1].arguments['enableDrag'], isTrue);
    expect(find.text("Connection broken"), findsOneWidget);
  });

  testWidgets('Watchdog timeout: shrinks, triggers restoration after 15s', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 100));

    // Advance clock past 15 seconds watchdog limit
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    // Verify timeout fired, resized to 140x140, and showed message
    final resizeCalls = log.where((call) => call.method == 'resizeOverlay').toList();
    expect(resizeCalls.length, equals(2));
    expect(resizeCalls[1].arguments['width'], equals(140));
    expect(resizeCalls[1].arguments['height'], equals(140));
    expect(resizeCalls[1].arguments['enableDrag'], isTrue);
    expect(find.text("Timeout. Please open the main app."), findsOneWidget);
  });
}
```
