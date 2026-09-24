import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';

import 'community_shared_media_test.dart' show SharedMediaPort;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'pending member avatar keeps its spinner during metadata refresh',
    (tester) async {
      final port = SharedMediaPort()
        ..heldMember = 'd' * 32
        ..mediaGate = Completer<void>();
      addTearDown(port.changes.close);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final avatarLoading = find.descendant(
        of: find.byType(UserAvatarMenu),
        matching: find.byType(CommunityImageLoading),
      );
      expect(avatarLoading, findsOneWidget);
      final avatar = find.descendant(
        of: find.byType(UserAvatarMenu),
        matching: find.byType(CommunityWorkspaceImage),
      );
      final avatarState = tester.state(avatar);
      final readsBeforeRefresh = port.avatarReads;
      final read = port.reader!;
      final metadata = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => metadata.future;
      try {
        await tester.tap(find.text('搜索'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('community-refresh-progress')),
          findsOneWidget,
        );
        expect(
          tester.state(avatar),
          same(avatarState),
          reason: 'The image widget was not remounted by metadata refresh.',
        );
        expect(
          port.avatarReads,
          readsBeforeRefresh,
          reason: 'The same unfinished request remains in the shared cache.',
        );
        final image = tester.widget<CommunityWorkspaceImage>(avatar);
        expect(image.bytes, isNull);
        expect(image.loadFailed, isFalse);
        expect(image.loading, isTrue);
        expect(
          avatarLoading,
          findsOneWidget,
          reason:
              'Refreshing member metadata must not turn an in-flight '
              'avatar into the no-avatar placeholder.',
        );
      } finally {
        metadata.complete(await read('a' * 32, '', 0));
        port.mediaGate!.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    },
  );
}
