import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_attachment.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_card.dart';
import 'package:starbridge_flutter/features/communities/community_invite_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invite_flow.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/direct_messages/bridge_direct_messages.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';

import '../direct_messages/bridge_direct_messages_test.dart' show history;
import '../friends/social_layout_test.dart' show loadFonts;
import 'community_admission_test.dart';
import 'community_invite_dialog_test.dart' as dialog;

Map<String, Object?> card() => {
  'title': '组织邀请 · Alpha',
  'summary': '查看组织详情后决定是否加入。',
  'inviteCode': 'EXAMPLE-ORG',
  'expiresAt': null,
};

void main() {
  setUpAll(loadFonts);
  test(
    'history preserves invitation metadata without changing older attachments',
    () {
      final data = history();
      final row = (data['messages'] as List).single as Map;
      expect(parseDirectPage(data).messages.single.communityInvitation, isNull);
      row['attachmentKind'] = 'fleet_invitation';
      expect(parseDirectPage(data).messages.single.communityInvitation, isNull);
      row['communityInvitation'] = card();
      final value = parseDirectPage(data).messages.single.communityInvitation!;
      expect(value.inviteCode, 'EXAMPLE-ORG');
      expect(value.title, '组织邀请 · Alpha');
      expect(value.expiresAt, isNull);
      row['attachmentKind'] = 'overlay_preset';
      expect(() => parseDirectPage(data), throwsA(anything));
    },
  );
  for (final entry in <String, Object?>{
    'title': '',
    'summary': 'x' * 241,
    'inviteCode': 'x\n123456',
    'expiresAt': 'bad',
  }.entries) {
    test('malformed invitation ${entry.key} is rejected', () {
      final value = card()..[entry.key] = entry.value;
      expect(
        () => CommunityInvitationAttachment.parse(value),
        throwsFormatException,
      );
    });
  }
  testWidgets('card entry only verifies, never accepts or changes privacy', (
    tester,
  ) async {
    final invites = AdmissionInvites();
    final privacy = await dialog.open(tester, invites, initialCode: 'ABCDEF12');
    expect(invites.previews, 1);
    expect(invites.calls, isEmpty);
    expect(find.text('组织 B · B'), findsOneWidget);
    expect(find.text('ABCDEF12'), findsOneWidget);
    invites.events.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityInviteDialog), findsNothing);
    expect(privacy.closed, isTrue);
  });
  testWidgets('revoked card code remains in verification flow, no acceptance', (
    tester,
  ) async {
    final invites = AdmissionInvites();
    await dialog.open(tester, invites, initialCode: 'bad');
    expect(invites.previews, 1);
    expect(invites.calls, isEmpty);
    expect(find.text(dialog.text(tester, 'inviteInvalid')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      testWidgets('bounded card with contained action $locale $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 750);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var opens = 0;
        final value = CommunityInvitationAttachment.parse(
          card()..['expiresAt'] = '2000-01-01T00:00:00Z',
        );
        await tester.pumpWidget(
          dialog.app(
            Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: const ValueKey('card-capture'),
                  child: CommunityInvitationCard(
                    value: value,
                    onOpen: () => opens++,
                  ),
                ),
              ),
            ),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(opens, 0);
        final bounds = tester.getRect(find.byType(CommunityInvitationCard));
        expect(bounds.height, lessThan(400));
        final button = tester.getRect(find.byType(OutlinedButton));
        expect(
          bounds.contains(button.topLeft) &&
              bounds.contains(button.bottomRight),
          isTrue,
        );
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(opens, 1);
        if (locale == const Locale('zh', 'CN') && width == 1200) {
          await tester.runAsync(() async {
            final box = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('card-capture')),
            );
            final image = await box.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/community-invitation-card-review.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'private chat card opens shared example verification, draft survives',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final communities = CommunitiesModule(ExampleCommunities());
      addTearDown(communities.dispose);
      await communities.refreshJoined();
      final originalKeys = communities.joined.map((c) => c.key).toSet();
      final messages = ExampleDirectMessages();
      final friend = (await messages.directory()).first;
      await tester.pumpWidget(
        dialog.app(
          Scaffold(
            body: DirectMessagesPage(
              createPort: () => messages,
              onBack: () {},
              initialConversation: friend,
              openCommunityInvite: (context, code) =>
                  openCommunityInvitation(context, communities, code),
            ),
          ),
          const Locale('zh', 'CN'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '未发送草稿');
      await tester.tap(find.widgetWithText(OutlinedButton, '查看邀请'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityInviteDialog), findsOneWidget);
      expect(find.text('示例 · 新手互助 · EXAMPLE-ORG'), findsOneWidget);
      expect(
        (await (communities.port as ExampleCommunities).previewInvite(
          'EXAMPLE-ORG',
        )).alreadyMember,
        isFalse,
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityInviteDialog), findsNothing);
      expect(find.text('未发送草稿'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '查看邀请'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, dialog.text(tester, 'review')),
      );
      await tester.pumpAndSettle();
      await dialog.acknowledge(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, dialog.text(tester, 'join')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommunityInviteDialog), findsNothing);
      expect(
        communities.joined.map((c) => c.key).toSet().containsAll(originalKeys),
        isTrue,
      );
      expect(communities.joined.length, originalKeys.length + 1);
      expect(find.text('未发送草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
