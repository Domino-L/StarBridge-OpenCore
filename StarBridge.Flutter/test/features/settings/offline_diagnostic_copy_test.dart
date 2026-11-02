import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/application_support_copy.dart';

void main() {
  final copies = <Locale, String>{
    const Locale('zh', 'CN'): '联网检查已暂停，本地检查结果仍然有效。',
    const Locale('zh', 'TW'): '連線檢查已暫停，本機檢查結果仍然有效。',
    const Locale('en', 'US'):
        'Online checks are paused. Local results remain valid.',
  };
  for (final entry in copies.entries) {
    testWidgets('paused probe is not a server failure: ${entry.key}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.key,
          supportedLocales: copies.keys.toList(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Text(
              applicationSupportCopy(context, 'detail.connectionPaused'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('detail.connectionPaused'), findsNothing);
      expect(tester.takeException(), null);
    });
  }
}
