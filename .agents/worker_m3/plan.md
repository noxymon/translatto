# Implementation Plan - Resizing State Transitions

## 1. Modify lib/main.dart
### 1.1 Update _startTranslationFlow()
- Call `FlutterOverlayWindow.resizeOverlay(1, 1, false)` immediately when the translation flow starts, wrapped in `try-catch`.
- Add `await Future.delayed(const Duration(milliseconds: 100));` to wait 100 milliseconds.
- Then call `OverlayBridge.send("capture")`.

### 1.2 Update initState() and Watchdog Timer
- Inside the `no_text` block in `initState()`, add `FlutterOverlayWindow.resizeOverlay(140, 140, true);`.
- Inside the `error` block in `initState()`, add `FlutterOverlayWindow.resizeOverlay(140, 140, true);`.
- Inside the 15-second watchdog timer callback in `_startTranslationFlow()`, add `FlutterOverlayWindow.resizeOverlay(140, 140, true);`.

## 2. Update test/overlay_dismissal_test.dart
- Add widget tests verification:
  - Verify tapping the trigger FAB immediately triggers `resizeOverlay(1, 1, false)`.
  - Verify after a successful flow, it resizes to fullscreen.
  - Verify after a `no_text` flow, it restores to `140x140`.
  - Verify after an `error` flow, it restores to `140x140` and displays the error message.
  - Verify watchdog timeout fires after 15 seconds, restoring to `140x140` and displaying the timeout message.

## 3. Verify
- Run `flutter test test/overlay_dismissal_test.dart` and ensure all tests pass.
