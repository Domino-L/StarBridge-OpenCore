import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/community_directory_details.dart';
import 'package:starbridge_flutter/features/communities/community_filter_panel.dart';
import 'package:starbridge_flutter/features/communities/community_invite_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_outbox_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';

import 'interaction_batch3ae_test.dart' show mount, action;
import 'interaction_batch3af_test.dart' show activate;
import '../../features/communities/community_admission_test.dart'
    show AdmissionInvites, AdmissionPrivacy;
import '../../features/communities/community_directory_preview_test.dart'
    show recruiting, ordinary;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/communities/community_invitation_send_controller_test.dart'
    show InvitationSendTestPort;
import '../../features/friends/social_layout_test.dart' show loadFonts;

class Invites extends AdmissionInvites {
  final sources = <(String, InteractionSource)>[];
  final acceptedRequests = <(String, String)>[];
  @override
  Future<CommunityInvitePreview> previewInvite(String code) {
    sources.add(('preview', currentStarBridgeActivationSource));
    return super.previewInvite(code);
  }

  @override
  Future<CommunityInviteOutcome> acceptInvite(String id, String ref) {
    sources.add(('accept', currentStarBridgeActivationSource));
    acceptedRequests.add((id, ref));
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) || ref != value.previewRef) {
      return Future.error(
        const FormatException('Invalid original admission intent'),
      );
    }
    calls.add('accept');
    return holdAccept?.future ?? Future.value(result);
  }
}

class Privacy extends AdmissionPrivacy {
  Privacy(super.calls);
  final sources = <(String, InteractionSource)>[];
  @override
  Future<LocalPrivacySnapshot> read() {
    sources.add(('privacy-read', currentStarBridgeActivationSource));
    return super.read();
  }

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) {
    sources.add(('privacy-save', currentStarBridgeActivationSource));
    return super.save(settings);
  }
}

class Directory
    implements
        CommunitiesPort,
        CommunityInvitePort,
        CommunityInvitationSendPort {
  final invites = Invites();
  final outbox = InvitationSendTestPort();
  final reads = <(String, String, String?, String?)>[];
  final writes = <(String, String, InteractionSource)>[];
  final recovery = <(String, InteractionSource)>[];
  bool readFail = false;
  bool paginated = false;
  Completer<String>? pendingWrite;
  Completer<CommunityDirectory>? pendingRead;
  @override
  Stream<void> get invalidations => invites.events.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    reads.add((view, query, after, filters));
    if (readFail) throw const CommunityFailure('unavailable');
    return pendingRead?.future ??
        CommunityDirectory(
          view,
          query,
          after == null ? [recruiting, ordinary] : [ordinary],
          next: paginated && after == null ? 'page-two' : null,
        );
  }

  @override
  Future<String> execute(String action, String ref) {
    writes.add((action, ref, currentStarBridgeActivationSource));
    return pendingWrite?.future ?? Future.value('rejected');
  }

  @override
  Future<void> close() async {}
  @override
  Future<CommunityInvitePreview> previewInvite(String code) =>
      invites.previewInvite(code);
  @override
  Future<CommunityInviteOutcome> acceptInvite(String id, String ref) =>
      invites.acceptInvite(id, ref);
  @override
  bool get invitationSendingAvailable => outbox.invitationSendingAvailable;
  @override
  Future<List<CommunityInvitationOperation>> readInvitationOutbox() =>
      outbox.readInvitationOutbox();
  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) => throw StateError('The directory/outbox must never allocate a new send');
  @override
  Future<CommunityInvitationProgress> resumeInvitation(
    String id, {
    String action = 'check',
  }) {
    recovery.add((action, currentStarBridgeActivationSource));
    return outbox.resumeInvitation(id, action: action);
  }

  Future<void> disposeFixtures() async {
    await invites.events.close();
    await outbox.events.close();
  }
}

const operation = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
CommunityInvitationOperation record(String phase) =>
    CommunityInvitationOperation(
      operation,
      'private',
      phase,
      'Original organization',
      'Original recipient',
      DateTime.utc(2026, 10, 1),
      1,
    );
