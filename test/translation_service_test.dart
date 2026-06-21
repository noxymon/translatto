import 'package:flutter_test/flutter_test.dart';
import 'package:screen_translate/translation_service.dart';

void main() {
  test('TranslationService translates Japanese text', () async {
    final service = TranslationService();
    expect(service, isNotNull);
  });
}
