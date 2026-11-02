import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_invitations.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_attachment.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../app/menu_overlay/menu_comms_session_test.dart' show Port;
import '../../app/menu_overlay/menu_comms_invitations_test.dart'
    show InvitePort;
import '../../features/communities/community_admission_test.dart'
    show AdmissionPrivacy;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ck_controls_test.dart' show fire, button;
import 'interaction_batch3cj_test.dart' show control;

const firstRef = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    secondRef = 'cccccccccccccccccccccccccccccccc';
Conversation peer(String ref, String name) =>
    Conversation(ref, name, '', DateTime.utc(2026), 0, 'accepted');
DirectPage page(
  String ref, {
  int oldest = 10,
  bool older = true,
  String text = 'Latest',
  bool attachment = false,
}) => DirectPage(
  ref,
  [
    DirectMessage(
      oldest,
      'hidden-message',
      true,
      text,
      DateTime.utc(2026),
      attachment ? 'fleet_invitation' : null,
      communityInvitation: attachment
          ? const CommunityInvitationAttachment(
              title: '组织 B',
              summary: '邀请摘要',
              inviteCode: 'secret-invite-code',
            )
          : null,
    ),
  ],
  oldest,
  oldest,
  older,
  'accepted',
  canSend: true,
);

class InvitationPort extends InvitePort {
  final destinations = <String>[];
  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) async {
    sends++;
    destinations.add(destinationRef);
    return CommunityInvitationProgress(operationId, 'unknown');
  }
}

class Owner {
  final port = Port(), invites = InvitationPort();
  late final privacy = AdmissionPrivacy(invites.calls);
  final view = ValueNotifier(const MenuCommsView('idle'));
  final actions = <(String, String, InteractionSource)>[];
  late MenuCommsSession session;
  Future<void> open(WidgetTester t, InteractionSuite suite) async {
    size(t, const Size(1100, 1000));
    session = MenuCommsSession(
      port,
      (raw) => view.value = MenuCommsView.parse(jsonEncode(raw)),
      invitations: (publish) =>
          MenuCommsInvitations(invites, publish, createPrivacy: () => privacy),
    )..show(true);
    port.directories.single.complete([
      peer(firstRef, 'A'),
      peer(secondRef, 'B'),
    ]);
    await t.pump();
    await t.pumpWidget(
      scopedApp(
        ValueListenableBuilder<MenuCommsView>(
          valueListenable: view,
          builder: (_, v, _) => MenuCommsPanel(
            view: v,
            embedded: true,
            active: false,
            onClose: () {},
            onAction: (a, k) {
              actions.add((a, k, currentStarBridgeActivationSource));
              session.act(a, k);
            },
          ),
        ),
        suite,
      ),
    );
    await frames(t, 2);
  }

  Future<void> select(
    WidgetTester t,
    String source,
    String name, {
    bool attachment = false,
  }) async {
    final target = view.value.rows.singleWhere((row) => row.name == name);
    await fire(
      t,
      source,
      find.byKey(ValueKey('menu-conversation-${target.key}')),
    );
    port.histories.last.reply.complete(
      page(name == 'A' ? firstRef : secondRef, attachment: attachment),
    );
    await frames(t, 2);
    expect(view.value.name, name);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    session.dispose();
    await t.pump(const Duration(seconds: 13));
    await privacy.events.close();
    view.dispose();
  }
}

