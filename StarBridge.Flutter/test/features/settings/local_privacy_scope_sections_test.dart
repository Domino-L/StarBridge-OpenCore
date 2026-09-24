import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/privacy_scope_settings_strings.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'community_sharing_test.dart'
    show SharingFixture, target, membershipTime;
import 'local_privacy_page_test.dart' show app, viewport, MemoryPrivacy;

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    for (final entry in const {
      'Source Sans 3': 'SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load('assets/fonts/${entry.value}'))).load();
    }
  });
  testWidgets(
    'cards edit only their organization and preserve separate bits/groups',
    (tester) async {
      viewport(tester, const Size(1280, 900));
      final port = SharingFixture()
        ..settings = LocalPrivacySettings.editorDefaults.copyWith(
          roomFields: 63,
          communities: [
            CommunitySharingScope(
              code: 'A',
              joinedAt: membershipTime,
              fields: 1,
              administratorsCanView: false,
              allMembersCanView: false,
              visibilityGroupIds: ['kept-group'],
            ),
          ],
        );
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: controller)));
      await tester.pumpAndSettle();
      expect(port.writes, 0);
      expect(find.byKey(const Key('privacy-scope-A')), findsOneWidget);
      expect(find.byKey(const Key('privacy-scope-B')), findsOneWidget);
      final organizationLogo = find.descendant(
        of: find.byKey(const Key('privacy-scope-A')),
        matching: find.byType(CommunityLogo),
      );
      expect(tester.widget<CommunityLogo>(organizationLogo).framed, isFalse);
      expect(tester.getSize(organizationLogo), const Size(36, 36));
      for (final field in ['presence', 'ship', 'location', 'server']) {
        expect(
          tester
              .widget<InkWell>(
                find.byKey(Key('privacy-scope-official-fleet-field-$field')),
              )
              .onTap,
          isNull,
        );
      }
      await tapKey(tester, 'privacy-scope-A-field-ship');
      expect(controller.draft!.communities!.single.fields, 3);
      expect(controller.draft!.communities!.single.visibilityGroupIds, [
        'kept-group',
      ]);
      await tapKey(tester, 'privacy-scope-B-confirm-none');
      expect(controller.unconfirmedCommunities, isEmpty);
      expect(controller.draft!.communities!.last.fields, 0);
      await tapKey(tester, 'privacy-scope-room-field-server');
      expect(controller.draft!.roomFields, 55);
      expect(controller.draft!.fleetFields, port.settings.fleetFields);
      await tapKey(tester, 'privacy-save');
      expect(port.writes, 1);
      expect(port.applies, 1);
      expect(port.settings.communities!.map((s) => s.fields), [3, 0]);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PRIVACY')) {
        await tester.ensureVisible(find.byKey(const Key('privacy-scope-A')));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/privacy-organization-scopes.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets(
    'failed organization read retries automatically without clearing a dirty room',
    (tester) async {
      final port = SharingFixture()..failTargets = true;
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('privacy-organizations-failed')),
        findsOneWidget,
      );
      c.edit(c.draft!.copyWith(roomFields: 4));
      final draft = c.draft;
      port.failTargets = false;
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(c.communityTargetsFailed, false);
      expect(identical(c.draft, draft), true);
      expect(c.dirty, true);
      expect(port.writes, 0);
    },
  );

  testWidgets(
    'service capability failure is distinguished from a temporary read failure',
    (tester) async {
      final port = CurrentReceiptFixture()
        ..targetFailure = const BridgeClientException(
          'privacy_publication.community_scopes_unavailable',
        );
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      expect(
        c.communityTargetsFailure,
        CommunityTargetsFailure.serviceUnavailable,
      );
      expect(find.text('逐组织设置尚未上线'), findsOneWidget);
      expect(find.textContaining('组织资料没有丢失'), findsOneWidget);
      expect(find.textContaining('正在自动重试'), findsNothing);
      expect(find.text('已有共享仍在生效，逐组织设置暂不可用。'), findsOneWidget);
      expect(find.text('共享已生效'), findsNothing);
      c.edit(c.draft!.copyWith(roomFields: 4));
      final draft = c.draft;
      port.targetFailure = null;
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(c.communityTargetsFailure, CommunityTargetsFailure.none);
      expect(find.text('共享已生效'), findsOneWidget);
      expect(identical(c.draft, draft), true);
      expect(port.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy migration is explicit and an old dialog cannot authorize another account',
    (tester) async {
      final port = SharingFixture();
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'privacy-organizations-migrate');
      expect(c.draft!.communities, isNull);
      port.events.add(null);
      await tester.pumpAndSettle();
      await tapKey(tester, 'privacy-organizations-migrate-confirm');
      expect(c.draft!.communities, isNull);
      expect(port.writes, 0);
      await tapKey(tester, 'privacy-organizations-migrate');
      await tapKey(tester, 'privacy-organizations-migrate-confirm');
      expect(c.draft!.communities!.single.code, 'A');
      expect(port.writes, 0);
    },
  );

  testWidgets(
    'changed membership invalidates pending legacy migration confirmation',
    (tester) async {
      final port = SharingFixture();
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'privacy-organizations-migrate');
      port.targets = CommunitySharingTargets(
        primaryFleetCode: 'B',
        communities: [target('B')],
      );
      await c.refreshCommunityTargets();
      await tapKey(tester, 'privacy-organizations-migrate-confirm');
      expect(c.draft!.communities, isNull);
      expect(port.writes, 0);
    },
  );

  testWidgets('conflict reload requires explicit draft discard', (
    tester,
  ) async {
    final port = MemoryPrivacy();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    await tester.pumpAndSettle();
    c.edit(c.draft!.copyWith(roomFields: 0));
    port.failure = const BridgeClientException('privacy_local.conflict');
    await c.save();
    await tester.pumpAndSettle();
    await tapKey(tester, 'privacy-reload');
    await tapKey(tester, 'privacy-leave-cancel');
    expect(c.draft!.roomFields, 0);
    expect(c.needsReload, true);
    await tapKey(tester, 'privacy-reload');
    await tapKey(tester, 'privacy-leave-discard');
    expect(c.needsReload, false);
    expect(c.draft!.roomFields, LocalPrivacySettings.editorDefaults.roomFields);
  });

  testWidgets(
    'unchanged background membership renewal preserves confirmation',
    (tester) async {
      final port = SharingFixture();
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'privacy-organizations-migrate');
      port.targets = CommunitySharingTargets(
        primaryFleetCode: 'A',
        communities: [target('A'), target('B')],
      );
      await c.refreshCommunityTargets();
      await tapKey(tester, 'privacy-organizations-migrate-confirm');
      expect(c.draft!.communities!.single.code, 'A');
      expect(port.writes, 0);
    },
  );

  test(
    'fresh settings never inherit legacy organization or non-realtime grants',
    () async {
      final c = LocalPrivacyController(MemoryPrivacy());
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.hasSaved, false);
      expect(c.draft!.fleetFields, 0);
      expect(c.draft!.roomFields, 15);
      expect(c.draft!.communities, isNull);
      c.communityTargets = CommunitySharingTargets(
        primaryFleetCode: 'A',
        communities: [target('A')],
      );
      c.enableCommunityChoices();
      expect(c.draft!.communities, isEmpty);
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    testWidgets('organization cards fit narrow large-text $locale', (
      tester,
    ) async {
      viewport(tester, const Size(430, 900));
      final port = SharingFixture()
        ..settings = LocalPrivacySettings.editorDefaults.copyWith(
          communities: [],
        );
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(LocalPrivacyPage(controller: c), locale: locale, textScale: 1.6),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'privacy-scope-B-field-server');
      expect(c.draft!.communities!.single.fields, 8);
      expect(tester.takeException(), isNull);
      for (final key in simplifiedPrivacyScopeSettingsStrings.keys) {
        expect(AppStrings.resolve(locale).text(key), isNot(key));
      }
    });
  }

  testWidgets('stale publication acknowledgement is pending, not active', (
    tester,
  ) async {
    final port = StaleReceiptFixture()
      ..settings = LocalPrivacySettings.editorDefaults.copyWith(
        communities: [],
      );
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('privacy-publication-status')))
          .data,
      '等待服务器确认',
    );
  });
}

class StaleReceiptFixture extends SharingFixture {
  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async => PrivacyPublicationView('applied', revision: (revision ?? 1) - 1);
}

class CurrentReceiptFixture extends SharingFixture {
  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async => PrivacyPublicationView('applied', revision: this.revision);
}
