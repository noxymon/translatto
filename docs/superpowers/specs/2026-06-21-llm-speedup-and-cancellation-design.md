# Design Spec: LLM Speedup and Cancellation

This document outlines the design for local LLM inference acceleration (GPU backend + compressed prompts) and the user cancellation flow when the overlay is in a spinning state.

## 1. Goal
1. Increase request watchdog timeout from 45 seconds to 120 seconds.
2. Allow users to cancel active OCR & translation operations by clicking the overlay spinner button.
3. Speed up local LLM inference on devices with Qualcomm Snapdragon 870 (Adreno 650 GPU) using GPU acceleration.
4. Reduce LLM prefill processing time by compressing instructions in the batch translation XML prompt.

## 2. Technical Details

### A. Cancellation Flow
- **Overlay State Management**:
  - The floating action button (FAB) changes to a `CircularProgressIndicator` when `_isTranslating` is true.
  - Tapping this spinner triggers `_startTranslationFlow()`. We modify the handler:
    ```dart
    if (_isTranslating) {
      _cancelTranslationFlow();
      return;
    }
    ```
  - `_cancelTranslationFlow()` sets `_isTranslating = false`, cancels `_translationTimeoutTimer`, resizes overlay back to `140x140` with `enableDrag: true`, and sends `"cancel"` across `OverlayBridge`.
- **Main Isolate Execution Guard**:
  - Tracks state via `bool _cancelRequested = false`.
  - On receiving `"cancel"` via `OverlayBridge`, sets `_cancelRequested = true`.
  - Checks `_cancelRequested` at critical boundaries:
    - Before capturing screen
    - Before starting OCR
    - Before batch translation
    - Between sequential fallback loops
  - If cancellation is detected, aborts cleanly and resets state without sending error messages.

### B. Prolonged Watchdog Timeout
- Increases the watchdog watchdog timer in `_startTranslationFlow()` to `120` seconds.

### C. GPU Acceleration
- Initializing local Gemma:
  ```dart
  try {
    _model = await FlutterGemma.getActiveModel(
      maxTokens: 256,
      preferredBackend: PreferredBackend.gpu,
    );
  } catch (e) {
    debugPrint("Failed to initialize GPU backend: $e. Falling back to CPU.");
    _model = await FlutterGemma.getActiveModel(
      maxTokens: 256,
      preferredBackend: PreferredBackend.cpu,
    );
  }
  ```

### D. Prompt Compression
- Compresses the instructions template:
  ```
  Translate Japanese UI text blocks to English. Use (x,y) for layout context.
  Format: <t id="N">translation</t>
  Output only XML tags. No notes.
  ```

## 3. Review Checklist
- [x] Zero placeholders or TODOs.
- [x] Compilation safety via fallbacks.
- [x] Test coverage for cancellation triggers.
