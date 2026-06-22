# Design Spec: README.md Redesign & Online Translation Roadmap

## Context & Goal
The project currently uses a pure offline translation model (Gemma 2B) through [TranslationService](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/translation_service.dart). Small offline models have low contextual awareness. This document details the spec for updating the project [README.md](file:///Users/haikalannisa/Documents/Code/screen-translate/README.md) to serve as a high-quality guide and define a roadmap/design for introducing high-quality online translation engines.

## README Structure Spec

1. **Title & Badges**
   * Translatto: Local & Hybrid Android Screen Translator.
2. **Current System Architecture**
   * Mermaid sequence diagram showing interaction:
     * Media projection image reader in [MediaProjectionService.kt](file:///Users/haikalannisa/Documents/Code/screen-translate/android/app/src/main/kotlin/id/web/noxymon/translatto/MediaProjectionService.kt)
     * Text Recognition in [OcrService](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/ocr_service.dart)
     * Model inference in [TranslationService](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/translation_service.dart)
     * Renders in [OverlayPainter](file:///Users/haikalannisa/Documents/Code/screen-translate/lib/overlay_painter.dart)
3. **Getting Started & Commands**
   * Pushing model file using `make push-model`.
   * Building APKs.
4. **Current Limits: Offline Translation Quality**
   * Highlight low contextual accuracy of local Gemma 2B.
   * Highlight KV cache size constraints.
5. **Roadmap: Online Hybrid Translation Architecture**
   * Design interface `TranslationEngine` to support multiple backends.
   * Propose Gemini API, OpenAI, or DeepL implementations for high context translation.

## Verification
* Ensure markdown links use correct absolute scheme (`file://`).
* Validate all code links point to actual files in repo.
