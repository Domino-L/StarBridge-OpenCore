import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_live_appearance_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import '../friends/social_layout_test.dart' show app, size;

final class PreviewPort implements OverlayAppearancePreviewPort {
  final opened = <(String, OverlayAppearanceOptions)>[];
  final closed = <String>[];
  Completer<String>? pending;
  bool failOpen = false, failClose = false;
  bool? reduced;
  @override
  Future<String> openAppearancePreview(
    String id,
    OverlayAppearanceOptions options, {
    bool reduceMotion = false,
  }) async {
    opened.add((id, options));
    reduced = reduceMotion;
    if (failOpen) throw StateError('open failed');
    return pending?.future ?? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  }

  @override
  Future<void> closeAppearancePreview(String id) async {
    if (failClose) throw StateError('close failed');
    closed.add(id);
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    PreviewPort port, {
    bool reduced = false,
  }) async {
    size(tester, const Size(800, 600));
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showOverlayLiveAppearancePreview(
              context,
              appearanceId: 'Fixture',
              options: const OverlayAppearanceOptions.empty(),
              reduceMotion: reduced,
              port: port,
            ),
            child: const Text('Preview'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'preview opens immutable draft with no pet interaction and closes its own session',
    (tester) async {
      final port = PreviewPort();
      await show(tester, port);
      expect(port.opened.single.$1, 'Fixture');
      expect(port.opened.single.$2, const OverlayAppearanceOptions.empty());
      expect(find.textContaining('猫会自行活动'), findsOneWidget);
      expect(find.textContaining('不会保存'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
      await tester.tap(find.byKey(const Key('overlay-live-preview-close')));
      await tester.pumpAndSettle();
      expect(port.closed, ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion is sent to the native preview without starting another session',
    (tester) async {
      final port = PreviewPort();
      await show(tester, port, reduced: true);
      expect(port.reduced, isTrue);
      expect(port.opened.length, 1);
      await tester.tap(find.byKey(const Key('overlay-live-preview-close')));
      await tester.pumpAndSettle();
      expect(port.closed.length, 1);
    },
  );

  testWidgets(
    'dismissal before late open response cleans the returned session',
    (tester) async {
      final port = PreviewPort()..pending = Completer<String>();
      await show(tester, port);
      expect(find.textContaining('正在打开'), findsOneWidget);
      await tester.tap(find.byKey(const Key('overlay-live-preview-close')));
      await tester.pumpAndSettle();
      port.pending!.complete('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      await tester.pumpAndSettle();
      expect(port.closed, ['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'barrier dismissal and widget disposal release a completed session',
    (tester) async {
      for (final removeTree in [false, true]) {
        final port = PreviewPort();
        await show(tester, port);
        if (removeTree) {
          await tester.pumpWidget(const SizedBox());
        } else {
          await tester.tapAt(const Offset(4, 4));
        }
        await tester.pumpAndSettle();
        expect(port.closed, ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa']);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'failed open is not silently replayed, failed close can be retried',
    (tester) async {
      final failed = PreviewPort()..failOpen = true;
      await show(tester, failed);
      expect(find.textContaining('预览未能打开'), findsOneWidget);
      expect(failed.opened.length, 1);
      await tester.tap(find.byKey(const Key('overlay-live-preview-close')));
      await tester.pumpAndSettle();
      final port = PreviewPort()..failClose = true;
      await show(tester, port);
      await tester.tap(find.byKey(const Key('overlay-live-preview-close')));
      await tester.pumpAndSettle();
      expect(find.textContaining('预览未能关闭'), findsOneWidget);
      expect(port.closed, isEmpty);
      port.failClose = false;
      await tester.tap(find.text('重试关闭'));
      await tester.pumpAndSettle();
      expect(port.closed.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
