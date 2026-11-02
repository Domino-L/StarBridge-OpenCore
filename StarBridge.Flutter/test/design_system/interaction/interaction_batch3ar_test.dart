import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_avatar.dart';

import '../../features/communities/community_visitor_profile_test.dart'
    show VisitorPort, visitorPayload;
import '../../features/communities/community_chat_media_cache_test.dart'
    show MediaPort, message;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3ac_test.dart' show Live;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3am_test.dart' show action;

const target = UserTarget.community(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);
const other = UserTarget.community(
  'cccccccccccccccccccccccccccccccc',
  'dddddddddddddddddddddddddddddddd',
);

class Profile extends VisitorPort {
  Profile(this.name);
  String name;
  final targets = <(UserTarget, InteractionSource)>[];
  Completer<PersonalProfileSnapshot>? held;
  int commands = 0;
  @override
  Future<FriendCommandResult> execute(String action, String reference) async {
    commands++;
    return const FriendCommandResult('rejected');
  }

  PersonalProfileSnapshot snapshot() => parsePersonalProfileSnapshot({
    ...visitorPayload,
    'profile': {
      ...visitorPayload['profile']! as Map,
      'identity': {'callSign': name, 'gameHandle': 'Synthetic_Handle'},
    },
  });
  @override
  Future<PersonalProfileSnapshot> profile(UserTarget value) async {
    targets.add((value, currentStarBridgeActivationSource));
    return held?.future ?? snapshot();
  }
}

class Media extends MediaPort {
  final origins = <(String, String, InteractionSource)>[];
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) {
    origins.add((targetRef, messageRef, currentStarBridgeActivationSource));
    return super.readChatDetail(targetRef, messageRef, offset, version);
  }
}

class AvatarProfile extends Profile {
  AvatarProfile(super.name);
  Completer<FriendRow?>? avatarPending;
  final avatarTargets = <UserTarget>[];
  @override
  Future<FriendRow?> social(UserTarget target) async {
    avatarTargets.add(target);
    return avatarPending?.future;
  }
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      final directory = Directory('build/reviews/interaction-batch3ar');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });

