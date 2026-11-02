// User report 2026-10-29 ("都有，不动就转"): avatars in an idle holo chat kept
// showing their loading state. Renewed access references and background
// refreshes must leave the shown portraits and their widgets in place.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/common/organization_holo.dart';
import 'package:starbridge_flutter/features/communities/community_activity_time.dart';
import 'package:starbridge_flutter/features/communities/community_avatar_cache.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_online_members_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';

import 'community_chat_media_cache_test.dart' show MediaPort;
import 'community_image_test_support.dart';
import 'community_workspace_test.dart';
import '../overlay_settings/overlay_acceptance_polish_test.dart' show polishApp;

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=';

Finder get _waitingAvatars => find.byWidgetPredicate(
  (w) => w is CommunityWorkspaceImage && w.loading && w.bytes == null,
);

void main() {
  _renewalDuringRead();
  _viewerClock();
  testWidgets(
    'a renewed reference on the same controller keeps every tile and its '
    'portrait, without a waiting frame',
    (tester) async {
      final port = MediaPort();
      final avatars = CommunityAvatarCache();
      final controller = CommunityChatController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(avatars.dispose);
      addTearDown(port.changes.close);
      Widget panel(String ref) => polishApp(
        CommunityChatPanel(
          port: port,
          targetRef: ref,
          name: 'Fixture',
          onBack: () {},
          controller: controller,
          avatars: avatars,
        ),
      );
      await tester.pumpWidget(panel('a' * 32));
      await tester.pumpAndSettle();
      final tiles = tester
          .stateList<State>(find.byType(CommunityChatMessageTile))
          .toSet();
      expect(tiles, isNotEmpty);
      expect(_waitingAvatars, findsNothing);
      controller.renewVerifiedReference('b' * 32);
      await tester.pumpWidget(panel('b' * 32));
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          _waitingAvatars,
          findsNothing,
          reason: 'frame $frame shows an avatar waiting after renewal',
        );
        expect(
          find.byKey(const ValueKey('community-chat-avatar-wait')),
          findsNothing,
        );
      }
      await tester.pumpAndSettle();
      expect(
        tester.stateList<State>(find.byType(CommunityChatMessageTile)).toSet(),
        tiles,
        reason: 'the tiles were rebuilt from scratch',
      );
      expect(tester.takeException(), isNull);
    },
  );

  group('online members pane', () {
    late WorkspaceTestPort port;
    late int mediaReads;
    late CommunityAvatarCache avatars;

    setUp(() {
      port = WorkspaceTestPort();
      mediaReads = 0;
      avatars = CommunityAvatarCache();
      port.reader = (target, query, _) async {
        final payload = workspacePayload(target: target, query: query);
        final member = (payload['members'] as List).single as Map;
        member['hasAvatar'] = true;
        member['avatarVersion'] = sha256.convert(base64Decode(_png)).toString();
        member['online'] = true;
        member['publicOnline'] = true;
        return CommunityWorkspace.parse(payload);
      };
      port.mediaReader = (offset, _) async {
        mediaReads++;
        return mediaChunk(
          base64Decode(_png),
          offset,
          kind: 'avatar',
          memberRef: 'b' * 32,
        );
      };
    });

    tearDown(() {
      avatars.dispose();
      port.changes.close();
    });

    Widget pane(String ref) => polishApp(
      OrganizationHolo(
        child: SizedBox(
          width: 320,
          height: 600,
          child: CommunityOnlineMembersPane(
            port: port,
            targetRef: ref,
            avatars: avatars,
            onAllMembers: () {},
          ),
        ),
      ),
    );

    testWidgets('a renewed reference keeps the portraits', (tester) async {
      await tester.pumpWidget(pane('a' * 32));
      await settleCommunityImages(tester);
      await tester.pumpAndSettle();
      final images = tester
          .stateList<State>(find.byType(CommunityWorkspaceImage))
          .toSet();
      expect(images, isNotEmpty);
      final reads = mediaReads;
      await tester.pumpWidget(pane('b' * 32));
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_waitingAvatars, findsNothing);
      }
      await settleCommunityImages(tester);
      await tester.pumpAndSettle();
      expect(
        tester.stateList<State>(find.byType(CommunityWorkspaceImage)).toSet(),
        images,
      );
      expect(mediaReads, reads, reason: 'the portrait was read again');
      expect(tester.takeException(), isNull);
    });

    testWidgets('thirty idle seconds of background refreshes change nothing', (
      tester,
    ) async {
      await tester.pumpWidget(pane('a' * 32));
      await settleCommunityImages(tester);
      await tester.pumpAndSettle();
      final images = tester
          .stateList<State>(find.byType(CommunityWorkspaceImage))
          .toSet();
      final reads = mediaReads;
      for (var second = 0; second < 30; second++) {
        await tester.pump(const Duration(seconds: 1));
        expect(_waitingAvatars, findsNothing, reason: 'second $second');
      }
      await tester.pumpAndSettle();
      expect(
        tester.stateList<State>(find.byType(CommunityWorkspaceImage)).toSet(),
        images,
      );
      expect(mediaReads, reads);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the active hours keep their phrases whole and name the region', (
    tester,
  ) async {
    final workspace = CommunityWorkspace.parse(
      workspacePayload()
        ..['timeZoneId'] = 'America/Chicago'
        ..['timeZoneStandardOffsetMinutes'] = -360
        ..['activityWindows'] = [
          {
            'days': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
            'startTime': '19:00',
            'endTime': '22:30',
            'endsNextDay': false,
          },
          {
            'days': ['Sat', 'Sun'],
            'startTime': '08:00',
            'endTime': '22:00',
            'endsNextDay': false,
          },
        ],
    );
    late String zone, hours;
    await tester.pumpWidget(
      polishApp(
        Builder(
          builder: (context) {
            zone = communityTimeZoneSummary(context, workspace);
            hours = communityActivitySummary(
              context,
              workspace.activityWindows,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    expect(zone, startsWith('UTC−06:00'));
    expect(zone, contains('美国中部'));
    expect(hours, contains('; '));
    // Shown text: phrases keep their words together, joins stay breakable.
    final shown = communityReadoutPhrases('$hours · $zone');
    expect(shown, contains('; '));
    expect(shown, contains(' · '));
    for (final phrase in shown.split('; ').expand((p) => p.split(' · '))) {
      expect(phrase.contains(' '), isFalse, reason: 'breakable space: $phrase');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the contact copy action is quiet on the holo deck', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    port.reader = (target, query, _) async => CommunityWorkspace.parse(
      workspacePayload(target: target, query: query),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('zh', 'CN'),
        ),
        home: Scaffold(
          body: CommunityWorkspaceView(
            port: port,
            targetRef: 'a' * 32,
            organizationKey: 'org',
            holo: true,
            actions: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await settleCommunityImages(tester);
    await tester.pumpAndSettle();
    final copy = find.byKey(
      const ValueKey('community-copy-contact-Discord-organization-contact'),
    );
    expect(copy, findsOneWidget);
    final action = find.ancestor(
      of: copy,
      matching: find.byType(StarBridgeIconAction),
    );
    expect(tester.widget<StarBridgeIconAction>(action.first).quiet, isTrue);
    expect(tester.takeException(), isNull);
  });
}

// Review 2026-10-29 (CX-HOLOPOLISH-R): a renewal that lands while a round is
// still reading is not a wrong response; the round is dropped and re-read.
void _renewalDuringRead() {
  test(
    'online members controller re-reads after a renewal mid-round',
    () async {
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      final targets = <String>[];
      Completer<void>? gate;
      port.reader = (target, query, _) {
        targets.add(target);
        final page = CommunityWorkspace.parse(
          workspacePayload(target: target, query: query),
        );
        if (gate case final pending? when !pending.isCompleted) {
          return pending.future.then((_) => page);
        }
        return Future.value(page);
      };
      final model = CommunityOnlineMembersController(port, 'a' * 32);
      addTearDown(model.dispose);
      await model.refresh();
      expect(model.members, hasLength(1));
      gate = Completer<void>();
      final round = model.refresh(silent: true);
      model.renewTarget('b' * 32);
      gate.complete();
      await round;
      await Future<void>.delayed(Duration.zero);
      expect(model.error, isNull);
      expect(
        model.members,
        hasLength(1),
        reason: 'the old round cleared the list',
      );
      expect(targets.last, 'b' * 32, reason: 'no re-read on the new reference');
    },
  );
}

// User 2026-10-29: "可以加" — the viewer's own clock beside the active hours.
void _viewerClock() {
  testWidgets(
    'the viewer clock shifts the windows and marks a crossed midnight',
    (tester) async {
      final workspace = CommunityWorkspace.parse(
        workspacePayload()
          ..['timeZoneStandardOffsetMinutes'] = -360
          ..['activityWindows'] = [
            {
              'days': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
              'startTime': '19:00',
              'endTime': '22:30',
              'endsNextDay': false,
            },
            {
              'days': ['Sat', 'Sun'],
              'startTime': '08:00',
              'endTime': '22:00',
              'endsNextDay': false,
            },
          ],
      );
      late String shifted, same;
      await tester.pumpWidget(
        polishApp(
          Builder(
            builder: (context) {
              shifted = communityViewerActivitySummary(
                context,
                workspace.activityWindows,
                workspace.timeZoneStandardOffsetMinutes,
                viewerOffsetMinutes: 480,
              );
              same = communityViewerActivitySummary(
                context,
                workspace.activityWindows,
                workspace.timeZoneStandardOffsetMinutes,
                viewerOffsetMinutes: -360,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      // UTC−06:00 19:00–22:30 is UTC+08:00 09:00–12:30; 08:00–22:00 crosses
      // midnight into 22:00–12:00 of the next day.
      expect(shifted, contains('09:00–12:30'));
      expect(shifted, contains('22:00–次日 12:00'));
      expect(same, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
