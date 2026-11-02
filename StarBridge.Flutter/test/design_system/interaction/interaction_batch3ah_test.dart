import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/account/account_avatar.dart';
import 'package:starbridge_flutter/features/account/account_avatar_editor.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/communities/community_logo_crop.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_image_editor.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_images.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'interaction_batch3ae_test.dart' show mount, action;
import '../../features/communities/community_creation_dialog_test.dart'
    show FormPort;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;

class Connection implements BridgeConnection {
  final incomingController = StreamController<BridgeEnvelope>.broadcast();
  final requests = <BridgeEnvelope>[];
  final origins = <InteractionSource>[];
  String? holding;
  BridgeEnvelope? held;
  bool pickCancel = false, saveReject = false;
  @override
  Stream<BridgeEnvelope> get incoming => incomingController.stream;
  @override
  Future<void> close() => incomingController.close();
  @override
  Future<void> send(BridgeEnvelope request) async {
    requests.add(request);
    origins.add(currentStarBridgeActivationSource);
    if (request.name == holding) {
      held = request;
      return;
    }
    reply(request);
  }

  void reply(BridgeEnvelope request) {
    incomingController.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        status: 'ok',
        accountContext: const BridgeAccountContext(
          environment: 'test',
          authority: 'scm-test',
          subject: 'subject-one',
        ),
        payload: {
          'schemaVersion': 1,
          'state': 'signedIn',
          'imageData': saveReject && request.name == 'account.updateAvatar'
              ? 'rejected'
              : FormPort.image,
          'status': pickCancel ? 'cancelled' : 'selected',
          'source': {
            'sourceRef': 'avatar-source',
            'previewImageData': FormPort.image,
            'width': 300,
            'height': 200,
          },
        },
      ),
    );
  }

  void release() {
    final request = held!;
    held = null;
    holding = null;
    reply(request);
  }

  void switchAccount() {
    incomingController.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 8,
        sequence: 1,
        payload: const {'schemaVersion': 1},
      ),
    );
  }
}

BridgeClientSession session(Connection connection) =>
    BridgeClientSession(connection: connection, sessionGeneration: 7)
      ..acceptHostCapabilities({
        'account.avatar',
        'account.avatarImages',
        'account.scmAvatar',
      });
Widget avatar(AccountAvatarPort port, {bool editable = true}) =>
    AccountAvatarScope(
      port: port,
      imageData: null,
      editable: editable,
      child: const AccountAvatarEditor(),
    );

class Images implements LocalHangarImagePort {
  final calls = <(String, InteractionSource)>[];
  String? currentImage;
  bool cancel = false, saveFail = false, restoreFail = false;
  Completer<String?>? reading;
  Completer<CommunityLogoSource?>? picking;
  Completer<void>? saving, restoring;
  @override
  bool get canPickLogo => true;
  @override
  Future<String?> readImage() => reading?.future ?? Future.value(currentImage);
  @override
  Future<CommunityLogoSource?> pickLogo() {
    calls.add(('pick', currentStarBridgeActivationSource));
    return picking?.future ??
        Future.value(
          cancel
              ? null
              : const CommunityLogoSource(
                  'local-source',
                  FormPort.image,
                  300,
                  200,
                ),
        );
  }

  @override
  Future<String> cropLogo(String ref, double x, double y, double size) async {
    calls.add(('crop', currentStarBridgeActivationSource));
    return FormPort.image;
  }

  @override
  Future<void> clearLogo() async {
    calls.add(('clear', currentStarBridgeActivationSource));
  }

  @override
  Future<void> saveImage() {
    calls.add(('save', currentStarBridgeActivationSource));
    if (saving != null) return saving!.future;
    if (saveFail) return Future.error(StateError('uncertain'));
    currentImage = FormPort.image;
    return Future.value();
  }

  @override
  Future<void> restoreImage() {
    calls.add(('restore', currentStarBridgeActivationSource));
    if (restoring != null) return restoring!.future;
    if (restoreFail) return Future.error(StateError('uncertain'));
    currentImage = null;
    return Future.value();
  }

  int count(String name) => calls.where((c) => c.$1 == name).length;
}

Widget local(Images port, VoidCallback saved, {bool editable = true}) =>
    LocalHangarImageEditor(
      port: port,
      onSaved: saved,
      editable: editable,
      fallback: const Text('catalog'),
    );