Finder acknowledge() => find.byWidgetPredicate(
  (w) =>
      w is StarBridgeCheckboxTile &&
      w.controlKey == const Key('community-admission-acknowledge'),
);
Finder field(int bit) => find.byWidgetPredicate(
  (w) =>
      w is StarBridgeSwitch && w.controlKey == ValueKey('admission-field-$bit'),
);
Future<void> verify(WidgetTester t, String source) async {
  await t.enterText(find.byKey(const Key('community-admission-code')), 'code');
  await action(t, const Key('community-admission-verify'), source);
  await action(t, const Key('community-admission-join-review'), source);
}

Widget page(Directory port, CommunitiesModule module, Privacy privacy) =>
    CommunitiesPage(
      createPort: () => port,
      module: module,
      createAdmissionPrivacy: () => privacy,
    );
void expectRoute(WidgetTester t, Finder child, String source) {
  final route = ModalRoute.of(t.element(child))! as StarBridgeDialogRoute;
  expect(route.instant, source != 'pointer');
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'directory card body details and explicit commands do not conflate navigation $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = Directory();
          final owner = CommunitiesModule(port);
          final privacy = Privacy(port.invites.calls);
          addTearDown(owner.dispose);
          addTearDown(port.disposeFixtures);
          addTearDown(privacy.events.close);
          try {
            await mount(t, page(port, owner, privacy), suite);
            if (source == 'keyboard') {
              final root = find.byKey(
                const ValueKey('community-card-open-org-a'),
              );
              final focus = find
                  .descendant(
                    of: root,
                    matching: find.byWidgetPredicate(
                      (w) => w is Focus && w.focusNode?.canRequestFocus == true,
                    ),
                  )
                  .first;
              t.widget<Focus>(focus).focusNode!.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              await settleCommunityImages(t);
            } else {
              await action(
                t,
                const ValueKey('community-card-open-org-a'),
                source,
              );
            }
            expectRoute(t, find.byType(CommunityDirectoryDetails), source);
            expect(port.writes, isEmpty);
            expect(owner.selected, isNull);
            await action(
              t,
              const ValueKey('community-details-action-apply'),
              source,
            );
            expectRoute(t, find.byType(AlertDialog), source);
            await action(t, const Key('community-command-cancel'), source);
            expect(port.writes, isEmpty);
            await action(t, const Key('community-details-close'), source);
            await action(
              t,
              const ValueKey('community-card-primary-org-a'),
              source,
            );
            expect(find.byType(CommunityDirectoryDetails), findsNothing);
            await action(t, const Key('community-command-confirm'), source);
            expect(port.writes.single, (
              'apply',
              recruiting.targetRef,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ));
            expect(owner.selected, isNull);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'admission source consent six independent fields and save before accept $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = Directory();
          final module = CommunitiesModule(port),
              privacy = Privacy(port.invites.calls);
          privacy.snapshot = LocalPrivacySnapshot(
            revision: 4,
            settings: LocalPrivacySettings(
              publicationEnabled: true,
              fleetFields: 0,
              fleetAdministratorsCanView: true,
              fleetAllMembersCanView: false,
              fleetVisibilityGroupIds: ['keep-group'],
              roomFields: 5,
              roomAllMembersCanView: false,
            ),
          );
          addTearDown(module.dispose);
          addTearDown(port.disposeFixtures);
          addTearDown(privacy.events.close);
          try {
            await mount(t, page(port, module, privacy), suite);
            await action(t, const Key('community-admission-open'), source);
            expectRoute(t, find.byType(CommunityInviteDialog), source);
            await verify(t, source);
            expect(port.invites.calls, ['read']);
            final join = find.byWidgetPredicate(
              (w) =>
                  w is StarBridgeActionButton &&
                  w.controlKey == const Key('community-admission-join-review'),
            );
            expect(t.widget<StarBridgeActionButton>(join).onActivate, isNull);
            await activate(t, acknowledge(), source);
            for (final bit in [1, 2, 4, 8, 16, 32]) {
              await activate(t, field(bit), source);
            }
            expect(
              t.widget<StarBridgeCheckboxTile>(acknowledge()).value,
              false,
            );
            expect(t.widget<StarBridgeActionButton>(join).onActivate, isNull);
            await activate(t, acknowledge(), source);
            await action(
              t,
              const Key('community-admission-join-review'),
              source,
            );
            await settleCommunityImages(t);
            expect(port.invites.calls, ['read', 'save', 'accept']);
            expect(
              port.invites.acceptedRequests.single.$1,
              matches(RegExp(r'^[a-f0-9]{32}$')),
            );
            expect(
              port.invites.acceptedRequests.single.$2,
              port.invites.value.previewRef,
            );
            expect(privacy.snapshot.settings!.fleetFields, 63);
            expect(privacy.snapshot.settings!.roomFields, 5);
            expect(privacy.snapshot.settings!.roomAllMembersCanView, false);
            expect(privacy.snapshot.settings!.fleetVisibilityGroupIds, [
              'keep-group',
            ]);
            expect(privacy.snapshot.settings!.fleetAdministratorsCanView, true);
            expect(privacy.closed, true);
            for (final value in [...port.invites.sources, ...privacy.sources]) {
              expect(
                value.$2,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
            }
            expect(find.byType(CommunityInviteDialog), findsNothing);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'outbox original identity check continue and explicit retry $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = Directory();
          final owner = CommunitiesModule(port),
              privacy = Privacy(port.invites.calls);
          addTearDown(owner.dispose);
          addTearDown(port.disposeFixtures);
          addTearDown(privacy.events.close);
          port.outbox.items = [record('sending')];
          try {
            await mount(t, page(port, owner, privacy), suite);
            await action(t, const Key('community-outbox-open'), source);
            expectRoute(
              t,
              find.byType(CommunityInvitationOutboxDialog),
              source,
            );
            expect(port.outbox.calls, ['read']);
            await action(
              t,
              const ValueKey('community-outbox-retry-$operation'),
              source,
            );
            await action(t, const Key('community-outbox-retry-cancel'), source);
            expect(port.outbox.calls, ['read']);
            await action(
              t,
              const ValueKey('community-outbox-check-$operation'),
              source,
            );
            expect(port.outbox.calls, ['read', 'check:$operation', 'read']);
            await action(
              t,
              const ValueKey('community-outbox-retry-$operation'),
              source,
            );
            await action(
              t,
              const Key('community-outbox-retry-confirm'),
              source,
            );
            expect(
              port.outbox.calls.lastIndexOf('retryDelivery:$operation'),
              greaterThan(0),
            );
            port.outbox.items = [record('ready')];
            await action(t, const Key('community-outbox-refresh'), source);
            await action(
              t,
              const ValueKey('community-outbox-continue-$operation'),
              source,
            );
            expect(port.outbox.calls, contains('advance:$operation'));
            expect(
              port.recovery,
              everyElement(
                predicate<(String, InteractionSource)>(
                  (v) =>
                      v.$2 ==
                      (source == 'pointer'
                          ? InteractionSource.pointer
                          : InteractionSource.keyboard),
                ),
              ),
            );
            await action(t, const Key('community-outbox-close'), source);
            expect(find.byType(CommunityInvitationOutboxDialog), findsNothing);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    for (final status in ['unknown', 'rejected']) {
      testWidgets(
        'admission $status keeps confirmed privacy without repeated accept $suite',
        (t) async {
          final invites = Invites()
            ..result = CommunityInviteOutcome(
              status,
              error: status == 'unknown' ? 'outcomeUnknown' : 'inviteInvalid',
            );
          final privacy = Privacy(invites.calls);
          addTearDown(invites.events.close);
          addTearDown(privacy.events.close);
          await mount(
            t,
            CommunityInviteDialog(port: invites, privacy: privacy),
            suite,
          );
          await verify(t, 'keyboard');
          await activate(t, acknowledge(), 'keyboard');
          await action(
            t,
            const Key('community-admission-join-review'),
            'keyboard',
          );
          expect(invites.calls, ['read', 'save', 'accept']);
          expect(
            find.byKey(const Key('community-admission-join-review')),
            findsNothing,
          );
          expect(privacy.snapshot.revision, 1);
          if (status == 'unknown') {
            expect(
              t
                  .widget<TextField>(
                    find.byKey(const Key('community-admission-code')),
                  )
                  .enabled,
              false,
            );
          }
          await t.pumpWidget(const SizedBox());
          expect(privacy.closed, true);
        },
      );
    }
    testWidgets(
      'admission failed privacy does not accept and reload retains field draft $suite',
      (t) async {
        final invites = Invites(), privacy = Privacy([])..failSave = true;
        addTearDown(invites.events.close);
        addTearDown(privacy.events.close);
        await mount(
          t,
          CommunityInviteDialog(port: invites, privacy: privacy),
          suite,
        );
        await verify(t, 'keyboard');
        await activate(t, field(32), 'keyboard');
        await activate(t, acknowledge(), 'keyboard');
        await action(
          t,
          const Key('community-admission-join-review'),
          'keyboard',
        );
        expect(invites.calls, isEmpty);
        expect(privacy.calls, ['read', 'save']);
        expect(t.widget<StarBridgeSwitch>(field(32)).value, true);
        privacy.failSave = false;
        await action(
          t,
          const Key('community-admission-reload-privacy'),
          'keyboard',
        );
        expect(t.widget<StarBridgeSwitch>(field(32)).value, true);
        expect(t.widget<StarBridgeCheckboxTile>(acknowledge()).value, false);
        await activate(t, acknowledge(), 'keyboard');
        await action(
          t,
          const Key('community-admission-join-review'),
          'keyboard',
        );
        expect(invites.calls, ['accept']);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final state in ['already', 'conflict', 'expired']) {
      testWidgets('admission $state never exposes consent write $suite', (
        t,
      ) async {
        final invites = Invites()
          ..already = state == 'already'
          ..conflict = state == 'conflict'
          ..expiry = state == 'expired' ? DateTime.utc(2020) : null;
        final privacy = Privacy(invites.calls);
        addTearDown(invites.events.close);
        addTearDown(privacy.events.close);
        await mount(
          t,
          CommunityInviteDialog(port: invites, privacy: privacy),
          suite,
        );
        await t.enterText(
          find.byKey(const Key('community-admission-code')),
          'code',
        );
        await action(t, const Key('community-admission-verify'), 'keyboard');
        final button = find.byWidgetPredicate(
          (w) =>
              w is StarBridgeActionButton &&
              w.controlKey == const Key('community-admission-join-review'),
        );
        if (state == 'expired') {
          expect(t.widget<StarBridgeActionButton>(button).onActivate, isNull);
        } else {
          expect(button, findsNothing);
        }
        expect(invites.calls, isEmpty);
        await t.pumpWidget(const SizedBox());
      });
    }
    for (final child in ['filters', 'details', 'admission', 'outbox']) {
      testWidgets(
        'directory parent departure retires $child owned dialog $suite',
        (t) async {
          final port = Directory();
          final owner = CommunitiesModule(port),
              privacy = Privacy(port.invites.calls);
          addTearDown(owner.dispose);
          addTearDown(port.disposeFixtures);
          addTearDown(privacy.events.close);
          final live = await mount(t, page(port, owner, privacy), suite);
          final key = switch (child) {
            'filters' => const Key('community-directory-filters'),
            'details' => const ValueKey('community-card-open-org-a'),
            'admission' => const Key('community-admission-open'),
            _ => const Key('community-outbox-open'),
          };
          await action(t, key, 'keyboard');
          live.change(() => live.visible = false);
          await settleCommunityImages(t);
          expect(find.byType(CommunityInviteDialog), findsNothing);
          expect(find.byType(CommunityFilterPanel), findsNothing);
          expect(find.byType(CommunityDirectoryDetails), findsNothing);
          expect(find.byType(CommunityInvitationOutboxDialog), findsNothing);
          expect(port.writes, isEmpty);
          expect(port.invites.calls, isEmpty);
          if (child == 'admission') expect(privacy.closed, true);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'pending local privacy and late answer after account loss cannot accept $suite',
      (t) async {
        final port = Directory();
        final module = CommunitiesModule(port),
            privacy = Privacy(port.invites.calls)
              ..holdSave = Completer<LocalPrivacySnapshot>();
        addTearDown(module.dispose);
        addTearDown(port.disposeFixtures);
        addTearDown(privacy.events.close);
        final live = await mount(t, page(port, module, privacy), suite);
        await action(t, const Key('community-admission-open'), 'pointer');
        await verify(t, 'keyboard');
        await activate(t, acknowledge(), 'keyboard');
        await action(
          t,
          const Key('community-admission-join-review'),
          'keyboard',
          settle: false,
        );
        expect(port.invites.calls, ['read', 'save']);
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        port.invites.events.add(null);
        await settleCommunityImages(t);
        privacy.holdSave!.complete(
          LocalPrivacySnapshot(
            revision: 1,
            settings: LocalPrivacySettings.editorDefaults,
          ),
        );
        await settleCommunityImages(t);
        expect(port.invites.calls, ['read', 'save']);
        expect(privacy.closed, true);
        expect(find.byType(CommunityInviteDialog), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'directory search pagination explicit refresh and live filter route retain query $suite',
      (t) async {
        final port = Directory()..paginated = true;
        final module = CommunitiesModule(port),
            privacy = Privacy(port.invites.calls);
        addTearDown(module.dispose);
        addTearDown(port.disposeFixtures);
        addTearDown(privacy.events.close);
        final live = await mount(t, page(port, module, privacy), suite);
        final search = find.descendant(
          of: find.byType(CommunitiesPage),
          matching: find.byType(TextField),
        );
        await t.enterText(search, 'retained query');
        await action(t, const Key('community-directory-search'), 'keyboard');
        await action(t, const Key('community-directory-next'), 'keyboard');
        expect(port.reads.last.$2, 'retained query');
        expect(port.reads.last.$3, 'page-two');
        await action(t, const Key('community-directory-previous'), 'keyboard');
        expect(port.reads.last.$3, isNull);
        await action(
          t,
          const Key('community-directory-filters'),
          'pointer',
          settle: false,
        );
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        final route =
            ModalRoute.of(t.element(find.byType(CommunityFilterPanel)))!
                as StarBridgeDialogRoute;
        expect(route.animation!.value, 1);
        await action(t, const Key('community-filter-apply'), 'keyboard');
        expect(port.reads.last.$2, 'retained query');
        await action(t, const Key('community-directory-reset'), 'keyboard');
        expect(port.reads.last.$4, '{}');
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets(
      'public details actual foreground and footer geometry review $suite',
      (t) async {
        final port = Directory();
        final owner = CommunitiesModule(port),
            privacy = Privacy(port.invites.calls),
            capture = GlobalKey();
        addTearDown(owner.dispose);
        addTearDown(port.disposeFixtures);
        addTearDown(privacy.events.close);
        await mount(t, page(port, owner, privacy), suite, capture: capture);
        await action(t, const ValueKey('community-card-open-org-a'), 'pointer');
        final label = find.byKey(
          const ValueKey('community-details-description'),
        );
        final rect = t.getRect(label);
        final footer = t.getSize(
          find.byKey(const ValueKey('community-details-action-apply')),
        );
        expect(footer.height, greaterThanOrEqualTo(44));
        expect(footer.width, greaterThanOrEqualTo(126));
        final box =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await box.toImage();
          final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
          var count = 0;
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final i = (y * image.width + x) * 4;
              if (raw[i] >= 120 &&
                  raw[i + 1] >= 140 &&
                  raw[i + 2] >= 145 &&
                  raw[i + 3] > 240) {
                count++;
              }
            }
          }
          expect(count, greaterThan(10));
          final png = await image.toByteData(format: ImageByteFormat.png);
          io.Directory('build/reviews/interaction-batch3aj')
              .createSync(recursive: true);
          io.File(
            'build/reviews/interaction-batch3aj/${suite.name}-details.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
