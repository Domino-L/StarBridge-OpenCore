import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_invite_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/communities/community_invite_copy.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_admission_test.dart' show AdmissionInvites, AdmissionPrivacy;
import '../friends/social_layout_test.dart' show loadFonts;

Widget app(Widget home, Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  home: home,
);

Future<AdmissionPrivacy> open(
  WidgetTester tester,
  AdmissionInvites invites, {
  Locale locale = const Locale('zh', 'CN'),
  double width = 1100,
  String? initialCode,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(invites.events.close);
  final privacy = AdmissionPrivacy(invites.calls);
  addTearDown(privacy.events.close);
  await tester.pumpWidget(
    app(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<CommunityInviteOutcome>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('invite-capture'),
                child: CommunityInviteDialog(
                  port: invites,
                  privacy: privacy,
                  initialCode: initialCode,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      locale,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return privacy;
}

String text(WidgetTester tester, String key) =>
    inviteText(tester.element(find.byType(CommunityInviteDialog)), key);

Future<void> verify(WidgetTester tester, {String code = 'code'}) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(CommunityInviteDialog),
      matching: find.byType(TextField),
    ),
    code,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> review(WidgetTester tester) async {
  await verify(tester);
  await tester.tap(find.widgetWithText(FilledButton, text(tester, 'review')));
  await tester.pumpAndSettle();
}

Future<void> acknowledge(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      'S2 conflicting membership preserves preview and disables admission $locale',
      (tester) async {
        final invites = AdmissionInvites()..conflict = true;
        await open(tester, invites, locale: locale, width: 620);
        await verify(tester);
        expect(find.text('组织 B / B'), findsOneWidget);
        expect(find.text(text(tester, 'membershipConflict')), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, text(tester, 'review')),
          findsNothing,
        );
        expect(
          find.widgetWithText(FilledButton, text(tester, 'join')),
          findsNothing,
        );
        expect(invites.calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.widgetWithText(TextButton, text(tester, 'cancel')),
        );
        await tester.pumpAndSettle();
      },
    );
  }
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [620.0, 1100.0]) {
      testWidgets(
        'invite review layout $locale / $width, explicit consent and cancel',
        (tester) async {
          final invites = AdmissionInvites();
          final privacy = await open(
            tester,
            invites,
            locale: locale,
            width: width,
          );
          await review(tester);
          final join = find.widgetWithText(FilledButton, text(tester, 'join'));
          expect(tester.widget<FilledButton>(join).onPressed, isNull);
          expect(find.text('组织 B / B'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('admission-field-32')),
            findsOneWidget,
          );
          await acknowledge(tester);
          expect(tester.widget<FilledButton>(join).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
          if (width == 1100 && locale.toString() == 'zh_CN') {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('invite-capture')),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('build/community-invite-review.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(
            find.widgetWithText(TextButton, text(tester, 'cancel')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CommunityInviteDialog), findsNothing);
          expect(invites.calls, ['read']);
          expect(privacy.closed, isTrue);
        },
      );
    }
  }
  testWidgets('accepted join closes only after saving choices', (tester) async {
    final invites = AdmissionInvites();
    await open(tester, invites);
    await review(tester);
    await acknowledge(tester);
    await tester.tap(find.widgetWithText(FilledButton, text(tester, 'join')));
    await tester.pumpAndSettle();
    expect(invites.calls, ['read', 'save', 'accept']);
    expect(find.byType(CommunityInviteDialog), findsNothing);
  });
  testWidgets('unknown outcome remains visible and cannot be retried', (
    tester,
  ) async {
    final invites = AdmissionInvites()
      ..result = const CommunityInviteOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    await open(tester, invites);
    await review(tester);
    await acknowledge(tester);
    await tester.tap(find.widgetWithText(FilledButton, text(tester, 'join')));
    await tester.pumpAndSettle();
    expect(find.text(text(tester, 'outcomeUnknown')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      find.widgetWithText(FilledButton, text(tester, 'join')),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(TextButton, text(tester, 'close')));
    await tester.pumpAndSettle();
    expect(invites.calls, ['read', 'save', 'accept']);
  });
  testWidgets('changing code clears old card before another verification', (
    tester,
  ) async {
    final invites = AdmissionInvites();
    await open(tester, invites);
    await verify(tester);
    expect(find.text('组织 B / B'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'different');
    await tester.pumpAndSettle();
    expect(find.text('组织 B / B'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    await tester.tap(find.byTooltip(text(tester, 'close')));
    await tester.pumpAndSettle();
  });
  testWidgets('account invalidation removes dialog and private draft', (
    tester,
  ) async {
    final invites = AdmissionInvites();
    final privacy = await open(tester, invites);
    await review(tester);
    invites.events.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityInviteDialog), findsNothing);
    expect(invites.calls, ['read']);
    expect(privacy.closed, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'example page join uses isolated privacy, preserves existing organizations',
    (tester) async {
      tester.view.physicalSize = const Size(850, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = ExampleCommunities();
      var productionPrivacyCalls = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: CommunitiesPage(
              createPort: () => port,
              createAdmissionPrivacy: () {
                productionPrivacyCalls++;
                throw StateError('Must not use real settings');
              },
            ),
          ),
          const Locale('zh', 'CN'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用邀请码加入组织'));
      await tester.pumpAndSettle();
      expect(find.textContaining('EXAMPLE-ORG'), findsOneWidget);
      await verify(tester, code: 'EXAMPLE-ORG');
      await tester.tap(
        find.widgetWithText(FilledButton, text(tester, 'review')),
      );
      await tester.pumpAndSettle();
      await acknowledge(tester);
      await tester.tap(find.widgetWithText(FilledButton, text(tester, 'join')));
      await tester.pumpAndSettle();
      expect(productionPrivacyCalls, 0);
      expect(find.byType(CommunityInviteDialog), findsNothing);
      final mine = await port.read(view: 'mine', query: '');
      expect(mine.items.map((row) => row.targetRef).toSet(), {
        '00000000000000000000000000000001',
        '00000000000000000000000000000002',
        '00000000000000000000000000000003',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
