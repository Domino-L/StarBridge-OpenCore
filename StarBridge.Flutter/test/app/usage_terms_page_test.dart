import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/app/runtime/test_build_notice_flow.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';

import '../features/settings/local_privacy_page_test.dart' show app, viewport;
import 'test_build_notice_flow_test.dart' show readTermsAndCheck;

Future<ClientLicenseDocument> _license() async => const ClientLicenseDocument(
  ClientLicenseState.ready,
  'Synthetic complete license for bounded tests.',
);

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final width in [400.0, 800.0]) {
      testWidgets('terms fixed controls fit $locale width=$width large text', (
        tester,
      ) async {
        viewport(tester, Size(width, 600));
        await tester.pumpWidget(
          app(
            TestBuildNoticeDialog(
              acknowledge: () async => false,
              readLicense: _license,
            ),
            locale: locale,
            textScale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byKey(const Key('test-build-exit'))).bottom,
          lessThanOrEqualTo(600),
        );
        expect(
          tester.getRect(find.byKey(const Key('test-build-accept'))).bottom,
          lessThanOrEqualTo(600),
        );
        await readTermsAndCheck(tester);
        expect(
          tester
              .widget<StarBridgeCheckboxTile>(
                find.byKey(const Key('usage-terms-consent')),
              )
              .value,
          true,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('locale change retires reading position and explicit choice', (
    tester,
  ) async {
    viewport(tester, const Size(800, 600));
    var writes = 0;
    Widget page(Locale locale) => app(
      TestBuildNoticeDialog(
        acknowledge: () async {
          writes++;
          return false;
        },
        readLicense: _license,
      ),
      locale: locale,
    );
    await tester.pumpWidget(page(const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    await readTermsAndCheck(tester);
    await tester.pumpWidget(page(const Locale('en', 'US')));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<StarBridgeCheckboxTile>(
      find.byKey(const Key('usage-terms-consent')),
    );
    expect(checkbox.value, false);
    expect(checkbox.onChanged, isNull);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'decline never waits for a stalled document and disposal cancels timer',
    (tester) async {
      viewport(tester, const Size(800, 600));
      final pending = Completer<ClientLicenseDocument>();
      var exits = 0, writes = 0;
      await tester.pumpWidget(
        app(
          TestBuildNoticeDialog(
            acknowledge: () async {
              writes++;
              return true;
            },
            readLicense: () => pending.future,
            exitApplication: () async {
              exits++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-build-exit')));
      await tester.pumpAndSettle();
      expect(exits, 1);
      expect(writes, 0);
      expect(find.byKey(const Key('test-build-notice')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      pending.complete(await _license());
      await tester.pump();
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
