import 'dart:async';
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
import 'package:starbridge_flutter/features/communities/community_disband_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_disband_port.dart';
import 'package:starbridge_flutter/features/communities/community_disband_copy.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_disband_test.dart';
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> openDisband(
  WidgetTester tester,
  CommunityDisbandPort port, {
  Locale locale = const Locale('zh', 'CN'),
  double width = 1000,
  String target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
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
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('disband-capture'),
                child: CommunityDisbandDialog(port: port, targetRef: target),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  for (final (locale, width, index) in [
    (const Locale('zh', 'CN'), 420.0, 0),
    (const Locale('zh', 'TW'), 800.0, 1),
    (const Locale('en'), 1000.0, 2),
  ]) {
    testWidgets('localized password confirmation fits $locale $width', (
      tester,
    ) async {
      final port = DisbandFake();
      addTearDown(port.changes.close);
      await openDisband(tester, port, locale: locale, width: width);
      final name = tester.widget<Text>(find.text(port.preview.name));
      if (locale.countryCode == 'CN') {
        expect(name.style?.fontFamilyFallback, contains('Source Han Sans CN'));
      } else {
        expect(name.style?.fontFamilyFallback, isNotEmpty);
      }
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.text(
          [
            communityDisbandCopy['credential']!.$1,
            communityDisbandCopy['credential']!.$2,
            communityDisbandCopy['credential']!.$3,
          ][index],
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (index == 0) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('disband-capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/community-disband.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  testWidgets('password clears before send; unknown stays open without retry', (
    tester,
  ) async {
    final port = DisbandFake()..writing = Completer<CommunityDisbandOutcome>();
    addTearDown(port.changes.close);
    await openDisband(tester, port);
    final field = tester.widget<TextField>(find.byType(TextField));
    await tester.enterText(find.byType(TextField), ' fixture ');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(field.controller!.text, isEmpty);
    expect(port.sentPassword, ' fixture ');
    port.writing!.complete(
      const CommunityDisbandOutcome('unknown', error: 'outcomeUnknown'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommunityDisbandDialog), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('重新读取确认'), findsNothing);
    expect(
      find.text(communityDisbandCopy['outcomeUnknown']!.$1),
      findsOneWidget,
    );
    expect(port.writes, 1);
  });
  testWidgets('wrong password requires reread and no password survives', (
    tester,
  ) async {
    final port = DisbandFake()
      ..outcome = const CommunityDisbandOutcome(
        'rejected',
        error: 'passwordInvalid',
      );
    addTearDown(port.changes.close);
    await openDisband(tester, port);
    await tester.enterText(find.byType(TextField), 'fixture');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('重新读取确认'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(port.writes, 1);
    expect(port.reads, 2);
  });
  testWidgets(
    'account invalidation clears password and late success cannot close dialog',
    (tester) async {
      final port = DisbandFake()
        ..writing = Completer<CommunityDisbandOutcome>();
      addTearDown(port.changes.close);
      await openDisband(tester, port);
      await tester.enterText(find.byType(TextField), 'fixture');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      port.changes.add(null);
      port.writing!.complete(const CommunityDisbandOutcome('accepted'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityDisbandDialog), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );
  testWidgets(
    'example confirmation needs no credential and closes after accepted',
    (tester) async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      await openDisband(
        tester,
        port,
        target: '00000000000000000000000000000002',
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text(communityDisbandCopy['example']!.$1), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityDisbandDialog), findsNothing);
      expect(
        (await port.read(
          view: 'mine',
          query: '',
        )).items.any((v) => v.targetRef == '00000000000000000000000000000002'),
        isFalse,
      );
    },
  );
  testWidgets(
    'owner entry refreshes joined list after disband and member entry stays hidden',
    (tester) async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var refreshed = 0;
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          target: '00000000000000000000000000000001',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('disband-community')), findsNothing);
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          target: '00000000000000000000000000000002',
          onGovernanceChanged: () async {
            refreshed++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-nav-danger')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-nav-danger')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('disband-community')),
      );
      await tester.tap(find.byKey(const ValueKey('disband-community')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(refreshed, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
