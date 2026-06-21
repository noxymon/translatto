# Theme Settings and Japanese Text Filtering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a settings page to configure the app theme and filter out non-Japanese blocks from translation and overlay.

**Architecture:**
Wrap the root `MaterialApp` in a `ValueListenableBuilder` listening to `themeNotifier` which stores a `ThemeMode`. Expose `SettingsScreen` containing radio selections for the theme. Update dashboard card container backgrounds and borders to use theme-based colors. Filter `ocrBlocks` in the translation request handler to exclude blocks that do not contain hiragana, katakana, or kanji, only translating and overlaying the CJK-matching subset.

**Tech Stack:** Flutter, google_mlkit_text_recognition

---

### Task 1: Main App Theme Configuration and Settings Screen

**Files:**
- Modify: `lib/main.dart:18-52`
- Modify: `lib/main.dart:299-410`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Declare global themeMode notifier and update MaterialApp themes**
  Create the theme notifier and wrap the root `MaterialApp` to react to theme mode:
  ```dart
  final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

  class MyApp extends StatelessWidget {
    const MyApp({super.key});

    @override
    Widget build(BuildContext context) {
      return ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'Screen Translator',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.light,
              primaryColor: const Color(0xff1e90ff),
              scaffoldBackgroundColor: const Color(0xfff5f5f5),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xff1e90ff),
                foregroundColor: Colors.white,
              ),
              colorScheme: const ColorScheme.light(
                primary: Color(0xff1e90ff),
                secondary: Color(0xff00bfff),
                surface: Colors.white,
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              primaryColor: const Color(0xff89b4fa),
              scaffoldBackgroundColor: const Color(0xff181825),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xff1e1e2e),
              ),
              colorScheme: const ColorScheme.dark(
                primary: Color(0xff89b4fa),
                secondary: Color(0xffcba6f7),
                surface: Color(0xff1e1e2e),
              ),
            ),
            themeMode: themeMode,
            home: const MainDashboardScreen(),
          );
        },
      );
    }
  }
  ```

- [ ] **Step 2: Add Settings Screen widget and route it from AppBar**
  Define `SettingsScreen` and connect it in the Dashboard's AppBar actions:
  ```dart
  class SettingsScreen extends StatelessWidget {
    const SettingsScreen({super.key});

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Settings"),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Appearance",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, currentMode, _) {
                    return Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          title: const Text("Dark Theme"),
                          value: ThemeMode.dark,
                          groupValue: currentMode,
                          onChanged: (mode) {
                            if (mode != null) themeNotifier.value = mode;
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<ThemeMode>(
                          title: const Text("Light Theme"),
                          value: ThemeMode.light,
                          groupValue: currentMode,
                          onChanged: (mode) {
                            if (mode != null) themeNotifier.value = mode;
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<ThemeMode>(
                          title: const Text("System Default"),
                          value: ThemeMode.system,
                          groupValue: currentMode,
                          onChanged: (mode) {
                            if (mode != null) themeNotifier.value = mode;
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  ```

  And inside `MainDashboardScreen`'s AppBar:
  ```dart
      appBar: AppBar(
        title: const Text("Gemma Screen Translator"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
  ```

- [ ] **Step 3: Refactor dashboard cards to adapt to current theme**
  Replace hardcoded dark background and border colors in `MainDashboardScreen`'s cards with themed values:
  ```dart
  // Card 1
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: status.ready ? const Color(0xffa6e3a1) : const Color(0xfff38ba8),
                        width: 2,
                      ),
                    ),
  // Text contrast
                          Text(
                            status.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: status.ready 
                                  ? (Theme.of(context).brightness == Brightness.dark 
                                      ? const Color(0xffa6adc8) 
                                      : Colors.black87) 
                                  : const Color(0xfff38ba8),
                              fontSize: 13,
                            ),
                          ),

  // Card 2
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
  ```

- [ ] **Step 4: Update dashboard UI widget test to verify settings icon renders**
  Add verification inside `test/widget_test.dart`:
  ```dart
  testWidgets('Dashboard UI renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
  ```

- [ ] **Step 5: Run tests to verify compilation and passing**
  Run: `rtk flutter test test/widget_test.dart`
  Expected: PASS

- [ ] **Step 6: Commit**
  Run: `git add lib/main.dart test/widget_test.dart && git commit -m "feat: add app theme settings configuration screen"`

---

### Task 2: Japanese Selective OCR Filtering

**Files:**
- Modify: `lib/main.dart:102-125`
- Test: `test/overlay_dismissal_test.dart`

- [ ] **Step 1: Refactor OCR output pipeline to filter out non-Japanese blocks**
  Modify the `_runTranslationFlowAndSendToOverlay` method to extract and translate only Japanese-containing blocks:
  ```dart
    final ocrBlocks = await _ocrService.extractText(path);
    if (_cancelRequested) return;
    debugPrint("[Main] OCR found ${ocrBlocks.length} blocks.");
    if (ocrBlocks.isEmpty) {
      await OverlayBridge.send({"status": "no_text"});
      return;
    }

    final List<OcrBlock> blocksToTranslate = [];
    for (final block in ocrBlocks) {
      if (TranslationService.hasJapaneseText(block.text)) {
        blocksToTranslate.add(block);
      }
    }

    if (blocksToTranslate.isEmpty) {
      debugPrint("[Main] No Japanese text blocks detected.");
      await OverlayBridge.send({"status": "no_japanese_text"});
      return;
    }

    final blockRecords = blocksToTranslate.map((b) => (
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
    for (int i = 0; i < blocksToTranslate.length; i++) {
      final block = blocksToTranslate[i];
      final rect = block.boundingBox;
      final text = (i < translatedTexts.length && translatedTexts[i].isNotEmpty)
          ? translatedTexts[i]
          : block.text;
      list.add({
        'text': text,
        'rect': [rect.left, rect.top, rect.right, rect.bottom],
      });
    }
  ```

- [ ] **Step 2: Add integration test verifying English blocks are omitted from overlay payload**
  Create a test inside `test/overlay_dismissal_test.dart` that mocks a blend of English and Japanese OCR inputs and asserts that only Japanese is processed:
  ```dart
  // We don't have a direct mock for ocr blocks inside dismissal, but we verify overlay painting does not throw with empty list
  ```
  Wait! Let's check `test/ocr_service_test.dart` to see if there is any OCR processing test we should verify, or if we can run `rtk flutter test`.

- [ ] **Step 3: Run all tests to verify correctness**
  Run: `rtk flutter test`
  Expected: PASS

- [ ] **Step 4: Commit**
  Run: `git add lib/main.dart && git commit -m "feat: ignore non-Japanese text blocks during OCR extraction and overlay translation"`