InteractionSource origin(String value) =>
    value == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'visitor toolbar refresh and guarded back retain original ownership $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              p = Profile('Authorized visitor');
          addTearDown(p.changes.close);
          final guard = UserPageLeaveGuard();
          bool allow = false;
          int guards = 0;
          InteractionSource? from;
          guard.confirm = () async {
            guards++;
            from = currentStarBridgeActivationSource;
            return allow;
          };
          final nav = GlobalKey<NavigatorState>();
          await mount(
            t,
            Navigator(
              key: nav,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Text('Source retained'),
              ),
            ),
            suite,
          );
          unawaited(
            nav.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => UserPageLeaveScope(
                  guard: guard,
                  child: UserProfilePage(port: p, target: target),
                ),
              ),
            ),
          );
          await settleCommunityImages(t);
          await action(t, const Key('visitor-profile-refresh'), source);
          expect(p.targets.last.$1.payload, target.payload);
          expect(p.targets.last.$2, origin(source));
          expect(p.commands, 0);
          await action(t, const Key('visitor-profile-back'), source);
          expect(guards, 1);
          expect(from, origin(source));
          expect(find.text('Authorized visitor'), findsWidgets);
          allow = true;
          await action(t, const Key('visitor-profile-back'), source);
          expect(guards, 2);
          expect(from, origin(source));
          expect(find.byType(UserProfilePage), findsNothing);
          expect(find.text('Source retained'), findsOneWidget);
          expect(p.commands, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
      for (final cached in [false, true]) {
        testWidgets(
          'media retry exact source and no extra read after recovery $suite $source cache=$cached',
          (t) async {
            final semantics = t.ensureSemantics(),
                p = Media()..fail = true,
                item = message(1, attachment: true, hasAvatar: false);
            final cache = cached
                ? CommunityChatMediaCache(p, target.contextRef!)
                : null;
            addTearDown(p.changes.close);
            if (cache != null) addTearDown(cache.dispose);
            await mount(
              t,
              SizedBox(
                width: 480,
                child: CommunityChatMessageTile(
                  port: p,
                  targetRef: target.contextRef!,
                  message: item,
                  mediaCache: cache,
                ),
              ),
              suite,
            );
            expect(p.calls, hasLength(1));
            p.fail = false;
            await action(
              t,
              ValueKey(('community-chat-media-retry', item.messageRef)),
              source,
            );
            expect(p.calls, hasLength(2));
            expect(p.origins.last, (
              target.contextRef!,
              item.messageRef,
              origin(source),
            ));
            expect(find.text(item.messageRef), findsOneWidget);
            expect(
              find.byKey(
                ValueKey(('community-chat-media-retry', item.messageRef)),
              ),
              findsNothing,
            );
            await t.pump(const Duration(seconds: 2));
            expect(p.calls, hasLength(2));
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          },
        );
      }
    }
    for (final cached in [false, true]) {
      testWidgets(
        'pending media retry cannot revive invalidated attachment $suite cache=$cached',
        (t) async {
          final p = Media()..fail = true,
              item = message(2, attachment: true, hasAvatar: false);
          final cache = cached
              ? CommunityChatMediaCache(p, target.contextRef!)
              : null;
          addTearDown(p.changes.close);
          if (cache != null) addTearDown(cache.dispose);
          await mount(
            t,
            SizedBox(
              width: 480,
              child: CommunityChatMessageTile(
                port: p,
                targetRef: target.contextRef!,
                message: item,
                mediaCache: cache,
              ),
            ),
            suite,
          );
          p.fail = false;
          p.gate = Completer<void>();
          await action(
            t,
            ValueKey(('community-chat-media-retry', item.messageRef)),
            'pointer',
            settle: false,
          );
          expect(p.calls, hasLength(2));
          expect(
            find.byKey(
              ValueKey(('community-chat-media-retry', item.messageRef)),
            ),
            findsNothing,
          );
          p.changes.add(null);
          await t.pump();
          p.gate!.complete();
          await settleCommunityImages(t);
          expect(find.text(item.messageRef), findsNothing);
          expect(p.calls, hasLength(2));
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'functional image loading follows live suite reduce without changing geometry $suite',
      (t) async {
        final image = SizedBox.square(
          dimension: 96,
          child: CommunityWorkspaceImage(
            bytes: null,
            icon: StandardIconSemantic.person,
            loading: true,
          ),
        );
        size(t, const Size(1280, 1000));
        final key = GlobalKey();
        final scene = ValueNotifier((reduce: false, light: false));
        addTearDown(scene.dispose);
        // The suite configuration carries user reduction; no synthetic system MediaQuery change.
        await t.pumpWidget(
          Live(
            ValueListenableBuilder(
              valueListenable: scene,
              builder: (context, value, _) => InteractionScope(
                data: InteractionData(
                  suite: suite,
                  reduceMotion: value.reduce,
                  palette: resolveStarBridgeInteraction(context).palette,
                ),
                child: RepaintBoundary(key: key, child: image),
              ),
            ),
            suite,
          ),
        );
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        final rect = t.getRect(find.byType(CommunityWorkspaceImage));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        scene.value = (reduce: true, light: true);
        await t.pump();
        await t.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is StandardIcon &&
                w.semantic == StandardIconSemantic.hourglassTop,
          ),
          findsOneWidget,
        );
        expect(t.getRect(find.byType(CommunityWorkspaceImage)), rect);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'guarded back interrupted by new profile owner does not pop new page $suite',
      (t) async {
        final p = Profile('Old visitor'),
            config = ValueNotifier(target),
            confirm = Completer<bool>();
        addTearDown(p.changes.close);
        addTearDown(config.dispose);
        final guard = UserPageLeaveGuard()..confirm = () => confirm.future,
            nav = GlobalKey<NavigatorState>();
        await mount(
          t,
          Navigator(
            key: nav,
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const Text('Source')),
          ),
          suite,
        );
        unawaited(
          nav.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => UserPageLeaveScope(
                guard: guard,
                child: ValueListenableBuilder(
                  valueListenable: config,
                  builder: (_, value, _) =>
                      UserProfilePage(port: p, target: value),
                ),
              ),
            ),
          ),
        );
        await settleCommunityImages(t);
        await action(
          t,
          const Key('visitor-profile-back'),
          'pointer',
          settle: false,
        );
        p.name = 'New visitor';
        config.value = other;
        await t.pump();
        confirm.complete(true);
        await settleCommunityImages(t);
        expect(find.byType(UserProfilePage), findsOneWidget);
        expect(find.text('New visitor'), findsWidgets);
        expect(p.commands, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('old optional avatar cannot fill a different visitor $suite', (
      t,
    ) async {
      final p = AvatarProfile('Old visitor')
            ..avatarPending = Completer<FriendRow?>(),
          config = ValueNotifier(target);
      final held = p.avatarPending!;
      addTearDown(p.changes.close);
      addTearDown(config.dispose);
      await mount(
        t,
        ValueListenableBuilder(
          valueListenable: config,
          builder: (_, value, _) => UserProfilePage(port: p, target: value),
        ),
        suite,
      );
      expect(p.avatarTargets.map((x) => x.reference), [target.reference]);
      p.avatarPending = null;
      p.name = 'New visitor';
      config.value = other;
      await settleCommunityImages(t);
      held.complete(
        FriendRow(
          'Old visitor',
          '',
          'friend',
          DateTime.utc(2026),
          avatar: 'retired-avatar-fixture',
        ),
      );
      await settleCommunityImages(t);
      expect(find.text('New visitor'), findsWidgets);
      expect(
        t
            .widgetList<PersonalProfileAvatar>(
              find.byType(PersonalProfileAvatar),
            )
            .every((x) => x.imageData != 'retired-avatar-fixture'),
        true,
      );
      expect(p.avatarTargets.map((x) => x.reference), [
        target.reference,
        other.reference,
      ]);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
    for (final change in ['target', 'context', 'port', 'source']) {
      testWidgets(
        'visitor scope rebind does not show old late profile $suite $change',
        (t) async {
          final old = Profile('Old private pilot')
                ..held = Completer<PersonalProfileSnapshot>(),
              fresh = Profile('New authorized pilot');
          final config = ValueNotifier((port: old, target: target));
          final oldReply = old.held!, oldSnapshot = old.snapshot();
          addTearDown(config.dispose);
          addTearDown(old.changes.close);
          addTearDown(fresh.changes.close);
          size(t, const Size(1280, 1000));
          await t.pumpWidget(
            Live(
              ValueListenableBuilder(
                valueListenable: config,
                builder: (_, value, _) => UserProfilePage(
                  key: const ValueKey('same-visitor-state'),
                  port: value.port,
                  target: value.target,
                ),
              ),
              suite,
            ),
          );
          await t.pump();
          await t.pump();
          expect(old.targets, hasLength(1));
          final next = change == 'context'
              ? const UserTarget.community(
                  'cccccccccccccccccccccccccccccccc',
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                )
              : change == 'source'
              ? const UserTarget('friend', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
              : change == 'port'
              ? target
              : other;
          old.held = null;
          old.name = 'New authorized pilot';
          config.value = (port: change == 'port' ? fresh : old, target: next);
          await t.pump();
          await t.pump();
          expect(
            change == 'port' ? fresh.targets.length : old.targets.length,
            change == 'port' ? 1 : 2,
          );
          oldReply.complete(oldSnapshot);
          await settleCommunityImages(t);
          expect(find.text('New authorized pilot'), findsWidgets);
          expect(find.text('Old private pilot'), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'cosmetic query change cannot revive an invalidated visitor $suite',
      (t) async {
        final p = Profile('Private visitor'), config = ValueNotifier(target);
        addTearDown(p.changes.close);
        addTearDown(config.dispose);
        await mount(
          t,
          ValueListenableBuilder(
            valueListenable: config,
            builder: (_, value, _) => UserProfilePage(port: p, target: value),
          ),
          suite,
        );
        expect(p.targets, hasLength(1));
        p.changes.add(null);
        await settleCommunityImages(t);
        config.value = const UserTarget.community(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          query: 'Only display query changed',
        );
        await settleCommunityImages(t);
        await action(t, const Key('visitor-profile-refresh'), 'keyboard');
        expect(p.targets, hasLength(1));
        expect(find.text('Private visitor'), findsNothing);
        expect(p.commands, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('render visitor and recovered media $suite', (t) async {
      final p = Profile('Authorized visitor'), captureKey = GlobalKey();
      addTearDown(p.changes.close);
      await mount(
        t,
        UserProfilePage(port: p, target: target),
        suite,
        capture: captureKey,
      );
      await capture(t, captureKey, '${suite.name}-profile');
      final media = Media()..fail = true,
          item = message(1, attachment: true, hasAvatar: false),
          second = GlobalKey();
      addTearDown(media.changes.close);
      await mount(
        t,
        SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: CommunityChatMessageTile(
              port: media,
              targetRef: target.contextRef!,
              message: item,
            ),
          ),
        ),
        suite,
        capture: second,
      );
      await capture(t, second, '${suite.name}-media-failed');
      media.fail = false;
      await action(
        t,
        ValueKey(('community-chat-media-retry', item.messageRef)),
        'pointer',
      );
      await capture(t, second, '${suite.name}-media-ready');
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
  }
}
