import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';

import 'community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload, mediaChunk;
import '../friends/social_layout_test.dart' show loadFonts, app;

void main() {
  setUpAll(loadFonts);
  test(
    'queued images are loading before bytes arrive and clear on invalidation',
    () async {
      final port = WorkspaceTestPort();
      port.reader = (ref, _, _) async => CommunityWorkspace.parse(
        workspacePayload(target: ref)
          ..['hasLogo'] = true
          ..['hasBanner'] = true,
      );
      final pending = Completer<Map<String, Object?>>();
      port.mediaReader = (_, _) => pending.future;
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(() async {
        model.dispose();
        await port.changes.close();
      });
      final loading = model.load();
      await Future<void>.delayed(Duration.zero);
      expect(model.workspace, isNotNull);
      expect(model.busy, isFalse);
      expect(model.imageLoading('logo'), isTrue);
      expect(model.imageLoading('banner'), isTrue);
      expect(model.imageLoading('absent'), isFalse);
      port.changes.add(null);
      expect(model.imageLoading('logo'), isFalse);
      expect(model.imageLoading('banner'), isFalse);
      pending.complete(mediaChunk(Uint8List.fromList([1, 2, 3]), 0));
      await loading;
      expect(model.workspace, isNull);
      expect(model.image('logo'), isNull);
    },
  );

  testWidgets(
    'loading animates without changing image bounds and stops on failure',
    (tester) async {
      Widget scene({
        bool loading = true,
        bool failed = false,
        bool reduced = false,
      }) => app(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: RepaintBoundary(
              key: const ValueKey('image-loading-capture'),
              child: SizedBox.square(
                dimension: 96,
                child: CommunityWorkspaceImage(
                  bytes: null,
                  icon: StandardIconSemantic.groups,
                  loading: loading,
                  loadFailed: failed,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final rect = tester.getRect(find.byType(CommunityWorkspaceImage));
      Future<Uint8List> capture(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('image-loading-capture')),
        );
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final bytes = data!.buffer.asUint8List();
          await File('build/$name.png').writeAsBytes(bytes);
          image.dispose();
          return bytes;
        }))!;
      }

      final first = await capture('community-image-loading-frame-1');
      await tester.pump(const Duration(milliseconds: 320));
      final second = await capture('community-image-loading-frame-2');
      expect(listEquals(first, second), isFalse);
      expect(tester.getRect(find.byType(CommunityWorkspaceImage)), rect);
      await tester.pumpWidget(scene(loading: false, failed: true));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      await tester.pumpWidget(scene(reduced: true));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(find.byTooltip('正在加载图片…'), findsOneWidget);
      await tester.pumpWidget(scene(loading: false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
      expect(find.byType(CommunityImageLoading), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
