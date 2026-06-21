# LLM Speedup and Cancellation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prolong request watchdog timeout, enable user cancel tap on spinner FAB, and optimize local LLM inference via GPU acceleration and prompt compression.

**Architecture:** 
The overlay FAB intercepts taps during active translation flows to trigger dismissal. The main isolate checks for cancellation state using shared flags, aborting OCR/LLM loops early. Local Gemma initializes with a GPU preferred backend with CPU fallback, and utilizes compressed XML prompt instructions to reduce latency.

**Tech Stack:** Flutter, flutter_gemma, google_mlkit_text_recognition

---

### Task 1: watchdog timeout and cancel button UI

**Files:**
- Modify: `lib/main.dart:488-535`
- Test: `test/overlay_dismissal_test.dart`

- [ ] **Step 1: Update timeout to 120 seconds and implement cancel tap branch**
  Update the duration inside `_startTranslationFlow` to `120` seconds, and handle the cancellation action when tapping while translating.
  ```dart
  Future<void> _startTranslationFlow() async {
    debugPrint("[Overlay] _startTranslationFlow() called. _isTranslating=$_isTranslating");
    if (_isTranslating) {
      _cancelTranslationFlow();
      return;
    }
    setState(() {
      _isTranslating = true;
      _errorMessage = null;
    });

    _translationTimeoutTimer?.cancel();
    _translationTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (mounted && _isTranslating) {
        setState(() {
          _isTranslating = false;
          _errorMessage = "Timeout. Please open the main app.";
        });
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
    // ...
  }

  Future<void> _cancelTranslationFlow() async {
    debugPrint("[Overlay] Cancelling translation flow.");
    _translationTimeoutTimer?.cancel();
    setState(() {
      _isTranslating = false;
    });
    try {
      await FlutterOverlayWindow.resizeOverlay(140, 140, true);
    } catch (e) {
      debugPrint("[Overlay] Failed to resize overlay: $e");
    }
    try {
      await OverlayBridge.send("cancel");
    } catch (e) {
      debugPrint("[Overlay] Failed to send cancel request: $e");
    }
  }
  ```

- [ ] **Step 2: Add test verifying cancel click restores FAB size and sends cancel message**
  Add a widget test in `test/overlay_dismissal_test.dart`:
  ```dart
  testWidgets('Tapping spinner FAB during translation cancels flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: OverlayWindowScreen(),
    ));

    // Start translation flow
    await tester.tap(find.byIcon(Icons.g_translate));
    await tester.pump(const Duration(milliseconds: 10));

    // Spinner should render instead of standard translate icon
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Tap spinner (cancels flow)
    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    // Verify resizeOverlay(140, 140, true) was called
    final cancelCall = log.lastWhere((call) => call.method == 'resizeOverlay');
    expect(cancelCall.arguments['width'], equals(140));
    expect(cancelCall.arguments['height'], equals(140));

    // Verify "cancel" was sent across bridge
    final bridgeCall = log.lastWhere((call) => call.method == 'send');
    expect(bridgeCall.arguments, equals("cancel"));
  });
  ```

- [ ] **Step 3: Run test to verify it passes**
  Run: `rtk flutter test test/overlay_dismissal_test.dart`
  Expected: PASS

- [ ] **Step 4: Commit**
  Run: `git add lib/main.dart test/overlay_dismissal_test.dart && git commit -m "feat: watchdog timeout extension and cancel spinner UI"`

---

### Task 2: cancellation handling in main isolate

**Files:**
- Modify: `lib/main.dart:63-165`

- [ ] **Step 1: Implement cancelRequested check points and message listener branch**
  Define `bool _cancelRequested = false;` in the main isolate scope, update the message listener to set `_cancelRequested = true` on receiving `"cancel"`, and inject check points inside `_runTranslationFlowAndSendToOverlay()`.
  ```dart
  bool _isTranslationInProgress = false;
  bool _cancelRequested = false;

  Future<void> _runTranslationFlowAndSendToOverlay() async {
    if (!_modelStatusNotifier.value.ready) {
      await OverlayBridge.send({
        "status": "error",
        "message": "Gemma model not ready. Please open the main app dashboard.",
      });
      return;
    }

    if (_isTranslationInProgress) {
      debugPrint("[Main] Translation already in progress. Ignoring request.");
      return;
    }
    _isTranslationInProgress = true;
    _cancelRequested = false;
    debugPrint("[Main] Capture request received. Starting translation flow.");

    try {
      if (_cancelRequested) return;
      final captureData = await _captureService.captureScreen();
      if (_cancelRequested) return;
      await OverlayBridge.send({"status": "capturing_done"});
      if (_cancelRequested) return;

      if (captureData == null) {
        debugPrint("[Main] captureScreen() returned null.");
        await OverlayBridge.send({"status": "no_text"});
        return;
      }

      final path = captureData['path'] as String;
      final imageWidth = (captureData['width'] as num).toDouble();
      final imageHeight = (captureData['height'] as num).toDouble();
      final cropY = (captureData['cropY'] as num?)?.toDouble() ?? 0.0;
      debugPrint("[Main] Screen captured: $path ($imageWidth x $imageHeight) cropY=$cropY");

      final ocrBlocks = await _ocrService.extractText(path);
      if (_cancelRequested) return;
      debugPrint("[Main] OCR found ${ocrBlocks.length} blocks.");
      if (ocrBlocks.isEmpty) {
        await OverlayBridge.send({"status": "no_text"});
        return;
      }

      final blockRecords = ocrBlocks.map((b) => (
        text: b.text,
        x: b.boundingBox.left.toInt(),
        y: b.boundingBox.top.toInt(),
      )).toList();
      
      final translatedTexts = await _translationService.translateBatch(
        blockRecords,
        isCancelled: () => _cancelRequested,
      );
      if (_cancelRequested) return;
      debugPrint("[Main] Translated ${translatedTexts.length} blocks.");

      final List<Map<String, dynamic>> list = [];
      for (int i = 0; i < ocrBlocks.length; i++) {
        final block = ocrBlocks[i];
        final rect = block.boundingBox;
        final text = (i < translatedTexts.length && translatedTexts[i].isNotEmpty)
            ? translatedTexts[i]
            : block.text;
        list.add({
          'text': text,
          'rect': [rect.left, rect.top, rect.right, rect.bottom],
        });
      }

      await OverlayBridge.send({
        "status": "success",
        "translations": list,
        "imageWidth": imageWidth,
        "imageHeight": imageHeight,
        "cropY": cropY,
      });
    } catch (e) {
      if (_cancelRequested) {
        debugPrint("[Main] Translation flow clean abort due to cancellation.");
        return;
      }
      debugPrint("[Main] Translation flow error: $e");
      await OverlayBridge.send({
        "status": "error",
        "message": "Capture failed: ${e.toString()}",
      });
    } finally {
      _isTranslationInProgress = false;
    }
  }
  ```

  And update overlay listener:
  ```dart
  OverlayBridge.messages.listen(
    (data) async {
      debugPrint("[Main] OverlayBridge received: $data (type: ${data.runtimeType})");
      if (data == "capture") {
        await _runTranslationFlowAndSendToOverlay();
      } else if (data == "cancel") {
        _cancelRequested = true;
      } else if (data == "open_app") {
        // ...
  ```

