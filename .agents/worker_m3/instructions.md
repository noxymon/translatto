# Worker Instructions - Milestone 3

You are the worker for Milestone 3: Resizing State Transitions.
Your task is to modify the overlay window capturing flow in `lib/main.dart` and update `test/overlay_dismissal_test.dart` to verify these resizing transitions.

## Requirements:
1. In `lib/main.dart`, update `_startTranslationFlow()`:
   - Call `FlutterOverlayWindow.resizeOverlay(1, 1, false)` immediately when the translation flow starts. Wrap it in a `try-catch` to avoid failing on platform channel exceptions.
   - Wait 100 milliseconds: `await Future.delayed(const Duration(milliseconds: 100));`.
   - Call `OverlayBridge.send("capture")`.
2. In `lib/main.dart`, update the `OverlayBridge.messages.listen` callback inside `initState()` and the `_translationTimeoutTimer` watchdog:
   - When receiving `no_text`, call `FlutterOverlayWindow.resizeOverlay(140, 140, true)`.
   - When receiving `error`, call `FlutterOverlayWindow.resizeOverlay(140, 140, true)`.
   - In the watchdog timer callback (when 15 seconds expires), call `FlutterOverlayWindow.resizeOverlay(140, 140, true)`.
3. Update `test/overlay_dismissal_test.dart` to add widget tests verifying:
   - Tapping the trigger FAB immediately triggers `resizeOverlay(1, 1, false)`.
   - After a successful flow, it resizes to fullscreen.
   - After a `no_text` flow, it restores to `140x140`.
   - After an `error` flow, it restores to `140x140` and displays the error message.
   - When the 15-second watchdog timeout fires, it restores to `140x140` and displays the timeout message.
4. Verify that running `flutter test test/overlay_dismissal_test.dart` succeeds.

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
