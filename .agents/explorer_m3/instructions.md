# Explorer Instructions - Milestone 3

You are the explorer for Milestone 3: Resizing State Transitions.
Your task is to explore how `lib/main.dart` or overlay classes execute the overlay capture trigger and window resizing, and how to add widget tests for the 1x1 resize and restoration flow.

Find:
1. Where the floating action button (FAB) or translation trigger is defined, and where the capture is initiated.
2. How `FlutterOverlayWindow.resizeOverlay` is called and imported.
3. Where widget tests for the overlay and FAB are located (e.g. `test/widget_test.dart` or `test/overlay_dismissal_test.dart`).
4. Outline the exact implementation plan for:
   - Setting `_isTranslating = true` and immediately resizing overlay to 1x1.
   - Introducing a 100ms delay.
   - Restoring size to fullscreen on success, or 140x140 on error/no-text.
   - Writing widget tests that verify the resizing states using mock/fake platform channels.

Write your analysis to `analysis.md` in this directory and send a handoff message to the parent with the path.
