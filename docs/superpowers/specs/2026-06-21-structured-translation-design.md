# Design Spec: Structured Bulk Translation with Pixel Coordinates

*   **Date:** 2026-06-21
*   **Scope:** Optimize local Gemma translation speed and accuracy using structured prompting.

---

## 1. Goal & Objectives
*   **Performance:** Reduce translation latency by executing a single batched inference call instead of $N$ sequential calls.
*   **Context Preservation:** Inject layout pixel coordinates into the XML prompt tags to supply spatial context to the model (e.g., text block hierarchy).
*   **Safety:** Maintain strict mapping between original text bounding boxes and their translations, using RegExp parsing with robust sequential fallback.

---

## 2. Structured Prompt Schema

We wrap each text block in a `<t>` tag containing the unique block ID and its top-left coordinates `x` and `y`.

### Prompt Template
```text
Translate the following Japanese text blocks captured from an Android screen to English.
The coordinates (x, y) represent their top-left pixel locations on the screen.
Use these locations to understand the layout context (e.g., adjacent blocks, title vs. body).

Output ONLY the translated blocks wrapped in matching XML tags: <t id="..."><translation></t>.
Do not include coordinates in the output. Do not write any other explanations.

Input:
<t id="1" x="108" y="240">こんにちは</t>
<t id="2" x="108" y="292">お元気ですか？</t>
```

### Model Output Format
```xml
<t id="1">Hello</t>
<t id="2">How are you?</t>
```

---

## 3. Implementation Plan

### A. Translation Service Update (`lib/translation_service.dart`)
*   Refactor `translateBatch(List<TextBlock> blocks)` to build the XML prompt payload using `boundingBox.left` and `boundingBox.top`.
*   Initialize RegExp matching: `RegExp(r'<t id="(\d+)">\s*([\s\S]*?)\s*<\/t>')`.
*   Verify output tags count matches input. If mismatch or parsing fails, log and fallback to sequential block-by-block translation.

### B. Integration Update (`lib/main.dart`)
*   Pass the list of `TextBlock` objects from ML Kit OCR directly into `_translationService.translateBatch(...)` instead of extracting raw strings.

---

## 4. Test & Verification
*   **Mock Verification:** Write tests verifying XML generator formatting and RegExp parsing logic with typical inputs, corrupted structures, and missing tags.
