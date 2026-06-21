# Translatto - Screen Translator Project Context

## Commands & Workflows

### Setup & Deployment
*   **Push Model File to Device**:
    ```bash
    make push-model DEVICE_ID=<device_id>
    ```
    Pushes `gemma-4-E2B-it.litertlm` from host machine to the application private documents directory.

### Build & Run
*   **Debug Mode**:
    ```bash
    make debug DEVICE_ID=<device_id>
    ```
    Runs application in debug mode on connected device.
*   **Build Release APK**:
    ```bash
    make release
    ```
    Compiles release APK to `build/app/outputs/flutter-apk/app-release.apk`.
*   **Install Release APK**:
    ```bash
    make install-release DEVICE_ID=<device_id>
    ```
    Installs built release APK onto connected device.

### Verification
*   **Run Test Suite**:
    ```bash
    flutter test
    ```
*   **Run Static Analyzer**:
    ```bash
    flutter analyze
    ```

---

## Architecture & Codebase Map

### Core Layout
*   [lib/main.dart](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/main.dart): Defines main entry point `main()`, main dashboard screen `MainDashboardScreen`, overlay entry point `overlayMain()`, and overlay window screen `OverlayWindowScreen`.
*   [lib/ocr_service.dart](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/ocr_service.dart): Google ML Kit text recognition handler. Performs text block extraction and vertical/horizontal merging.
*   [lib/translation_service.dart](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/translation_service.dart): Manages local `flutter_gemma` inference sessions. Formats XML batch prompts and caches translations to minimize latency.
*   [lib/capture_service.dart](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/capture_service.dart): MethodChannel interfaces with Kotlin for screen frame captures, app minimization, and battery settings checking.
*   [lib/overlay_painter.dart](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/overlay_painter.dart): Renders AR overlay translated block painter, performing collision adjustments and dynamic line-height font scaling.

### Android Native Layer
*   [MainActivity.kt](file:///Users/haikalannisa/Documents/Code/screen-translate/android/app/src/main/kotlin/id/web/noxymon/translatto/MainActivity.kt): Registers Flutter method channel handlers, intercepts overlay requests, and launches screen projection permissions.
*   [MediaProjectionService.kt](file:///Users/haikalannisa/Documents/Code/screen-translate/android/app/src/main/kotlin/id/web/noxymon/translatto/MediaProjectionService.kt): Foreground service managing VirtualDisplay frame output to ImageReader, feeding compressed JPEG frames back to Dart.

---

## Gotchas & Technical Constraints

1.  **Android 14+ Foreground Service**: FGS type `mediaProjection` must be declared in manifest and started *after* displaying notification, otherwise OS throws `SecurityException`.
2.  **Isolate Plugin Binding Limits**: Flutter plugins (Gemma, ML Kit) crash if run on background/overlay isolates due to missing platform channel bindings. Heavy ML processing occurs on main isolate; overlay isolate receives translation layouts via bridge.
3.  **Battery Optimization Ignores**: Stable background capture requires ignoring battery optimization. Triggers ignore intent via `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission.
4.  **Repaint Avoidance**: Repaints on CustomPainter are performance bottlenecks. repaints occur only if `TranslatedBlock` coordinates or counts differ (overridden `==` and `hashCode`).
5.  **Dynamic Font Sizing**: Renders translated text sized at `(scaledLineHeight * 0.70).clamp(8.0, 48.0)` using the original text's line split count to fit target height bounds.
