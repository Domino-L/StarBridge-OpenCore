import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/window_presentation.dart';

void main() {
  test('detached windows retain every supported client locale', () {
    for (final tag in ['zh-CN', 'zh-TW', 'en-US']) {
      final locale = WindowPresentation.decode({'locale': tag}).locale;
      expect(locale.toLanguageTag(), tag);
    }
    expect(WindowPresentation.decode({'locale': 'invalid'}).locale, const Locale('zh', 'CN'));
  });
}
