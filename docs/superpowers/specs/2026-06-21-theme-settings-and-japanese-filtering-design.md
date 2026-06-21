# Design Spec: Theme Settings and Japanese Text Filtering

This spec outlines the design to add a theme mode configuration screen (supporting system, dark, and light themes) and filter out non-Japanese text blocks so they are not sent to the LLM or overlaid on the screen.

## 1. Goal
1. Allow users to configure theme preference (Dark, Light, or System) in a new Settings screen in the main app.
2. Filter OCR text blocks dynamically so only blocks containing Japanese characters (Kanji, Hiragana, or Katakana) are translated and overlaid.

## 2. Technical Details

### A. Theme Mode Settings
- **State Management**:
  - Global `ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);`.
- **MaterialApp Customization**:
  - Define `theme` (light theme definitions) and `darkTheme` (dark theme definitions).
  - Set `themeMode` to listen to `themeNotifier` changes.
- **Settings Screen**:
  - Access settings page via `Navigator.push` from AppBar actions in `MainDashboardScreen`.
  - Radio options in a card for selecting theme mode: System Default, Light Theme, Dark Theme.
- **Dashboard Styles Refactoring**:
  - Remove hardcoded color tokens from card boxes (use `Theme.of(context).colorScheme.surface` and `Theme.of(context).dividerColor` instead).

### B. Japanese Only Text Filtering
- **OCR Block Filtering**:
  - In `_runTranslationFlowAndSendToOverlay()`, check each block returned by `_ocrService.extractText()`.
  - If a block does not satisfy `TranslationService.hasJapaneseText(block.text)`, it is removed from the list of blocks to translate.
  - If the list of Japanese blocks is empty, aborts early and returns `"no_japanese_text"`.
- **Overlay Rendering Bounds**:
  - The final translated `list` sent via `OverlayBridge.send()` contains only CJK-verified blocks, leaving English/digits/symbols intact on the display.

## 3. Review Checklist
- [x] Compilation checks and theme settings persistency fallback.
- [x] Zero placeholders.
