import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog_owner.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_attachment.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_card.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_invite_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invite_flow.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import '../../features/communities/community_admission_test.dart'
    show AdmissionInvites, AdmissionPrivacy;
import '../../features/communities/community_invitation_send_dialog_test.dart'
    show SendPort;
import '../../features/friends/user_interaction_test.dart' show MenuPort;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3am_test.dart' show action;

final recipient = Conversation(
  'c' * 32,
  'Original recipient',
  '',
  DateTime.utc(2026),
  0,
  'friend',
);
final nextRecipient = Conversation(
  'e' * 32,
  'New recipient',
  '',
  DateTime.utc(2026),
  0,
  'friend',
);
const actorTarget = UserTarget.community(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);

class Invitations extends SendPort implements CommunityInvitePort {
  final invites = AdmissionInvites();
  final ids = <String>[];
  final origins = <InteractionSource>[];
  int outboxReads = 0;
  String result = 'sent';
  bool outboxFails = false;
  Completer<CommunityInvitationProgress>? pending;
  @override
  Future<List<CommunityInvitationOperation>> readInvitationOutbox() async {
    outboxReads++;
    if (outboxFails) throw const CommunityFailure('localRecoveryUnavailable');
    return [];
  }

  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) async {
    ids.add(operationId);
    origins.add(currentStarBridgeActivationSource);
    writes.add((organizationRef, channel, destinationRef, maxUses));
    return pending == null
        ? CommunityInvitationProgress(operationId, result)
        : await pending!.future;
  }

  @override
  Future<CommunityInvitePreview> previewInvite(String code) =>
      invites.previewInvite(code);
  @override
  Future<CommunityInviteOutcome> acceptInvite(
    String requestId,
    String previewRef,
  ) => invites.acceptInvite(requestId, previewRef);
}

class Messages implements DirectMessagesPort, DirectMessageSender {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads = <(String, int, int)>[];
  int writes = 0;
  bool allowed = true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get supportsSending => true;
  @override
  Future<List<Conversation>> directory() async => [recipient, nextRecipient];
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    reads.add((ref, before, after));
    return DirectPage(ref, const [], 0, 0, false, 'friend', canSend: allowed);
  }

  @override
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  ) async {
    writes++;
    return const DirectSendResult('unknown');
  }

  @override
  void cancel() {}
  @override
  Future<void> close() async {
    if (!changes.isClosed) await changes.close();
  }
}

class Avatar extends MenuPort {
  final commands = <(String, String, InteractionSource)>[];
  final targets = <UserTarget>[];
  Completer<FriendCommandResult>? commandReply;
  String result = 'accepted';
  @override
  Future<FriendRow?> social(UserTarget target) {
    targets.add(target);
    return super.social(target);
  }

  @override
  Future<FriendCommandResult> execute(String action, String reference) async {
    commands.add((action, reference, currentStarBridgeActivationSource));
    return commandReply == null
        ? FriendCommandResult(
            result,
            error: result == 'accepted' ? null : 'outcomeUnknown',
          )
        : await commandReply!.future;
  }
}

Future<DirectMessagesModule> chat(Messages port) async {
  final model = DirectMessagesModule(port);
  await model.refresh();
  await model.open(recipient);
  model.editDraft('Retained chat draft');
  return model;
}

Widget sendEntry(
  CommunitiesModule organizations,
  DirectMessagesModule messages,
) => Builder(
  builder: (context) => Align(
    alignment: Alignment.topLeft,
    child: StarBridgeActionButton(
      controlKey: const Key('send-entry'),
      onActivate: (_) =>
          sendCommunityInvitationInChat(context, organizations, messages),
      child: const Text('Invite'),
    ),
  ),
);
Finder button(Key key) => find.byWidgetPredicate(
  (w) => w is StarBridgeActionButton && w.controlKey == key,
);
Future<void> openAvatar(
  WidgetTester t,
  String source, {
  bool settle = true,
}) async {
  final row = find.byWidgetPredicate(
    (w) =>
        w is StarBridgeActionRow &&
        w.controlKey == const Key('user-avatar-menu-anchor'),
  );
  await t.ensureVisible(row);
  if (source == 'pointer') {
    await t.tap(row);
  } else if (source == 'keyboard') {
    t.widget<StarBridgeActionRow>(row).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final config = t.widget<StarBridgeMenuAnchor>(
      find.byType(StarBridgeMenuAnchor),
    );
    final target = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.label == config.semanticLabel &&
          w.properties.onTap != null,
    );
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
  await t.pump();
  if (settle) await settleCommunityImages(t);
}