- [ ] **Step 2: Update `translateBatch` signature to accept optional cancellation callback**
  Update `lib/translation_service.dart` to accept cancellation logic:
  ```dart
  Future<List<String>> translateBatch(
    List<({String text, int x, int y})> blocks, {
    bool Function()? isCancelled,
  }) async {
    if (blocks.isEmpty) return [];
    if (isCancelled != null && isCancelled()) return [];
    if (!_isInitialized || _model == null) {
      throw StateError("TranslationService is not initialized. Call init() first.");
    }
    // ...
  ```
  Pass `isCancelled` down to fallback logic as well:
  ```dart
  Future<List<String>> _fallbackToSequential(
    List<({String text, int x, int y})> blocks, {
    bool Function()? isCancelled,
  }) async {
    final List<String> results = [];
    for (final block in blocks) {
      if (isCancelled != null && isCancelled()) break;
      try {
        results.add(await translate(block.text));
      } catch (e) {
        results.add(block.text);
      }
    }
    return results;
  }
  ```

- [ ] **Step 3: Run test to verify it compiles and passes**
  Run: `rtk flutter test`
  Expected: PASS

- [ ] **Step 4: Commit**
  Run: `git add lib/main.dart lib/translation_service.dart && git commit -m "feat: cancel translation requests handler on main isolate"`

---

### Task 3: GPU acceleration fallback

**Files:**
- Modify: `lib/translation_service.dart:40-52`

- [ ] **Step 1: Update PreferredBackend to GPU with fallback to CPU**
  Update `TranslationService.init()` to initialize with `PreferredBackend.gpu`. If initialization fails, fallback to `PreferredBackend.cpu`.
  ```dart
    debugPrint('[TranslationService] Step 3: getActiveModel(maxTokens=256)...');
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 256,
        preferredBackend: PreferredBackend.gpu,
      );
      debugPrint('[TranslationService] GPU model initialized successfully.');
    } catch (e) {
      debugPrint('[TranslationService] GPU initialization failed: $e. Falling back to CPU.');
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 256,
        preferredBackend: PreferredBackend.cpu,
      );
    }
    debugPrint('[TranslationService] Step 3: done. model=$_model');
  ```

- [ ] **Step 2: Run test to verify it compiles and passes**
  Run: `rtk flutter test`
  Expected: PASS

- [ ] **Step 3: Commit**
  Run: `git add lib/translation_service.dart && git commit -m "feat: enable PreferredBackend.gpu with automatic CPU fallback"`

---

### Task 4: prompt compression

**Files:**
- Modify: `lib/translation_service.dart:210-228`
- Modify: `lib/translation_service.dart:128-132`

- [ ] **Step 1: Compress structured XML prompt instructions**
  Shorten the prompt boilerplate inside `buildStructuredPrompt` to optimize prefill latency:
  ```dart
  static String buildStructuredPrompt(List<({String text, int x, int y})> blocks) {
    final buffer = StringBuffer();
    buffer.writeln('Translate Japanese UI text blocks to English. Use (x,y) for layout context.');
    buffer.writeln('Format: <t id="N">translation</t>');
    buffer.writeln('Output only XML tags. No notes.');
    buffer.writeln('');
    buffer.writeln('Input:');
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final safeText = _chunkText(block.text.replaceAll('\n', ' ')).first;
      buffer.writeln('<t id="${i + 1}" x="${block.x}" y="${block.y}">$safeText</t>');
    }
    return buffer.toString();
  }
  ```

- [ ] **Step 2: Compress single chunk prompt instructions**
  Modify single chunk translation prompt in `_translateChunk`:
  ```dart
  final prompt =
      'Translate Japanese text to English. Output only English translation, no notes.\n'
      'Japanese: $chunk\nEnglish:';
  ```

- [ ] **Step 3: Run test to verify it compiles and passes**
  Run: `rtk flutter test`
  Expected: PASS

- [ ] **Step 4: Commit**
  Run: `git add lib/translation_service.dart && git commit -m "perf: compress translation prompt boilerplate to reduce prefill latency"`
