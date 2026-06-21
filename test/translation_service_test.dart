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
    expect(mockSession.queries.first.text, contains('Translate the following Japanese text to English'));
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
}