Widget avatar(
  Avatar port, {
  UserPageNavigation? navigation,
  bool self = false,
  List<AvatarMenuAction> extra = const [],
}) => UserInteractionScope(
  port: port,
  navigation: navigation ?? UserPageNavigation(),
  messagePage: (_, _) => const Text('Original conversation'),
  child: Align(
    alignment: Alignment.topLeft,
    child: UserAvatarMenu(
      name: 'Original peer',
      target: actorTarget,
      isSelf: self,
      actions: extra,
      child: const SizedBox(width: 48, height: 48),
    ),
  ),
);
Future<void> capture(WidgetTester t, GlobalKey key, String name) async =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      Directory('build/reviews/interaction-batch3ap')
          .createSync(recursive: true);
      File('build/reviews/interaction-batch3ap/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'real chat invitation source paging and exact single intent $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              port = Invitations(),
              messages = Messages();
          final organizations = CommunitiesModule(port),
              selected = await chat(messages);
          addTearDown(organizations.dispose);
          addTearDown(selected.dispose);
          addTearDown(port.events.close);
          addTearDown(port.invites.events.close);
          try {
            await mount(t, sendEntry(organizations, selected), suite);
            await action(t, const Key('send-entry'), source);
            expect(
              (ModalRoute.of(
                        t.element(find.byType(CommunityInvitationSendDialog)),
                      )!
                      as StarBridgeDialogRoute)
                  .instant,
              source != 'pointer',
            );
            expect(port.writes, isEmpty);
            expect(
              t
                  .widget<StarBridgeActionButton>(
                    button(const Key('send-organization-invitation')),
                  )
                  .onActivate,
              isNull,
            );
            await action(t, Key('invite-source-${'a' * 32}'), source);
            await action(
              t,
              const Key('invitation-send-more-organizations'),
              source,
            );
            expect(port.pages, [null, 'next']);
            await action(t, Key('invite-source-${'b' * 32}'), source);
            expect(port.writes, isEmpty);
            await action(t, const Key('send-organization-invitation'), source);
            expect(port.writes, [('b' * 32, 'private', recipient.ref, 1)]);
            expect(port.ids.single, matches(RegExp(r'^[a-f0-9]{32}$')));
            expect(
              port.origins.single,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(find.text('已发送'), findsOneWidget);
            expect(
              t
                  .widget<StarBridgeActionButton>(
                    button(const Key('send-organization-invitation')),
                  )
                  .onActivate,
              isNull,
            );
            await action(t, const Key('invitation-send-close'), source);
            expect(selected.draft, 'Retained chat draft');
            expect(messages.writes, 0);
            expect(messages.reads.length, 2);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'card uses original verification flow without accepting or saving privacy $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Invitations();
          final organizations = CommunitiesModule(port);
          addTearDown(organizations.dispose);
          addTearDown(port.events.close);
          addTearDown(port.invites.events.close);
          final privacy = AdmissionPrivacy(port.invites.calls);
          try {
            await mount(
              t,
              Builder(
                builder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: CommunityInvitationCard(
                    value: CommunityInvitationAttachment.parse({
                      'title': 'Original invitation',
                      'summary': 'Verify before joining',
                      'inviteCode': 'ABCDEF12',
                      'expiresAt': null,
                    }),
                    onOpen: () => openCommunityInvitation(
                      context,
                      organizations,
                      'ABCDEF12',
                      createPrivacy: () => privacy,
                    ),
                  ),
                ),
              ),
              suite,
            );
            await action(
              t,
              const Key('community-invitation-card-open'),
              source,
            );
            expect(
              (ModalRoute.of(t.element(find.byType(CommunityInviteDialog)))!
                      as StarBridgeDialogRoute)
                  .instant,
              source != 'pointer',
            );
            expect(port.invites.previews, 1);
            expect(port.invites.calls, isEmpty);
            await action(
              t,
              const Key('community-admission-close-icon'),
              source,
            );
            expect(privacy.closed, true);
            expect(port.invites.calls, isEmpty);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'avatar profile chat and exact social command never auto write $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Avatar();
          addTearDown(port.changes.close);
          final nav = UserPageNavigation();
          final opens = <(String, InteractionSource)>[];
          nav.open = (_, _, label) async {
            opens.add((label, currentStarBridgeActivationSource));
          };
          try {
            await mount(t, avatar(port, navigation: nav), suite);
            await openAvatar(t, source);
            expect(nativeViewportMenus.value, 1);
            expect(port.commands, isEmpty);
            final header = t.getSemantics(find.text('Original peer'));
            expect(
              header.getSemanticsData().hasAction(SemanticsAction.tap),
              false,
            );
            await action(
              t,
              const ValueKey<Object>('avatar-view-profile'),
              source,
            );
            expect(opens, [
              (
                'navigation.profile',
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            expect(nativeViewportMenus.value, 0);
            expect(port.commands, isEmpty);
            await openAvatar(t, source);
            await action(
              t,
              const ValueKey<Object>('avatar-send-message'),
              source,
            );
            expect(opens.last, (
              'direct.title',
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ));
            expect(port.commands, isEmpty);
            await openAvatar(t, source);
            await action(
              t,
              const ValueKey<Object>(('avatar-social', 'send')),
              source,
            );
            expect(port.commands, [
              (
                'send',
                'c' * 32,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            expect(nativeViewportMenus.value, 0);
            expect(
              port.targets.every(
                (value) =>
                    value.reference == actorTarget.reference &&
                    value.contextRef == actorTarget.contextRef,
              ),
              true,
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    for (final result in ['unknown', 'pending', 'rejected']) {
      testWidgets(
        'invitation $result locks original intent and preserves outbox ownership $suite',
        (t) async {
          final port = Invitations()..result = result, messages = Messages();
          final organizations = CommunitiesModule(port),
              selected = await chat(messages);
          addTearDown(organizations.dispose);
          addTearDown(selected.dispose);
          addTearDown(port.events.close);
          addTearDown(port.invites.events.close);
          await mount(t, sendEntry(organizations, selected), suite);
          await action(t, const Key('send-entry'), 'keyboard');
          await action(t, Key('invite-source-${'a' * 32}'), 'keyboard');
          await action(
            t,
            const Key('send-organization-invitation'),
            'keyboard',
          );
          expect(port.writes.length, 1);
          expect(
            t
                .widget<StarBridgeActionButton>(
                  button(const Key('send-organization-invitation')),
                )
                .onActivate,
            isNull,
          );
          expect(find.textContaining('邀请发送记录'), findsOneWidget);
          await action(t, const Key('invitation-send-close'), 'keyboard');
          expect(port.writes.length, 1);
          expect(selected.draft, 'Retained chat draft');
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final departure in ['caller', 'account', 'recipient']) {
      testWidgets(
        'pending invitation closes only its old $departure context without late refresh $suite',
        (t) async {
          final port = Invitations()..pending = Completer(),
              messages = Messages();
          final organizations = CommunitiesModule(port),
              selected = await chat(messages);
          addTearDown(organizations.dispose);
          addTearDown(selected.dispose);
          addTearDown(port.events.close);
          addTearDown(port.invites.events.close);
          final live = await mount(
            t,
            sendEntry(organizations, selected),
            suite,
          );
          await action(t, const Key('send-entry'), 'keyboard');
          await action(t, Key('invite-source-${'a' * 32}'), 'keyboard');
          await action(
            t,
            const Key('send-organization-invitation'),
            'keyboard',
            settle: false,
          );
          final before = messages.reads.length;
          if (departure == 'caller') {
            live.change(() => live.visible = false);
          } else if (departure == 'account') {
            port.events.add(null);
          } else {
            await selected.open(selected.rows.last);
          }
          await t.pump();
          await t.pump();
          port.pending!.complete(
            CommunityInvitationProgress(port.ids.single, 'sent'),
          );
          await settleCommunityImages(t);
          expect(find.byType(CommunityInvitationSendDialog), findsNothing);
          expect(port.writes.length, 1);
          expect(find.text('已发送'), findsNothing);
          expect(
            messages.reads.length,
            before + (departure == 'recipient' ? 1 : 0),
          );
          expect(messages.writes, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'invitation directory and outbox failure retry without fabricated empty or send $suite',
      (t) async {
        final port = Invitations()
              ..readFails = true
              ..outboxFails = true,
            messages = Messages();
        final organizations = CommunitiesModule(port),
            selected = await chat(messages);
        addTearDown(organizations.dispose);
        addTearDown(selected.dispose);
        addTearDown(port.events.close);
        addTearDown(port.invites.events.close);
        await mount(t, sendEntry(organizations, selected), suite);
        await action(t, const Key('send-entry'), 'keyboard');
        expect(find.text('重新读取组织'), findsOneWidget);
        expect(port.writes, isEmpty);
        port.readFails = false;
        await action(
          t,
          const Key('invitation-send-reload-organizations'),
          'keyboard',
        );
        port.outboxFails = false;
        await action(
          t,
          const Key('invitation-send-refresh-records'),
          'keyboard',
        );
        expect(find.text('探索同行'), findsOneWidget);
        expect(port.writes, isEmpty);
        await action(t, const Key('invitation-send-close'), 'keyboard');
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'verification retires when original card caller leaves $suite',
      (t) async {
        final port = Invitations();
        final organizations = CommunitiesModule(port);
        addTearDown(organizations.dispose);
        addTearDown(port.events.close);
        addTearDown(port.invites.events.close);
        final privacy = AdmissionPrivacy(port.invites.calls);
        final live = await mount(
          t,
          Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: CommunityInvitationCard(
                value: CommunityInvitationAttachment.parse({
                  'title': 'Original invitation',
                  'summary': 'Verify before joining',
                  'inviteCode': 'ABCDEF12',
                  'expiresAt': null,
                }),
                onOpen: () => openCommunityInvitation(
                  context,
                  organizations,
                  'ABCDEF12',
                  createPrivacy: () => privacy,
                ),
              ),
            ),
          ),
          suite,
        );
        await action(
          t,
          const Key('community-invitation-card-open'),
          'keyboard',
        );
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(find.byType(CommunityInviteDialog), findsNothing);
        expect(privacy.closed, true);
        expect(port.invites.calls, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'self profile chooses navigation once not fallback or social write $suite',
      (t) async {
        final port = Avatar();
        addTearDown(port.changes.close);
        var opened = 0, fallback = 0;
        final nav = UserPageNavigation()
          ..openSelf = (_) async {
            opened++;
          };
        await mount(
          t,
          Actions(
            actions: {
              OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                onInvoke: (_) {
                  fallback++;
                  return null;
                },
              ),
            },
            child: avatar(port, navigation: nav, self: true),
          ),
          suite,
        );
        await openAvatar(t, 'keyboard');
        expect(port.targets, isEmpty);
        await action(
          t,
          const ValueKey<Object>('avatar-view-profile'),
          'keyboard',
        );
        expect(opened, 1);
        expect(fallback, 0);
        expect(port.commands, isEmpty);
        expect(nativeViewportMenus.value, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'avatar custom danger action retains source while disabled item cannot activate $suite',
      (t) async {
        final port = Avatar();
        addTearDown(port.changes.close);
        final calls = <InteractionSource>[];
        await mount(
          t,
          avatar(
            port,
            extra: [
              AvatarMenuAction(
                'Scoped action',
                () => calls.add(currentStarBridgeActivationSource),
                color: Colors.red,
              ),
              const AvatarMenuAction('Disabled action', null),
            ],
          ),
          suite,
        );
        await openAvatar(t, 'keyboard');
        final disabled = t.getSemantics(
          find.byKey(
            const ValueKey<Object>(('avatar-custom', 'Disabled action', 0)),
          ),
        );
        expect(
          disabled.getSemanticsData().hasAction(SemanticsAction.tap),
          false,
        );
        await action(
          t,
          const ValueKey<Object>(('avatar-custom', 'Scoped action', 0)),
          'keyboard',
        );
        expect(calls, [InteractionSource.keyboard]);
        expect(port.commands, isEmpty);
        expect(nativeViewportMenus.value, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'avatar menu invalidation and disposal balance native viewport during loading $suite',
      (t) async {
        final port = Avatar()..held = Completer();
        addTearDown(port.changes.close);
        final live = await mount(t, avatar(port), suite);
        await openAvatar(t, 'pointer', settle: false);
        expect(nativeViewportMenus.value, 1);
        port.changes.add(null);
        await t.pump();
        await t.pump();
        port.held!.complete(port.row);
        await settleCommunityImages(t);
        expect(nativeViewportMenus.value, 0);
        expect(
          find.byKey(const ValueKey<Object>(('avatar-social', 'send'))),
          findsNothing,
        );
        await openAvatar(t, 'keyboard');
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(nativeViewportMenus.value, 0);
        expect(port.commands, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'live menu setting and escape retain identity but land instantly $suite',
      (t) async {
        final port = Avatar();
        addTearDown(port.changes.close);
        final live = await mount(t, avatar(port), suite);
        await openAvatar(t, 'pointer');
        live.change(() {
          live.light = true;
          live.reduce = true;
        });
        await t.pump();
        await t.pump();
        expect(find.text('Original peer'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(nativeViewportMenus.value, 0);
        expect(port.commands, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'owner guard schedules at most one check per rendered frame and stops on exit $suite',
      (t) async {
        var checks = 0, current = true;
        await mount(
          t,
          Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: StarBridgeActionButton(
                controlKey: const Key('guard-open'),
                onActivate: (_) => showStarBridgeDialog<void>(
                  context,
                  builder: (_) => StarBridgeDialogOwnerGuard(
                    isCurrent: () {
                      checks++;
                      return current;
                    },
                    child: const AlertDialog(title: Text('Owned dialog')),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
          suite,
        );
        await action(t, const Key('guard-open'), 'keyboard');
        final before = checks;
        for (var i = 0; i < 5; i++) {
          t.binding.scheduleFrame();
          await t.pump();
        }
        expect(checks - before, 5);
        current = false;
        t.binding.scheduleFrame();
        await t.pump();
        await t.pump();
        expect(find.text('Owned dialog'), findsNothing);
        final stopped = checks;
        for (var i = 0; i < 3; i++) {
          t.binding.scheduleFrame();
          await t.pump();
        }
        expect(checks, stopped);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'pending avatar command cannot repeat or announce on replacement port $suite',
      (t) async {
        final first = Avatar()..commandReply = Completer(), next = Avatar();
        addTearDown(first.changes.close);
        addTearDown(next.changes.close);
        var port = first;
        late StateSetter rebuild;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              rebuild = set;
              return avatar(port);
            },
          ),
          suite,
        );
        await openAvatar(t, 'keyboard');
        await action(
          t,
          const ValueKey<Object>(('avatar-social', 'send')),
          'keyboard',
          settle: false,
        );
        expect(first.commands.length, 1);
        await openAvatar(t, 'keyboard');
        final disabled = t.getSemantics(
          find.byKey(const ValueKey<Object>(('avatar-social', 'send'))),
        );
        expect(
          disabled.getSemanticsData().hasAction(SemanticsAction.tap),
          false,
        );
        rebuild(() => port = next);
        await t.pump();
        await t.pump();
        first.commandReply!.complete(const FriendCommandResult('accepted'));
        await settleCommunityImages(t);
        expect(first.commands.length, 1);
        expect(next.commands, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        expect(nativeViewportMenus.value, 0);
        await openAvatar(t, 'keyboard');
        await action(
          t,
          const ValueKey<Object>(('avatar-social', 'send')),
          'keyboard',
        );
        expect(next.commands.length, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'readonly menu header retains original snapshot through ordinary exit $suite',
      (t) async {
        final port = Avatar();
        addTearDown(port.changes.close);
        var name = 'Original peer';
        late StateSetter rebuild;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              rebuild = set;
              return UserInteractionScope(
                navigation: UserPageNavigation(),
                port: port,
                messagePage: null,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: UserAvatarMenu(
                    name: name,
                    target: actorTarget,
                    child: const SizedBox(width: 48, height: 48),
                  ),
                ),
              );
            },
          ),
          suite,
        );
        await openAvatar(t, 'pointer');
        await t.tapAt(const Offset(1100, 900));
        await t.pump();
        rebuild(() => name = 'New title');
        await t.pump();
        expect(find.text('Original peer'), findsOneWidget);
        expect(find.text('New title'), findsNothing);
        expect(nativeViewportMenus.value, 1);
        await settleCommunityImages(t);
        expect(nativeViewportMenus.value, 0);
        expect(port.commands, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'avatar maximum menu size scrolls keyboard target inside window $suite',
      (t) async {
        final port = Avatar();
        addTearDown(port.changes.close);
        await mount(
          t,
          avatar(
            port,
            extra: [
              for (var i = 0; i < 20; i++)
                AvatarMenuAction('Command $i', () {}),
            ],
          ),
          suite,
        );
        await openAvatar(t, 'keyboard');
        final surface = find.byType(SuiteSurfaceTransition);
        final rect = t.getRect(surface);
        expect(rect.width, lessThanOrEqualTo(320));
        expect(rect.height, lessThanOrEqualTo(480));
        expect(rect.left, greaterThanOrEqualTo(8));
        expect(rect.top, greaterThanOrEqualTo(8));
        for (var i = 0; i < 20; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await t.pump();
        }
        final last = find.byKey(
          const ValueKey<Object>(('avatar-custom', 'Command 19', 0)),
        );
        expect(t.getRect(last).bottom, lessThanOrEqualTo(rect.bottom + .1));
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleCommunityImages(t);
        expect(nativeViewportMenus.value, 0);
        expect(port.commands, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('render full actual invitation and avatar menu $suite', (
      t,
    ) async {
      final port = Invitations(), messages = Messages(), key = GlobalKey();
      final organizations = CommunitiesModule(port),
          selected = await chat(messages);
      addTearDown(organizations.dispose);
      addTearDown(selected.dispose);
      addTearDown(port.events.close);
      addTearDown(port.invites.events.close);
      await mount(t, sendEntry(organizations, selected), suite, capture: key);
      await action(t, const Key('send-entry'), 'pointer');
      await action(t, Key('invite-source-${'a' * 32}'), 'pointer');
      await capture(t, key, '${suite.name}-send');
      await action(t, const Key('invitation-send-close'), 'keyboard');
      final actor = Avatar();
      addTearDown(actor.changes.close);
      final second = GlobalKey();
      await mount(t, avatar(actor), suite, capture: second);
      await openAvatar(t, 'pointer');
      await capture(t, second, '${suite.name}-avatar');
      await t.pumpWidget(const SizedBox());
      expect(nativeViewportMenus.value, 0);
    });
  }
}
