import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:screen_translate/translation_service.dart';

void main() {
  late TranslationService service;

  setUp(() {
    service = TranslationService();
  });

  test('buildStructuredPrompt constructs correct XML input', () {
    final blocks = [
      TextBlock(
        text: 'こんにちは',
        lines: [],
        boundingBox: const Rect.fromLTWH(10, 20, 100, 50),
        recognizedLanguages: [],
        cornerPoints: [],
      ),
      TextBlock(
        text: 'お元気ですか？',
        lines: [],
        boundingBox: const Rect.fromLTWH(10, 80, 120, 50),
        recognizedLanguages: [],
        cornerPoints: [],
      ),
    ];

    final prompt = service.buildStructuredPrompt(blocks);
    expect(prompt, contains('<t id="1" x="10" y="20">こんにちは</t>'));
    expect(prompt, contains('<t id="2" x="10" y="80">お元気ですか？</t>'));
    expect(prompt, contains('Output ONLY the translated blocks wrapped in matching XML tags'));
  });

  test('parseStructuredResponse parses valid XML successfully', () {
    const response = '''
    <t id="1">Hello</t>
    <t id="2">How are you?</t>
    ''';
    final parsed = service.parseStructuredResponse(response, 2);
    expect(parsed, isNotNull);
    expect(parsed, equals(['Hello', 'How are you?']));
  });

  test('parseStructuredResponse returns null on count mismatch', () {
    const response = '<t id="1">Hello</t>';
    final parsed = service.parseStructuredResponse(response, 2);
    expect(parsed, isNull);
  });

  test('parseStructuredResponse returns null on invalid XML tags', () {
    const response = 'Hello how are you';
    final parsed = service.parseStructuredResponse(response, 1);
    expect(parsed, isNull);
  });

  test('parseStructuredResponse handles duplicate tags gracefully', () {
    const response = '''
    <t id="1">Hello</t>
    <t id="1">Duplicated</t>
    <t id="2">How are you?</t>
    ''';
    // First match should be kept or handled, if overall count of unique IDs matches
    final parsed = service.parseStructuredResponse(response, 2);
    expect(parsed, equals(['Hello', 'How are you?']));
  });
}
