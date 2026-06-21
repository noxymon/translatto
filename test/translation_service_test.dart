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
    service.model = mockModel;
    
    final result = await service.translate('こんにちは');
    
    expect(result, equals('Hello'));
    expect(mockSession.queries, hasLength(1));
    expect(mockSession.queries.first.text, contains('こんにちは'));
    expect(mockSession.queries.first.text, contains('natural, fluent English'));
    expect(mockSession.queries.first.isUser, isTrue);
    expect(mockSession.isClosed, isTrue);
  });

  test('TranslationService translateBatch falls back to sequential or processes single block', () async {
    final mockSession = MockInferenceModelSession('Hello');
    final mockModel = MockInferenceModel(mockSession);
    
    final service = TranslationService();
    service.model = mockModel;
    
    final result = await service.translateBatch([(text: 'こんにちは', x: 10, y: 20)]);
    
    expect(result, equals(['Hello']));
    expect(mockSession.queries, hasLength(1));
    expect(mockSession.queries.first.text, contains('こんにちは'));
    expect(mockSession.isClosed, isTrue);
  });

  test('TranslationService translateBatch structured XML translation', () async {
    final mockSession = MockInferenceModelSession('<t id="1">Hello</t><t id="2">World</t>');
    final mockModel = MockInferenceModel(mockSession);
    
    final service = TranslationService();
    service.model = mockModel;
    
    final result = await service.translateBatch([
      (text: 'こんにちは', x: 10, y: 20),
      (text: '世界', x: 10, y: 80),
    ]);
    
    expect(result, equals(['Hello', 'World']));
    expect(mockSession.queries, hasLength(1));
    expect(mockSession.queries.first.text, contains('<t id="1" x="10" y="20">こんにちは</t>'));
    expect(mockSession.queries.first.text, contains('<t id="2" x="10" y="80">世界</t>'));
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
}

