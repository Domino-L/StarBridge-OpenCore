import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/legal/starbridge_third_party_licenses.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';

void main() {
  testWidgets(
    'startup registers bundled notices; reopening does not duplicate',
    (tester) async {
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      StarBridgeThirdPartyLicenses.registerAtStartup();
      Future<void> verifyNotices() async {
        final entries = await LicenseRegistry.licenses.toList();
        expect(entries, hasLength(3));
        expect(entries.expand((entry) => entry.packages), [
          'Source Sans 3',
          'Source Han Sans CN',
          'Source Code Pro',
        ]);
        for (final entry in entries) {
          expect(entry.paragraphs.map((p) => p.text).join(), isNotEmpty);
        }
      }

      await tester.runAsync(verifyNotices);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => StarBridgeThirdPartyLicenses.show(context),
              child: const Text('Open licenses'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Open licenses'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(verifyNotices);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(LicensePage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.runAsync(verifyNotices);
    },
  );
}