Future<void> action(
  WidgetTester t,
  String source,
  String label, {
  bool generic = false,
}) async {
  await fire(t, source, generic ? control(label) : button(label));
  await frames(t, 2);
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final retirement in ['selection', 'account']) {
      testWidgets(
        '$suite actual invitation $retirement retirement rejects old attachment/grant and late preview',
        (t) async {
          final o = Owner();
          try {
            await o.open(t, suite);
            await o.select(t, 'pointer', 'A', attachment: true);
            final attachment = t
                .widget<StarBridgeActionButton>(button('查看组织邀请'))
                .onActivate!;
            await action(t, 'pointer', '邀请加入组织');
            final grant =
                o.view.value.invitation!.rows.single.buttons.single.key;
            await action(t, 'keyboard', '返回通讯');
            if (retirement == 'selection') {
              await o.select(t, 'keyboard', 'B');
            } else {
              o.invites.holdPreview = Completer<CommunityInvitePreview>();
              await action(t, 'pointer', '查看组织邀请');
              o.port.events.add(null);
              await t.pump();
              o.invites.holdPreview!.completeError(
                StateError('synthetic retired preview'),
              );
              o.port.directories.last.complete([peer(secondRef, 'B')]);
              await frames(t, 2);
            }
            final previews = o.invites.previews;
            attachment(InteractionSource.keyboard);
            o.session.act('inviteAction', grant);
            await frames(t, 2);
            expect(o.invites.previews, previews);
            expect(o.invites.sends + o.invites.resumes, 0);
            expect(o.invites.calls, isEmpty);
            expect(o.view.value.invitation, isNull);
            if (retirement == 'selection') {
              expect(o.view.value.name, 'B');
            } else {
              expect(o.view.value.rows.single.name, 'B');
            }
            expect(t.takeException(), isNull);
          } finally {
            await o.close(t);
          }
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source actual primary paging keeps cursor, read guard and late back retirement',
        (t) async {
          final semantics = t.ensureSemantics(), o = Owner();
          try {
            await o.open(t, suite);
            await o.select(t, source, 'A');
            final initial = o.port.histories.length;
            final retainedLatest = t
                .widget<StarBridgeActionButton>(button('刷新消息'))
                .onActivate!;
            await action(t, source, '较早消息');
            expect(o.port.histories, hasLength(initial + 1));
            expect(o.port.histories.last.before, 10);
            // UI remains usable, primary owner—not a new local busy flag—rejects
            // a second page command while the existing read is pending.
            // The first uncached older page uses the original no-name loading
            // projection. An already captured callback still cannot queue a
            // second read; do not invent retained history to make it visible.
            retainedLatest(InteractionSource.keyboard);
            expect(o.port.histories, hasLength(initial + 1));
            o.port.histories.last.reply.complete(
              page(firstRef, oldest: 1, older: false, text: 'Older'),
            );
            await frames(t, 2);
            expect(o.view.value.olderPage, true);
            expect(o.view.value.messages.single.text, 'Older');
            await action(t, source, '最新消息');
            expect(o.port.histories.last.before, 0);
            final late = o.port.histories.last.reply;
            await action(t, source, '返回会话列表');
            final directory = o.port.directories.last;
            late.complete(page(firstRef, text: 'Retired result'));
            await t.pump();
            directory.complete([peer(secondRef, 'B')]);
            await frames(t, 2);
            expect(o.view.value.name, isNull);
            expect(o.view.value.rows.single.name, 'B');
            expect(find.text('Retired result'), findsNothing);
            expect(o.port.sends + o.port.receipts, 0);
            expect(t.takeException(), isNull);
          } finally {
            await o.close(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source actual primary unavailable retry preserves content and rejects stale response',
        (t) async {
          final semantics = t.ensureSemantics(), o = Owner();
          try {
            await o.open(t, suite);
            await o.select(t, source, 'A');
            await action(t, source, '刷新消息');
            o.port.histories.last.reply.completeError(
              const DirectReadFailure('unavailable'),
            );
            await frames(t, 2);
            expect(o.view.value.messages.single.text, 'Latest');
            expect(o.view.value.notice, contains('草稿已保留'));
            final retainedRetry = t
                .widget<StarBridgeActionButton>(button('重新读取'))
                .onActivate!;
            await action(t, source, '重新读取');
            final stale = o.port.histories.last.reply;
            final cancels = o.port.cancels;
            retainedRetry(InteractionSource.keyboard);
            await frames(t, 2);
            expect(o.port.cancels, greaterThan(cancels));
            final current = o.port.histories.last.reply;
            current.complete(page(firstRef, text: 'Fresh retry'));
            await frames(t, 2);
            stale.complete(page(firstRef, text: 'Stale retry'));
            await frames(t, 2);
            expect(o.view.value.messages.single.text, 'Fresh retry');
            expect(o.view.value.notice, isEmpty);
            expect(o.port.sends + o.port.receipts, 0);
            expect(t.takeException(), isNull);
          } finally {
            await o.close(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source actual invitation records do not send and explicit confirmed send keeps unknown result',
        (t) async {
          final semantics = t.ensureSemantics(), o = Owner();
          try {
            await o.open(t, suite);
            await o.select(t, source, 'A');
            await action(t, source, '邀请发送记录');
            expect(o.view.value.invitation!.title, '邀请发送记录');
            expect(o.invites.sends + o.invites.resumes, 0);
            await action(t, source, '返回通讯');
            await action(t, source, '邀请加入组织');
            expect(
              o.view.value.invitation!.rows.single.buttons.single.label,
              '发送此组织邀请',
            );
            await action(t, source, '发送此组织邀请', generic: true);
            expect(o.invites.sends, 0);
            await action(t, source, '取消', generic: true);
            expect(o.invites.sends, 0);
            await action(t, source, '发送此组织邀请', generic: true);
            await action(t, source, '确认发送此组织邀请', generic: true);
            expect(o.invites.destinations, [firstRef]);
            expect(o.invites.sends, 1);
            expect(o.invites.resumes, 0);
            expect(o.view.value.invitation!.notice, isNot(contains('已发送成功')));
            expect(o.actions.any((a) => a.$1 == 'inviteAction'), true);
            expect(
              jsonEncode(o.view.value.invitation!.notice),
              isNot(contains(firstRef)),
            );
            expect(t.takeException(), isNull);
          } finally {
            await o.close(t);
            semantics.dispose();
          }
        },
      );
      for (final result in ['accepted', 'unknown', 'privacy-failure']) {
        testWidgets(
          '$suite $source actual attachment review $result saves choices before admission',
          (t) async {
            final semantics = t.ensureSemantics(), o = Owner();
            try {
              o.invites.result = CommunityInviteOutcome(
                result == 'accepted' ? 'accepted' : 'unknown',
              );
              o.privacy.failSave = result == 'privacy-failure';
              await o.open(t, suite);
              await o.select(t, source, 'A', attachment: true);
              expect(o.view.value.attachmentKeys.values.single, isNotEmpty);
              await action(t, source, '查看组织邀请');
              expect(o.invites.previews, 1);
              expect(o.invites.calls, isEmpty);
              expect(o.view.value.invitation!.title, '组织邀请');
              await action(t, source, '确认共享设置', generic: true);
              expect(o.invites.calls, ['read']);
              final toggle = o.view.value.invitation!.rows
                  .singleWhere((row) => row.title == '实时状态共享')
                  .buttons
                  .single;
              final toggleHost = find.byWidgetPredicate(
                (w) => w is MenuFeatureAction && w.action.key == toggle.key,
              );
              await fire(
                t,
                source,
                find.descendant(
                  of: toggleHost,
                  matching: control(toggle.label),
                ),
              );
              await frames(t, 2);
              await action(t, source, '我已确认共享选择', generic: true);
              await action(t, source, '保存选择并加入', generic: true);
              expect(o.invites.calls, ['read']);
              await action(t, source, '确认保存选择并加入', generic: true);
              expect(
                o.invites.calls,
                result == 'privacy-failure'
                    ? ['read', 'save']
                    : ['read', 'save', 'accept'],
              );
              expect(
                o.view.value.invitation!.notice.contains('已加入组织'),
                result == 'accepted',
              );
              expect(o.port.sends + o.port.receipts, 0);
              expect(o.invites.sends + o.invites.resumes, 0);
              expect(
                o.view.value.invitation!.notice,
                isNot(contains('secret-invite-code')),
              );
              expect(t.takeException(), isNull);
            } finally {
              await o.close(t);
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '$suite actual pending preview closes once and late completion cannot restore invitation flow',
      (t) async {
        final o = Owner();
        try {
          await o.open(t, suite);
          await o.select(t, 'pointer', 'A', attachment: true);
          o.invites.holdPreview = Completer<CommunityInvitePreview>();
          await action(t, 'pointer', '查看组织邀请');
          expect(o.view.value.invitation!.state, 'loading');
          await action(t, 'keyboard', '返回通讯');
          expect(o.view.value.invitation, isNull);
          o.invites.holdPreview!.complete(o.invites.value);
          await frames(t, 2);
          expect(o.view.value.invitation, isNull);
          expect(o.invites.calls, isEmpty);
          expect(o.invites.sends + o.invites.resumes, 0);
          expect(t.takeException(), isNull);
        } finally {
          await o.close(t);
        }
      },
    );
  }
}
