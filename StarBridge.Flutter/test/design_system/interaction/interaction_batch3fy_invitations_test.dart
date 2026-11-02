import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_invite_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_outbox_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_admission_test.dart'
    show AdmissionInvites, AdmissionPrivacy;
import '../../features/communities/community_invitation_send_controller_test.dart'
    show InvitationSendTestPort;
import '../../features/communities/community_invitation_send_dialog_test.dart'
    show SendPort;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fw_workspace_test.dart' show activate;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3af_test.dart' as draft show activate;

final _review = visualOutputDir(
  'interaction_motion_batch3fy_20261017',
  legacySubdirectory: 'review',
);
final _id = 'a' * 32;
CommunityInvitationOperation row([String phase = 'sending']) =>
    CommunityInvitationOperation(
      _id,
      'private',
      phase,
      '测试组织',
      '测试接收方',
      DateTime.utc(2026, 10, 17),
      1,
    );

class _Send extends SendPort {
  Completer<CommunityDirectory>? joinedReply;
  Completer<List<CommunityInvitationOperation>>? outboxReply;
  Completer<CommunityInvitationProgress>? sendReply;
  int outboxReads = 0;
  String? operationId;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) {
    if (joinedReply == null) {
      return super.read(
        view: view,
        query: query,
        after: after,
        filters: filters,
      );
    }
    pages.add(after);
    return joinedReply!.future;
  }

  @override
  Future<List<CommunityInvitationOperation>> readInvitationOutbox() {
    outboxReads++;
    return outboxReply?.future ?? Future.value([]);
  }

  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) {
    this.operationId = operationId;
    writes.add((organizationRef, channel, destinationRef, maxUses));
    return sendReply?.future ??
        Future.value(CommunityInvitationProgress(operationId, 'unknown'));
  }
}

class _Privacy extends AdmissionPrivacy {
  _Privacy(super.calls);
  LocalPrivacySettings? submitted;
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) {
    submitted = settings;
    return super.save(settings);
  }
}

class _Probe {
  _Probe(this.kind, this.suite, {this.light = false, this.large = false}) {
    privacy = _Privacy(invites.calls);
    organizations = CommunitiesModule(send);
  }
  final String kind;
  final invites = AdmissionInvites();
  late final _Privacy privacy;
  final outbox = InvitationSendTestPort();
  final send = _Send();
  late CommunitiesModule organizations;
  final capture = GlobalKey();
  InteractionSuite suite;
  bool reduce = false, light, large;
  late StateSetter update;
  Widget dialog() => switch (kind) {
    'admission' => CommunityInviteDialog(
      port: invites,
      privacy: privacy,
      initialCode: 'code',
    ),
    'outbox' => CommunityInvitationOutboxDialog(port: outbox),
    _ => CommunityInvitationSendDialog(
      organizations: organizations,
      port: send,
      recipient: Conversation(
        'c' * 32,
        '测试好友',
        '',
        DateTime.utc(2026),
        0,
        'friend',
      ),
    ),
  };
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open-invitation'),
              onActivate: (_) => showStarBridgeDialog<void>(
                context,
                barrierDismissible: false,
                builder: (_) => dialog(),
              ),
              child: const Text('Open invitation'),
            ),
          ),
          suite,
          light: light,
          reduce: reduce,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    organizations.dispose();
    await invites.events.close();
    await privacy.events.close();
    await outbox.events.close();
    await send.events.close();
    expect(t.takeException(), isNull);
  }
}

// ignore: library_private_types_in_public_api
Future<void> open(WidgetTester t, _Probe p, String source) async {
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
  await activate(t, const Key('open-invitation'), source);
  await frames(t);
}

