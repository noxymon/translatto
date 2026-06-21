import 'package:flutter_test/flutter_test.dart';
import 'package:screen_translate/translation_service.dart';

void main() {
  test('buildStructuredPrompt constructs correct XML input', () {
    final blocks = [
      (text: 'こんにちは', x: 10, y: 20),
      (text: 'お元気ですか？', x: 10, y: 80),
    ];

    final prompt = TranslationService.buildStructuredPrompt(blocks);
    expect(prompt, contains('<t id="1" x="10" y="20">こんにちは</t>'));
    expect(prompt, contains('<t id="2" x="10" y="80">お元気ですか？</t>'));
    expect(prompt, contains('Output ONLY the translated blocks wrapped in matching XML tags'));
  });

  test('parseStructuredResponse parses valid XML successfully', () {
    const response = '''
    <t id="1">Hello</t>
    <t id="2">How are you?</t>
    ''';
    final parsed = TranslationService.parseStructuredResponse(response, 2);
    expect(parsed, isNotNull);
    expect(parsed, equals(['Hello', 'How are you?']));
  });

  test('parseStructuredResponse returns null on count mismatch', () {
    const response = '<t id="1">Hello</t>';
    final parsed = TranslationService.parseStructuredResponse(response, 2);
    expect(parsed, isNull);
  });

  test('parseStructuredResponse returns null on invalid XML tags', () {
    const response = 'Hello how are you';
    final parsed = TranslationService.parseStructuredResponse(response, 1);
    expect(parsed, isNull);
  });

  test('parseStructuredResponse handles duplicate tags gracefully', () {
    const response = '''
    <t id="1">Hello</t>
    <t id="1">Duplicated</t>
    <t id="2">How are you?</t>
    ''';
    // First match should be kept; duplicates ignored.
    final parsed = TranslationService.parseStructuredResponse(response, 2);
    expect(parsed, equals(['Hello', 'How are you?']));
  });

  test('parseStructuredResponse tolerates spaces around id attribute', () {
    const response = '<t id = "1">Hello</t><t id = "2">World</t>';
    final parsed = TranslationService.parseStructuredResponse(response, 2);
    expect(parsed, isNotNull);
    expect(parsed, equals(['Hello', 'World']));
  });
}
