import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:screen_translate/translation_service.dart';

class MockInferenceModel implements InferenceModel {
  final MockInferenceModelSession mockSession;
  
  MockInferenceModel(this.mockSession);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createSession) {
      return Future.value(mockSession);
    }
    return super.noSuchMethod(invocation);
  }
}

class MockInferenceModelSession implements InferenceModelSession {
  final String responseText;
  final List<Message> queries = [];
  bool isClosed = false;

  MockInferenceModelSession(this.responseText);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #addQueryChunk) {
      queries.add(invocation.positionalArguments.first as Message);
      return Future.value();
    }
    if (invocation.memberName == #getResponse) {
      return Future.value(responseText);
    }
    if (invocation.memberName == #close) {
      isClosed = true;
      return Future.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  test('TranslationService translates Japanese text and verifies prompt submission', () async {
    final mockSession = MockInferenceModelSession('Hello');
    final mockModel = MockInferenceModel(mockSession);
    
    final service = TranslationService();
    TranslationService.clearCache();
    service.model = mockModel;
    
    final result = await service.translate('こんにちは');
    
    expect(result, equals('Hello'));
    expect(mockSession.queries, hasLength(1));
    expect(mockSession.queries.first.text, contains('こんにちは'));
    expect(mockSession.queries.first.text, contains('to English'));
    expect(mockSession.queries.first.isUser, isTrue);
    expect(mockSession.isClosed, isTrue);
  });

  test('TranslationService translateBatch falls back to sequential or processes single block', () async {
    final mockSession = MockInferenceModelSession('Hello');
    final mockModel = MockInferenceModel(mockSession);
    
    final service = TranslationService();
    TranslationService.clearCache();
    service.model = mockModel;
    
    final result = await service.translateBatch([(text: 'こんにちは', x: 10, y: 20, sourceLanguage: 'ja')]);
    
    expect(result, equals(['Hello']));
    expect(mockSession.queries, hasLength(1));
    expect(mockSession.queries.first.text, contains('こんにちは'));
    expect(mockSession.isClosed, isTrue);
  });

  test('TranslationService translateBatch structured XML translation', () async {
    final mockSession = MockInferenceModelSession('<t id="1">Hello</t><t id="2">World</t>');
    final mockModel = MockInferenceModel(mockSession);
    
    final service = TranslationService();
    TranslationService.clearCache();
    service.model = mockModel;
    
    final result = await service.translateBatch([
      (text: 'こんにちは', x: 10, y: 20, sourceLanguage: 'ja'),
      (text: '世界', x: 10, y: 80, sourceLanguage: 'ja'),
    ]);
    
    expect(result, equals(['Hello', 'World']));
    expect(mockSession.queries, hasLength(1));
    expect(mockSession.queries.first.text, contains('<t id="1">こんにちは</t>'));
    expect(mockSession.queries.first.text, contains('<t id="2">世界</t>'));
    expect(mockSession.isClosed, isTrue);
  });

  test('TranslationService splits into paragraphs and preserves newlines/list markers', () async {
    final mockSession = MockInferenceModelSession('Translated line');
    final mockModel = MockInferenceModel(mockSession);
    
    final service = TranslationService();
    service.model = mockModel;
    
    // Split test: 3 distinct paragraphs/bullets should translate sequentially and join with \n
    final input = '※ 期間が7日と14日の通常定期預金は最低預入単位\nが10万円以上、1円単位になります。\n※ 金利は税引前の年利です。';
    final result = await service.translate(input);
    
    // We expect 2 translated paragraphs joined by \n (since line 2 is merged into paragraph 1)
    expect(result, equals('Translated line\nTranslated line'));
    expect(mockSession.queries, hasLength(2));
    
    // Verify first query was the merged paragraph 1
    expect(mockSession.queries[0].text, contains('※ 期間が7日と14日の通常定期預金は最低預入単位が10万円以上、1円単位になります。'));
    // Verify second query was paragraph 2
    expect(mockSession.queries[1].text, contains('※ 金利は税引前の年利です。'));
  });

  test('TranslationService removes newlines when original Japanese had no newlines', () async {
    final mockSession = MockInferenceModelSession('Line 1\nLine 2');
    final mockModel = MockInferenceModel(mockSession);
    
    final service = TranslationService();
    service.model = mockModel;
    
    final result = await service.translate('改行なし原文');
    expect(result, equals('Line 1 Line 2')); // \n replaced with space
  });

  test('TranslationService.hasJapaneseText detects Hiragana, Katakana, and Kanji', () {
    expect(TranslationService.hasJapaneseText('こんにちは'), isTrue); // Hiragana
    expect(TranslationService.hasJapaneseText('テスト'), isTrue); // Katakana
    expect(TranslationService.hasJapaneseText('日本語'), isTrue); // Kanji
    expect(TranslationService.hasJapaneseText('Hello World'), isFalse); // English only
    expect(TranslationService.hasJapaneseText('12345!@#'), isFalse); // Symbols and digits
  });

  test('TranslationService handles language-specific caching correctly', () async {
    final service = TranslationService();
    TranslationService.clearCache();

    // First translation to English
    final mockSessionEn = MockInferenceModelSession('Hello');
    service.model = MockInferenceModel(mockSessionEn);
    final resultEn = await service.translate('こんにちは', targetLanguage: 'English');
    expect(resultEn, equals('Hello'));
    expect(mockSessionEn.queries.first.text, contains('to English'));

    // Second translation of SAME text to Indonesian
    final mockSessionId = MockInferenceModelSession('Halo');
    service.model = MockInferenceModel(mockSessionId);
    final resultId = await service.translate('こんにちは', targetLanguage: 'Indonesian');
    expect(resultId, equals('Halo')); // Should NOT hit cache for English
    expect(mockSessionId.queries.first.text, contains('to Indonesian'));
  });

  test('TranslationService sentence-boundary chunking groups short sentences', () {
    // English/Indonesian non-CJK text should support up to 400 chars, grouping multiple sentences
    final input = "First sentence. Second sentence. Third sentence. " * 3;
    final chunks = TranslationService.chunkTextForTesting(input);
    expect(chunks.length, equals(1)); // All should group in 1 chunk (< 400 chars)
    expect(chunks.first, contains("Third sentence."));
  });

  test('TranslationService sentence-boundary chunking splits oversized text adaptively', () {
    final input = "This is a very long sentence that will exceed the maximum character limit of four hundred characters for non CJK languages. " * 4;
    final chunks = TranslationService.chunkTextForTesting(input);
    expect(chunks.length, greaterThan(1));
  });
}