Finder marker(String kind) => find.byKey(ValueKey('$kind-activity'));
void waitState(WidgetTester t, String kind, {required bool animated}) {
  final target = marker(kind);
  expect(target, findsOneWidget);
  final busy = find.descendant(
    of: target,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(busy, findsOneWidget);
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  Rect rect, {
  String? png,
}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (png != null) {
        await Directory(_review).create(recursive: true);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(data!.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      return [
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + rect.left.ceil()) * 4,
            (y * image.width + rect.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  moreCases();
  testWidgets('3fy keyboard initial outbox wait must not loop', (t) async {
    final p = _Probe('outbox', InteractionSuite.standard);
    p.outbox.readReply = Completer();
    try {
      await open(t, p, 'keyboard');
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNotNull,
      );
      p.outbox.readReply!.complete([]);
      await frames(t);
    } finally {
      await p.clean(t);
    }
  });

  for (final kind in ['admission', 'outbox', 'invitation-send']) {
    for (final suite in InteractionSuite.values) {
      if (kind == 'invitation-send') {
        testWidgets(
          '3fy $suite borrowed busy owner swap stays unknown and detached',
          (t) async {
            final p = _Probe(kind, suite);
            final old = p.organizations;
            final oldReply = Completer<CommunityDirectory>();
            p.send.joinedReply = oldReply;
            final oldRead = old.refreshJoined();
            try {
              await open(t, p, 'pointer');
              waitState(t, kind, animated: false);
              expect(p.send.pages, hasLength(1));
              final replacement = CommunitiesModule(p.send);
              final newReply = Completer<CommunityDirectory>();
              p.send.joinedReply = newReply;
              final newRead = replacement.refreshJoined();
              p.update(() => p.organizations = replacement);
              await frames(t);
              waitState(t, kind, animated: false);
              oldReply.complete(
                CommunityDirectory('joined', '', [
                  CommunityCard(
                    targetRef: 'a' * 32,
                    name: 'Old borrowed row',
                    relationship: 'member',
                  ),
                ]),
              );
              await oldRead;
              await frames(t);
              expect(old.joined.single.name, 'Old borrowed row');
              expect(find.text('Old borrowed row'), findsNothing);
              waitState(t, kind, animated: false);
              newReply.complete(
                CommunityDirectory('joined', '', [
                  CommunityCard(
                    targetRef: 'b' * 32,
                    name: 'Current borrowed row',
                    relationship: 'member',
                  ),
                ]),
              );
              await newRead;
              await frames(t);
              expect(find.text('Current borrowed row'), findsOneWidget);
              expect(marker(kind), findsNothing);
              expect(p.send.pages, hasLength(2));
              expect(p.send.writes, isEmpty);
            } finally {
              old.dispose();
              await p.clean(t);
            }
          },
        );
      }
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets('3fy $kind $suite $source initial wait and live reduce', (
          t,
        ) async {
          final p = _Probe(kind, suite);
          final semantics = t.ensureSemantics();
          p.invites.holdPreview = Completer();
          p.outbox.readReply = Completer();
          p.send.outboxReply = Completer();
          p.send.joinedReply = Completer();
          try {
            await open(t, p, source);
            waitState(t, kind, animated: source == 'pointer');
            p.update(() => p.reduce = true);
            await frames(t, 2);
            waitState(t, kind, animated: false);
            p.update(() => p.reduce = false);
            await frames(t, 2);
            waitState(t, kind, animated: source == 'pointer');
            if (kind == 'admission') {
              p.invites.holdPreview!.complete(p.invites.value);
            }
            if (kind == 'outbox') p.outbox.readReply!.complete([row()]);
            if (kind == 'invitation-send') {
              p.send.outboxReply!.complete([]);
              await frames(t);
              waitState(t, kind, animated: source == 'pointer');
              p.send.joinedReply!.complete(
                CommunityDirectory('joined', '', [
                  CommunityCard(
                    targetRef: 'a' * 32,
                    name: '测试组织',
                    relationship: 'member',
                  ),
                ]),
              );
            }
            await frames(t);
            expect(marker(kind), findsNothing);
            expect(p.invites.calls.where((c) => c == 'accept'), isEmpty);
            expect(p.outbox.calls.where((c) => c != 'read'), isEmpty);
            expect(p.send.writes, isEmpty);
          } finally {
            await p.clean(t);
            semantics.dispose();
          }
        });
      }
    }
  }
}

void moreCases() {
  for (final kind in ['admission', 'outbox', 'invitation-send']) {
    for (final suite in InteractionSuite.values) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '3fy $kind $suite $source real operation and final readback',
          (t) async {
            final p = _Probe(kind, suite);
            final semantics = t.ensureSemantics();
            p.outbox.items = [row()];
            try {
              await open(t, p, 'pointer');
              if (kind == 'admission') {
                p.privacy.holdRead = Completer();
                await activate(
                  t,
                  const Key('community-admission-join-review'),
                  source,
                );
                waitState(t, kind, animated: source == 'pointer');
                expect(p.invites.calls, ['read']);
                p.privacy.holdRead!.complete(p.privacy.snapshot);
                await frames(t);
                final ack = find.byWidgetPredicate(
                  (w) =>
                      w is StarBridgeCheckboxTile &&
                      w.controlKey ==
                          const Key('community-admission-acknowledge'),
                );
                await t.ensureVisible(ack);
                await frames(t);
                await draft.activate(t, ack, source);
                p.privacy.holdSave = Completer();
                p.invites.holdAccept = Completer();
                await t.ensureVisible(
                  find.byKey(const Key('community-admission-join-review')),
                );
                await frames(t, 2);
                await activate(
                  t,
                  const Key('community-admission-join-review'),
                  source,
                );
                waitState(t, kind, animated: source == 'pointer');
                expect(p.invites.calls, ['read', 'save']);
                expect(
                  p.privacy.submitted!.toJson(),
                  LocalPrivacySettings.editorDefaults.toJson(),
                );
                p.privacy.holdSave!.complete(
                  LocalPrivacySnapshot(
                    revision: 1,
                    settings: LocalPrivacySettings.editorDefaults,
                  ),
                );
                // Semantics dispatch can await the async fake port outside the
                // test's fake-microtask zone; deliver its actual event turn too.
                await t.runAsync(() => Future<void>.delayed(Duration.zero));
                await frames(t);
                expect(p.invites.calls, ['read', 'save', 'accept']);
                waitState(t, kind, animated: source == 'pointer');
                p.invites.holdAccept!.complete(
                  const CommunityInviteOutcome(
                    'unknown',
                    error: 'outcomeUnknown',
                  ),
                );
                await t.runAsync(() => Future<void>.delayed(Duration.zero));
                await frames(t);
                expect(marker(kind), findsNothing);
                expect(p.invites.calls, ['read', 'save', 'accept']);
                expect(
                  t
                      .getSemantics(
                        find.byKey(const Key('community-admission-verify')),
                      )
                      .getSemanticsData()
                      .hasAction(ui.SemanticsAction.tap),
                  isFalse,
                );
              } else if (kind == 'outbox') {
                final retry = ValueKey('community-outbox-retry-$_id');
                await activate(
                  t,
                  retry,
                  source == 'pointer' ? 'keyboard' : 'pointer',
                );
                await frames(t, 40);
                await activate(
                  t,
                  const Key('community-outbox-retry-cancel'),
                  source,
                );
                expect(p.outbox.calls, ['read']);
                await activate(
                  t,
                  retry,
                  source == 'pointer' ? 'keyboard' : 'pointer',
                );
                await frames(t, 40);
                p.outbox.reply = Completer();
                p.outbox.readReply = Completer();
                await activate(
                  t,
                  const Key('community-outbox-retry-confirm'),
                  source,
                );
                waitState(t, kind, animated: source == 'pointer');
                expect(p.outbox.calls, ['read', 'retryDelivery:$_id']);
                p.outbox.reply!.complete(
                  CommunityInvitationProgress(_id, 'sent'),
                );
                await frames(t);
                waitState(t, kind, animated: source == 'pointer');
                expect(p.outbox.calls, ['read', 'retryDelivery:$_id', 'read']);
                p.outbox.readReply!.complete([row('sent')]);
                await frames(t);
                expect(marker(kind), findsNothing);
                expect(find.byKey(retry), findsNothing);
                expect(
                  p.outbox.calls.where((c) => c.startsWith('send:')),
                  isEmpty,
                );
              } else {
                await activate(
                  t,
                  ValueKey('invite-source-${'a' * 32}'),
                  source,
                );
                p.send.sendReply = Completer();
                p.send.outboxReply = Completer();
                await activate(
                  t,
                  const ValueKey('send-organization-invitation'),
                  source,
                );
                waitState(t, kind, animated: source == 'pointer');
                expect(p.send.writes, [('a' * 32, 'private', 'c' * 32, 1)]);
                p.send.joinedReply = Completer();
                final background = p.organizations.refreshJoined();
                await frames(t);
                waitState(t, kind, animated: source == 'pointer');
                p.send.sendReply!.complete(
                  CommunityInvitationProgress(p.send.operationId!, 'unknown'),
                );
                await frames(t);
                waitState(t, kind, animated: source == 'pointer');
                expect(p.send.outboxReads, 2);
                p.send.outboxReply!.complete([]);
                await frames(t);
                waitState(t, kind, animated: false);
                p.send.joinedReply!.complete(
                  CommunityDirectory('joined', '', [
                    CommunityCard(
                      targetRef: 'a' * 32,
                      name: '测试组织',
                      relationship: 'member',
                    ),
                  ]),
                );
                await background;
                await frames(t);
                expect(marker(kind), findsNothing);
                expect(p.send.writes, hasLength(1));
                expect(
                  t
                      .getSemantics(
                        find.byKey(
                          const ValueKey('send-organization-invitation'),
                        ),
                      )
                      .getSemanticsData()
                      .hasAction(ui.SemanticsAction.tap),
                  isFalse,
                );
              }
            } finally {
              await p.clean(t);
              semantics.dispose();
            }
          },
        );
      }

      testWidgets(
        '3fy $kind $suite invalidation retires wait and late result',
        (t) async {
          final p = _Probe(kind, suite);
          p.invites.holdPreview = Completer();
          p.outbox.readReply = Completer();
          p.send.outboxReply = Completer();
          try {
            await open(t, p, 'pointer');
            waitState(t, kind, animated: true);
            if (kind == 'admission') p.invites.events.add(null);
            if (kind == 'outbox') p.outbox.events.add(null);
            if (kind == 'invitation-send') p.send.events.add(null);
            await frames(t);
            expect(marker(kind), findsNothing);
            if (kind == 'admission') {
              p.invites.holdPreview!.complete(p.invites.value);
            }
            if (kind == 'outbox') p.outbox.readReply!.complete([row()]);
            if (kind == 'invitation-send') p.send.outboxReply!.complete([]);
            await frames(t);
            expect(marker(kind), findsNothing);
            expect(p.invites.calls.where((c) => c == 'accept'), isEmpty);
            expect(p.outbox.calls.where((c) => c != 'read'), isEmpty);
            expect(p.send.writes, isEmpty);
          } finally {
            await p.clean(t);
          }
        },
      );

      testWidgets('3fy review $kind $suite existing wait slot and reduce', (
        t,
      ) async {
        final p = _Probe(
          kind,
          suite,
          large: true,
          light:
              suite == InteractionSuite.rail || suite == InteractionSuite.glow,
        );
        p.invites.holdPreview = Completer();
        p.outbox.items = [row()];
        p.send.outboxReply = Completer();
        try {
          await open(t, p, 'pointer');
          if (kind == 'outbox') {
            p.outbox.readReply = Completer();
            await activate(t, const Key('community-outbox-refresh'), 'pointer');
          }
          waitState(t, kind, animated: true);
          final rect = t.getRect(marker(kind));
          final name = '$kind-${suite.name}';
          final first = await pixels(t, p, rect, png: name);
          await frames(t, 12);
          final moving = changed(first, await pixels(t, p, rect));
          expect(moving, greaterThan(0));
          p.update(() => p.reduce = true);
          await frames(t, 2);
          waitState(t, kind, animated: false);
          final still = await pixels(t, p, rect);
          await frames(t, 38);
          final staticPixels = changed(still, await pixels(t, p, rect));
          expect(staticPixels, 0);
          expect(t.getRect(marker(kind)), rect);
          await t.runAsync(
            () => File('$_review/$name.json').writeAsString(
              jsonEncode({
                'movingPixels': moving,
                'staticPixels': staticPixels,
                'rect': [rect.left, rect.top, rect.width, rect.height],
              }),
            ),
          );
          await t.pumpWidget(const SizedBox());
          if (kind == 'admission') {
            p.invites.holdPreview!.complete(p.invites.value);
          }
          if (kind == 'outbox') p.outbox.readReply!.complete([row()]);
          if (kind == 'invitation-send') p.send.outboxReply!.complete([]);
          await frames(t);
        } finally {
          await p.clean(t);
        }
      });
    }
  }
}
