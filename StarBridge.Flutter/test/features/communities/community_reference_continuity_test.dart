import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_header.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'community_workspace_test.dart';
import 'community_workspace_view_test.dart' show host;
import 'community_image_test_support.dart';

void main() {
  testWidgets(
    'background organization refresh does not display a progress bar',
    (tester) async {
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      await tester.pumpWidget(
        host(port, const Locale('en'), organizationKey: 'org'),
      );
      await tester.pumpAndSettle();
      final state = tester.state<CommunityWorkspaceViewState>(
        find.byType(CommunityWorkspaceView),
      );
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => pending.future;
      final refresh = state.refreshVisibleCommunity();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(state.model.workspace, isNotNull);
      pending.complete(CommunityWorkspace.parse(workspacePayload()));
      await refresh;
      final manual = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => manual.future;
      final manualRead = state.model.load();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      manual.complete(CommunityWorkspace.parse(workspacePayload()));
      await manualRead;
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'reference renewal preserves the active member search and page',
    () async {
      final port = WorkspaceTestPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final calls = <(String, String, int)>[];
      port.reader = (target, query, offset) async {
        calls.add((target, query, offset));
        return CommunityWorkspace.parse(
          workspacePayload(target: target, query: query)
            ..['offset'] = offset
            ..['totalCount'] = 21
            ..['matchedCount'] = 21,
        );
      };
      await model.load(search: 'example', offset: 20);
      await model.renewReference('c' * 32);
      expect(calls.last, ('c' * 32, 'example', 20));
      expect(model.query, 'example');
      expect(model.workspace!.offset, 20);
    },
  );

  testWidgets(
    'manual reference refresh issues only one replacement metadata read',
    (tester) async {
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      var target = 'a' * 32, reads = 0;
      port.reader = (target, _, _) async {
        reads++;
        return CommunityWorkspace.parse(workspacePayload(target: target));
      };
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => host(
            port,
            const Locale('en'),
            target: target,
            organizationKey: 'org',
            onGovernanceChanged: () async => setState(() => target = 'c' * 32),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<CommunityWorkspaceHeader>(
            find.byType(CommunityWorkspaceHeader),
          )
          .onRefresh();
      await tester.pumpAndSettle();
      expect(
        reads,
        2,
        reason: 'One initial read and one renewed read, not a second read after rebinding.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('pending old avatar is discarded rather than shared with a renewed reference', () async {
    final port = WorkspaceTestPort();
    final model = CommunityWorkspaceController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    port.reader = (target, _, _) async {
      final payload = workspacePayload(target: target);
      final member = (payload['members'] as List).single as Map;
      member['hasAvatar'] = true;
      member['avatarVersion'] = 'a' * 64;
      return CommunityWorkspace.parse(payload);
    };
    final pending = Completer<Map<String, Object?>>();
    final oldBytes = base64Decode('AQID'), newBytes = base64Decode('BAUG');
    var reads = 0;
    port.mediaReader = (offset, _) {
      reads++;
      return reads == 1
          ? pending.future
          : Future.value(
              mediaChunk(newBytes, offset, kind: 'avatar', memberRef: 'b' * 32),
            );
    };
    final initial = model.load();
    await Future<void>.delayed(Duration.zero);
    await model.renewReference('c' * 32);
    expect(reads, 2);
    expect(model.image('b' * 32), newBytes);
    pending.complete(
      mediaChunk(oldBytes, 0, kind: 'avatar', memberRef: 'b' * 32),
    );
    await initial;
    expect(model.image('b' * 32), newBytes);
    expect(model.error, isNull);
  });

  testWidgets(
    'same organization reference refresh retains the visible roster and matching avatar',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=',
      );
      CommunityWorkspace page(String target) {
        final payload = workspacePayload(target: target);
        final member = (payload['members'] as List).single as Map;
        member['hasAvatar'] = true;
        member['avatarVersion'] = 'e' * 64;
        return CommunityWorkspace.parse(payload);
      }

      var reads = 0;
      port.reader = (target, _, _) async => page(target);
      port.mediaReader = (offset, _) async {
        reads++;
        return mediaChunk(bytes, offset, kind: 'avatar', memberRef: 'b' * 32);
      };
      await tester.pumpWidget(
        host(port, const Locale('en'), organizationKey: 'org'),
      );
      await settleCommunityImages(tester);
      final state = tester.state<CommunityWorkspaceViewState>(
        find.byType(CommunityWorkspaceView),
      );
      final image = state.model.image('b' * 32);
      expect(image, isNotNull);
      expect(reads, 1);
      final metadata = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => metadata.future;
      await tester.pumpWidget(
        host(
          port,
          const Locale('en'),
          target: 'c' * 32,
          organizationKey: 'org',
        ),
      );
      expect(
        state.model.workspace,
        isNotNull,
        reason: 'A reference refresh must not blank an already authorized organization view.',
      );
      expect(state.model.targetRef, 'a' * 32);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('community-reference-guard')),
            )
            .absorbing,
        isTrue,
      );
      metadata.complete(page('c' * 32));
      await settleCommunityImages(tester);
      expect(state.model.image('b' * 32), same(image));
      expect(state.model.targetRef, 'c' * 32);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('community-reference-guard')),
            )
            .absorbing,
        isFalse,
      );
      expect(
        reads,
        1,
        reason:
            'An unchanged, confirmed member avatar should not download again.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final change in ['organization', 'port', 'unknown identity']) {
    testWidgets('$change changes clear the previous view during loading', (
      tester,
    ) async {
      final first = WorkspaceTestPort();
      final second = WorkspaceTestPort();
      addTearDown(first.changes.close);
      addTearDown(second.changes.close);
      await tester.pumpWidget(
        host(
          first,
          const Locale('en'),
          organizationKey: change == 'unknown identity' ? null : 'org',
        ),
      );
      await tester.pumpAndSettle();
      final pending = Completer<CommunityWorkspace>();
      final next = change == 'port' ? second : first;
      next.reader = (_, _, _) => pending.future;
      await tester.pumpWidget(
        host(
          next,
          const Locale('en'),
          target: 'c' * 32,
          organizationKey: change == 'unknown identity'
              ? null
              : change == 'organization'
              ? 'other'
              : 'org',
        ),
      );
      final state = tester.state<CommunityWorkspaceViewState>(
        find.byType(CommunityWorkspaceView),
      );
      expect(state.model.workspace, isNull);
      pending.complete(
        CommunityWorkspace.parse(workspacePayload(target: 'c' * 32)),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final error in ['unavailable', 'notAllowed', 'identityUnavailable']) {
    test('reference validation failure $error clears retained data', () async {
      final port = WorkspaceTestPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      port.reader = (_, _, _) async => throw CommunityFailure(error);
      await model.renewReference('c' * 32);
      expect(model.workspace, isNull);
      expect(model.error, error);
      expect(model.busy, isFalse);
      if (error == 'unavailable') {
        port.reader = (target, _, _) async =>
            CommunityWorkspace.parse(workspacePayload(target: target));
        await model.load();
        expect(model.targetRef, 'c' * 32);
        expect(model.renewingReference, isFalse);
      }
    });
  }

  test(
    'account invalidation and late old responses cannot restore renewed data',
    () async {
      final port = WorkspaceTestPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      final old = Completer<CommunityWorkspace>();
      final next = Completer<CommunityWorkspace>();
      port.reader = (target, _, _) =>
          target == 'a' * 32 ? old.future : next.future;
      final oldRead = model.load();
      final nextRead = model.renewReference('c' * 32);
      old.complete(
        CommunityWorkspace.parse(
          workspacePayload()..['name'] = 'Late old result',
        ),
      );
      await oldRead;
      expect(model.workspace!.name, 'Organization A');
      port.changes.add(null);
      next.complete(
        CommunityWorkspace.parse(workspacePayload(target: 'c' * 32)),
      );
      await nextRead;
      expect(model.workspace, isNull);
      expect(model.error, 'identityUnavailable');
    },
  );

  test(
    'changed, removed and unversioned avatars are not carried across renewal',
    () async {
      final port = WorkspaceTestPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final bytes = base64Decode('AQID');
      String? version = 'a' * 64;
      var hasAvatar = true, reads = 0;
      port.reader = (target, _, _) async {
        final payload = workspacePayload(target: target);
        final member = (payload['members'] as List).single as Map;
        member['hasAvatar'] = hasAvatar;
        member['avatarVersion'] = version;
        return CommunityWorkspace.parse(payload);
      };
      port.mediaReader = (offset, _) async {
        reads++;
        return mediaChunk(bytes, offset, kind: 'avatar', memberRef: 'b' * 32);
      };
      await model.load();
      version = 'b' * 64;
      await model.renewReference('c' * 32);
      expect(reads, 2);
      version = null;
      await model.renewReference('d' * 32);
      await model.renewReference('e' * 32);
      expect(reads, 4);
      hasAvatar = false;
      await model.renewReference('f' * 32);
      expect(model.image('b' * 32), isNull);
      expect(reads, 4);
    },
  );
}
