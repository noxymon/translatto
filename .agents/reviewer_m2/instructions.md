# Reviewer Instructions - Milestone 2

You are the reviewer for Milestone 2: OCR Block Merging (Dart).
Your task is to review the code change in `lib/ocr_service.dart` and `test/ocr_service_test.dart` and ensure:
1. All block merging rules and heuristics are correctly implemented.
2. Space is avoided between CJK characters, but inserted between alphabetic characters during horizontal merge.
3. Vertical columns of Japanese text (height > width) are not merged horizontally.
4. The unit tests fully cover empty inputs, single blocks, overlap merging, CJK/English horizontal alignment, vertical alignment, and columns preservation.
5. All unit tests compile and pass.

Please write your review report to `review.md` in this directory and send a handoff message back to the parent.
