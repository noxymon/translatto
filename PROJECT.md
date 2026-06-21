# Project: screen-translate

## Architecture
- **Kotlin Layer**: Platform-specific implementation for capturing the screen using Android's MediaProjection API (`MediaProjectionService.kt`).
- **Dart/Flutter Layer**: Overlay UI window, OCR logic (`ocr_service.dart`), translation engine coordination, and custom overlay painters.
- **Bridge Layer**: Platform channel (`OverlayBridge`) for IPC between the main app, overlay window, and Kotlin service.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Screenshot Status Bar Cropping | Query status bar height in Kotlin; crop status bar area off captured screenshot bitmap; return cropped dimensions. | None | DONE |
| 2 | OCR Block Merging | Implement OCR block grouping/merging heuristics in Dart; write unit tests verifying merging/expansion. | M1 | DONE |
| 3 | Resizing State Transitions | Implement 1x1 resize flow, 100ms delay, and restore logic; write widget tests verifying transitions. | M2 | DONE |
| 4 | Integration Verification | Verify full system correctness; run and pass all unit/widget tests; run `flutter analyze`. | M1, M2, M3 | DONE |

## Interface Contracts
### MediaProjectionService (Kotlin) ↔ Dart Capture Service
- **Channel**: `OverlayBridge` / Method Channel
- **Inputs**: Capture request triggers screenshot.
- **Outputs**: Cropped image bytes, cropped width, cropped height (height excluding status bar).

## Code Layout
- Android Kotlin Code: `android/app/src/main/kotlin/id/web/noxymon/translatto/MediaProjectionService.kt`
- Capture Service: `lib/capture_service.dart`
- OCR Service: `lib/ocr_service.dart`
- Overlay UI: `lib/main.dart`
- Tests: `test/`