void expectRoute(WidgetTester t, String source, Finder child) {
  final route = ModalRoute.of(t.element(child))! as StarBridgeDialogRoute;
  expect(route.instant, source != 'pointer');
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'account avatar native boundary explicit confirmation and cleanup $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final wire = Connection();
          final s = session(wire);
          addTearDown(s.close);
          try {
            await mount(t, avatar(AccountAvatarPort(s)), suite);
            await action(t, const Key('profile-change-account-avatar'), source);
            expectRoute(t, source, find.byType(CommunityLogoCrop));
            await action(t, const Key('community-crop-apply'), source);
            expectRoute(t, source, find.byType(AlertDialog));
            expect(
              wire.requests.where((r) => r.name == 'account.updateAvatar'),
              isEmpty,
            );
            await action(t, const Key('account-avatar-confirm-save'), source);
            final index = wire.requests.indexWhere(
              (r) => r.name == 'account.updateAvatar',
            );
            expect(index, greaterThan(0));
            final saved = wire.requests[index];
            expect(saved.accountContext?.subject, 'subject-one');
            expect(saved.sessionGeneration, 7);
            expect(saved.payload, {
              'schemaVersion': 1,
              'imageData': FormPort.image,
            });
            expect(
              wire.origins[index],
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(
              wire.requests.where((r) => r.name == 'account.updateAvatar'),
              hasLength(1),
            );
            expect(
              wire.requests.where((r) => r.name == 'account.clearAvatarDraft'),
              hasLength(1),
            );
            expect(find.text('账号头像已更换。'), findsOneWidget);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets('local image scoped save restore and source $suite $source', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final port = Images();
        var saved = 0;
        try {
          await mount(t, local(port, () => saved++), suite);
          await action(t, const Key('hangar-image-choose'), source);
          expectRoute(t, source, find.byType(CommunityLogoCrop));
          await action(t, const Key('community-crop-apply'), source);
          expectRoute(t, source, find.byType(AlertDialog));
          expect(port.count('save'), 0);
          expect(find.textContaining('不会上传'), findsOneWidget);
          await action(t, const Key('hangar-image-confirm'), source);
          expect(port.count('save'), 1);
          expect(port.count('clear'), 1);
          expect(saved, 1);
          expect(
            port.calls.firstWhere((c) => c.$1 == 'save').$2,
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          );
          expect(find.text('已保存到本机。'), findsOneWidget);
          await action(t, const Key('hangar-image-restore'), source);
          await action(t, const Key('hangar-image-restore-cancel'), source);
          expect(port.count('restore'), 0);
          expect(saved, 1);
          await action(t, const Key('hangar-image-restore'), source);
          await action(t, const Key('hangar-image-restore-confirm'), source);
          expect(port.count('restore'), 1);
          expect(saved, 2);
          expect(find.text('catalog'), findsOneWidget);
          await t.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      });
    }
    testWidgets(
      'account cancel pick and cancel confirmation never write $suite',
      (t) async {
        final wire = Connection()..pickCancel = true;
        final s = session(wire);
        addTearDown(s.close);
        final port = AccountAvatarPort(s);
        await mount(t, avatar(port), suite);
        await action(t, const Key('profile-change-account-avatar'), 'keyboard');
        expect(find.byType(CommunityLogoCrop), findsNothing);
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          isEmpty,
        );
        wire.pickCancel = false;
        await action(t, const Key('profile-change-account-avatar'), 'keyboard');
        await action(t, const Key('community-crop-apply'), 'keyboard');
        await action(t, const Key('account-avatar-confirm-cancel'), 'keyboard');
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          isEmpty,
        );
        expect(
          wire.requests.where((r) => r.name == 'account.clearAvatarDraft'),
          hasLength(2),
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'account selection delayed across frames keeps initiating keyboard source $suite',
      (t) async {
        final wire = Connection()..holding = 'account.pickAvatar';
        final s = session(wire);
        addTearDown(s.close);
        await mount(t, avatar(AccountAvatarPort(s)), suite);
        await action(
          t,
          const Key('profile-change-account-avatar'),
          'keyboard',
          settle: false,
        );
        await t.pump(const Duration(milliseconds: 150));
        wire.release();
        await settleCommunityImages(t);
        expectRoute(t, 'keyboard', find.byType(CommunityLogoCrop));
        await action(t, const Key('community-crop-cancel'), 'keyboard');
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          isEmpty,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'account generation change retires confirmation without foreign write $suite',
      (t) async {
        final wire = Connection();
        final s = session(wire);
        addTearDown(s.close);
        await mount(t, avatar(AccountAvatarPort(s)), suite);
        await action(t, const Key('profile-change-account-avatar'), 'pointer');
        await action(t, const Key('community-crop-apply'), 'pointer');
        expect(find.byType(AlertDialog), findsOneWidget);
        wire.switchAccount();
        await settleCommunityImages(t);
        expect(find.byType(AlertDialog), findsNothing);
        expect(s.activeGeneration, 8);
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          isEmpty,
        );
        expect(
          wire.requests.where((r) => r.name == 'account.clearAvatarDraft'),
          isEmpty,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'account departure during crop removes only owned surface $suite',
      (t) async {
        final wire = Connection();
        final s = session(wire);
        addTearDown(s.close);
        final live = await mount(t, avatar(AccountAvatarPort(s)), suite);
        await action(t, const Key('profile-change-account-avatar'), 'pointer');
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(find.byType(CommunityLogoCrop), findsNothing);
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          isEmpty,
        );
        expect(
          wire.requests.where((r) => r.name == 'account.clearAvatarDraft'),
          hasLength(1),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'account rejected confirmation result never shows saved $suite',
      (t) async {
        final wire = Connection()..saveReject = true;
        final s = session(wire);
        addTearDown(s.close);
        await mount(t, avatar(AccountAvatarPort(s)), suite);
        await action(t, const Key('profile-change-account-avatar'), 'keyboard');
        await action(t, const Key('community-crop-apply'), 'keyboard');
        await action(t, const Key('account-avatar-confirm-save'), 'keyboard');
        expect(find.text('账号头像已更换。'), findsNothing);
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          hasLength(1),
        );
        expect(
          wire.requests.where((r) => r.name == 'account.clearAvatarDraft'),
          hasLength(1),
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final step in ['save', 'restore']) {
      testWidgets(
        'local image pending $step failure remains uncertain without callback $suite',
        (t) async {
          final port = Images()
            ..currentImage = step == 'restore' ? FormPort.image : null;
          var saved = 0;
          if (step == 'save') {
            port.saving = Completer<void>();
          } else {
            port.restoring = Completer<void>();
          }
          final live = await mount(t, local(port, () => saved++), suite);
          if (step == 'save') {
            await action(t, const Key('hangar-image-choose'), 'pointer');
            await action(t, const Key('community-crop-apply'), 'pointer');
          } else {
            await action(t, const Key('hangar-image-restore'), 'pointer');
          }
          await action(
            t,
            Key(
              step == 'save'
                  ? 'hangar-image-confirm'
                  : 'hangar-image-restore-confirm',
            ),
            'keyboard',
            settle: false,
          );
          expect(port.count(step), 1);
          expect(saved, 0);
          live.change(() {
            live.reduce = true;
            live.light = true;
          });
          await t.pump();
          await t.pump();
          (step == 'save' ? port.saving : port.restoring)!.completeError(
            StateError('uncertain'),
          );
          await settleCommunityImages(t);
          expect(saved, 0);
          expect(find.textContaining('无法确认保存结果'), findsOneWidget);
          expect(port.count(step), 1);
          expect(find.text('已保存到本机。'), findsNothing);
          expect(find.text('已恢复默认图片。'), findsNothing);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'local image late reply after port replacement cannot report new ship saved $suite',
      (t) async {
        final old = Images()..saving = Completer<void>(), next = Images();
        var saved = 0;
        late StateSetter set;
        var active = old;
        await mount(
          t,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return local(active, () => saved++);
            },
          ),
          suite,
        );
        await action(t, const Key('hangar-image-choose'), 'keyboard');
        await action(t, const Key('community-crop-apply'), 'keyboard');
        await action(
          t,
          const Key('hangar-image-confirm'),
          'keyboard',
          settle: false,
        );
        set(() => active = next);
        await t.pump();
        old.saving!.complete();
        await settleCommunityImages(t);
        expect(saved, 0);
        expect(next.calls, isEmpty);
        expect(old.count('clear'), 1);
        expect(find.text('已保存到本机。'), findsNothing);
        expect(find.text('catalog'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'local image pending pick after departure clears original buffer only $suite',
      (t) async {
        final port = Images()..picking = Completer<CommunityLogoSource?>();
        var saved = 0;
        final live = await mount(t, local(port, () => saved++), suite);
        await action(
          t,
          const Key('hangar-image-choose'),
          'keyboard',
          settle: false,
        );
        live.change(() => live.visible = false);
        await t.pump();
        port.picking!.complete(
          const CommunityLogoSource('old', FormPort.image, 300, 200),
        );
        await settleCommunityImages(t);
        expect(find.byType(CommunityLogoCrop), findsNothing);
        expect(port.count('clear'), 1);
        expect(port.count('save'), 0);
        expect(saved, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'account permission removal retires existing confirmation $suite',
      (t) async {
        final wire = Connection(), s = session(wire);
        addTearDown(s.close);
        final port = AccountAvatarPort(s);
        var editable = true;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              update = set;
              return avatar(port, editable: editable);
            },
          ),
          suite,
        );
        await action(t, const Key('profile-change-account-avatar'), 'keyboard');
        await action(t, const Key('community-crop-apply'), 'keyboard');
        update(() => editable = false);
        await settleCommunityImages(t);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          isEmpty,
        );
        expect(
          wire.requests.where((r) => r.name == 'account.clearAvatarDraft'),
          hasLength(1),
        );
        expect(
          find.byKey(const Key('profile-change-account-avatar')),
          findsNothing,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'local permission removal retires existing crop without saving $suite',
      (t) async {
        final port = Images();
        var editable = true, saved = 0;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              update = set;
              return local(port, () => saved++, editable: editable);
            },
          ),
          suite,
        );
        await action(t, const Key('hangar-image-choose'), 'keyboard');
        update(() => editable = false);
        await settleCommunityImages(t);
        expect(find.byType(CommunityLogoCrop), findsNothing);
        expect(port.count('crop'), 0);
        expect(port.count('save'), 0);
        expect(port.count('clear'), 1);
        expect(saved, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'account late save after generation advance never reports saved $suite',
      (t) async {
        final wire = Connection(), s = session(wire);
        addTearDown(s.close);
        await mount(t, avatar(AccountAvatarPort(s)), suite);
        await action(t, const Key('profile-change-account-avatar'), 'keyboard');
        await action(t, const Key('community-crop-apply'), 'keyboard');
        wire.holding = 'account.updateAvatar';
        await action(
          t,
          const Key('account-avatar-confirm-save'),
          'keyboard',
          settle: false,
        );
        expect(wire.held, isNotNull);
        wire.switchAccount();
        await settleCommunityImages(t);
        wire.release();
        await settleCommunityImages(t);
        expect(find.text('账号头像已更换。'), findsNothing);
        expect(
          wire.requests.where((r) => r.name == 'account.updateAvatar'),
          hasLength(1),
        );
        expect(
          wire.requests.where((r) => r.name == 'account.clearAvatarDraft'),
          isEmpty,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final account in [true, false]) {
      testWidgets(
        'image entry synchronous double activation is one native pick $suite account=$account',
        (t) async {
          final wire = Connection(), s = session(wire);
          addTearDown(s.close);
          final port = Images()..picking = Completer<CommunityLogoSource?>();
          if (account) wire.holding = 'account.pickAvatar';
          await mount(
            t,
            account ? avatar(AccountAvatarPort(s)) : local(port, () {}),
            suite,
          );
          final control = find.byWidgetPredicate(
            (w) =>
                w is StarBridgeActionButton &&
                w.controlKey ==
                    Key(
                      account
                          ? 'profile-change-account-avatar'
                          : 'hangar-image-choose',
                    ),
          );
          final callback = t
              .widget<StarBridgeActionButton>(control)
              .onActivate!;
          callback(InteractionSource.keyboard);
          callback(InteractionSource.keyboard);
          await t.pump();
          if (account) {
            expect(
              wire.requests.where((r) => r.name == 'account.pickAvatar'),
              hasLength(1),
            );
            wire.pickCancel = true;
            wire.release();
          } else {
            expect(port.count('pick'), 1);
            port.picking!.complete(null);
          }
          await settleCommunityImages(t);
          expect(find.byType(CommunityLogoCrop), findsNothing);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets('readonly image entry has no styled write affordance $suite', (
      t,
    ) async {
      final wire = Connection();
      final s = session(wire);
      addTearDown(s.close);
      await mount(t, avatar(AccountAvatarPort(s), editable: false), suite);
      expect(
        find.byKey(const Key('profile-change-account-avatar')),
        findsNothing,
      );
      expect(wire.requests, isEmpty);
      final port = Images()..currentImage = FormPort.image;
      await mount(t, local(port, () {}, editable: false), suite);
      expect(find.byKey(const Key('hangar-image-choose')), findsNothing);
      expect(find.byKey(const Key('hangar-image-restore')), findsNothing);
      expect(port.calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('local confirmation review separate persistence copy $suite', (
      t,
    ) async {
      final port = Images();
      final capture = GlobalKey();
      await mount(t, local(port, () {}), suite, capture: capture);
      await action(t, const Key('hangar-image-choose'), 'pointer');
      await action(t, const Key('community-crop-apply'), 'pointer');
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final textRects = [
        t.getRect(find.text('保存舰船图片')),
        t.getRect(find.text('仅保存在这台电脑，不会上传或对外分享。')),
        t.getRect(find.text('取消')),
      ];
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ImageByteFormat.png);
        final rgba = (await image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        for (final rect in textRects) {
          var foreground = 0;
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final i = (y * image.width + x) * 4;
              if (rgba[i] >= 120 &&
                  rgba[i + 1] >= 140 &&
                  rgba[i + 2] >= 145 &&
                  rgba[i + 3] > 240) {
                foreground++;
              }
            }
          }
          expect(
            foreground,
            greaterThan(10),
            reason:
                'Confirmation copy actually paints, not only layout/semantics.',
          );
        }
        Directory('build/reviews/interaction-batch3ah')
            .createSync(recursive: true);
        File(
          'build/reviews/interaction-batch3ah/${suite.name}-local-confirm.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(port.count('save'), 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
