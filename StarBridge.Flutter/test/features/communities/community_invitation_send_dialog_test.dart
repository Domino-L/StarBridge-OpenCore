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
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import '../friends/social_layout_test.dart' show loadFonts;

class SendPort implements CommunitiesPort, CommunityInvitationSendPort {
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => events.stream;
  @override
  bool invitationSendingAvailable = true;
  bool empty = false, readFails = false;
  final writes = <(String, String, String, int)>[];
  final pages = <String?>[];
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    pages.add(after);
    if (readFails) throw const CommunityFailure('unavailable');
    return CommunityDirectory(
      view,
      query,
      empty
          ? []
          : [
              CommunityCard(
                targetRef: (after == null ? 'a' : 'b') * 32,
                name: after == null ? '探索同行' : '远航后勤',
                description: '长期协作，共同探索与后勤支援。',
                relationship: after == null ? 'member' : 'owner',
              ),
            ],
      next: !empty && after == null ? 'next' : null,
    );
  }

  @override
  Future<String> execute(String action, String targetRef) async =>
      throw UnimplementedError();
  @override
  Future<void> close() async {}
  @override
  Future<List<CommunityInvitationOperation>> readInvitationOutbox() async => [];
  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) async {
    writes.add((organizationRef, channel, destinationRef, maxUses));
    return CommunityInvitationProgress(operationId, 'unknown');
  }

  @override
  Future<CommunityInvitationProgress> resumeInvitation(
    String operationId, {
    String action = 'check',
  }) async => throw UnimplementedError();
}

void main() {
  late SendPort port;
  late CommunitiesModule organizations;
  setUpAll(loadFonts);
  setUp(() {
    port = SendPort();
    organizations = CommunitiesModule(port);
  });
  tearDown(() async {
    organizations.dispose();
    await port.events.close();
  });
  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'CN'),
    double width = 1000,
  }) async {
    tester.view.physicalSize = Size(width, 780);
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
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('send-capture'),
            child: CommunityInvitationSendDialog(
              organizations: organizations,
              port: port,
              recipient: Conversation(
                'c' * 32,
                '测试好友',
                '',
                DateTime.utc(2026),
                0,
                'friend',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder getSend() =>
      find.byKey(const ValueKey('send-organization-invitation'));
  testWidgets(
    'explicit source, unchanged private target and one use; unknown cannot send twice',
    (tester) async {
      await open(tester);
      expect(port.writes, isEmpty);
      expect(tester.widget<FilledButton>(getSend()).onPressed, isNull);
      await tester.tap(find.text('探索同行'));
      await tester.pumpAndSettle();
      await tester.tap(getSend());
      await tester.pumpAndSettle();
      expect(port.writes, [('a' * 32, 'private', 'c' * 32, 1)]);
      expect(tester.widget<FilledButton>(getSend()).onPressed, isNull);
      expect(find.textContaining('邀请发送记录'), findsOneWidget);
    },
  );
  testWidgets(
    'next page preserves selected membership and allows another organization',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('更多组织'));
      await tester.pumpAndSettle();
      expect(port.pages, [null, 'next']);
      await tester.tap(find.text('远航后勤'));
      await tester.pumpAndSettle();
      await tester.tap(getSend());
      await tester.pumpAndSettle();
      expect(port.writes.single.$1, 'b' * 32);
    },
  );
  testWidgets(
    'failed directory can reload; does not masquerade as no memberships',
    (tester) async {
      port.readFails = true;
      await open(tester);
      expect(find.text('重新读取组织'), findsOneWidget);
      port.readFails = false;
      await tester.tap(find.text('重新读取组织'));
      await tester.pumpAndSettle();
      expect(find.text('探索同行'), findsOneWidget);
      expect(port.writes, isEmpty);
    },
  );
  testWidgets('empty directory has no enabled send', (tester) async {
    port.empty = true;
    await open(tester);
    expect(find.textContaining('尚未加入组织'), findsOneWidget);
    expect(tester.widget<FilledButton>(getSend()).onPressed, isNull);
  });
  testWidgets(
    'account invalidation removes source and recipient; no late send',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('探索同行'));
      port.events.add(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('测试好友'), findsNothing);
      expect(find.text('探索同行'), findsNothing);
      expect(tester.widget<FilledButton>(getSend()).onPressed, isNull);
      expect(port.writes, isEmpty);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('picker fits narrow layout ${locale.toLanguageTag()}', (
      tester,
    ) async {
      await open(tester, locale: locale, width: 420);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('render actual invitation picker', (tester) async {
    await open(tester);
    await tester.tap(find.text('探索同行'));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('send-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/test-output/community-invitation-send.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}
