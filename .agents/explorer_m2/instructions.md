# Explorer Instructions - Milestone 2

You are the explorer for Milestone 2: OCR Block Merging (Dart).
Your task is to analyze how `lib/ocr_service.dart` works, examine existing unit tests (e.g. `test/ocr_service_test.dart`), and outline how to implement the OCR bounding box merging heuristics in Dart.

## Merge Heuristics:
1. **Overlap Check**: Merge blocks if they geometrically overlap.
2. **Vertical Alignment (Paragraph Lines)**: Merge blocks that are stacked vertically if:
   - Their horizontal overlap is >= 30% of the narrower block's width.
   - The vertical gap between them is <= 1.5x the height of the shorter block.
3. **Horizontal Alignment (Adjacent Words)**: Merge blocks side-by-side if:
   - Their vertical overlap is >= 50% of the shorter block's height.
   - The horizontal gap between them is <= 2x the height of the shorter block.
4. **Merging Action**:
   - Bounding Box: Expand `rectA` to include `rectB`.
   - Text: Join texts with a space: `"${b1.text} ${b2.text}"`.

Please write your analysis to `analysis.md` in this directory and send a handoff message to the parent with the path.
