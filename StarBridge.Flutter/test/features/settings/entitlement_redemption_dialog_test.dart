import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/settings/entitlement_redemption_dialog.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: Scaffold(body: child),
  );
  testWidgets('SCM unsupported never exposes submission', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        EntitlementRedemptionDialog(
          supported: false,
          redeem: (_) async {
            calls++;
            return 'redeemed';
          },
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(calls, 0);
  });
  testWidgets('single submit disables duplicates and clears successful code', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<String>();
    await tester.pumpWidget(
      app(
        EntitlementRedemptionDialog(
          supported: true,
          redeem: (_) {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test-code');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    expect(calls, 1);
    pending.complete('redeemed');
    await tester.pumpAndSettle();
    expect(find.text('Redeemed. Entitlements updated.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
  testWidgets('uncertainty does not replay and disables repeat', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        EntitlementRedemptionDialog(
          supported: true,
          redeem: (_) async {
            calls++;
            throw Exception('synthetic');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test-code');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
