import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;
import 'interaction_batch3dr_test.dart';

Future<List<int>> editorPixels(WidgetTester t) => t
    .runAsync(() async {
      final render = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('3dr-frame')),
      );
      final image = await render.toImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List()
            .toList();
      } finally {
        image.dispose();
      }
    })
    .then((bytes) => bytes!);
Future<void> editorFrame(WidgetTester t, String name) async {
  final bytes = await editorPixels(t);
  await t.runAsync(() async {
    final file = File('build/reviews/interaction-batch3dr/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  });
}

void visibleEditor(WidgetTester t, Finder target) {
  final r = t.getRect(target);
  expect(r.left, greaterThanOrEqualTo(0));
  expect(r.right, lessThanOrEqualTo(430));
  expect(r.top, greaterThanOrEqualTo(0));
  expect(r.bottom, lessThanOrEqualTo(850));
}

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final combined in [false, true]) {
          final config =
              '${suite.name}-${light ? 'light' : 'dark'}-$scale-${combined ? 'combined' : 'local'}';
          testWidgets(
            '$config save footer geometry and pinned pending remain visible',
            (t) async {
              fixture.size(t, const Size(430, 850));
              final p = EditorPort();
              final c = LocalPrivacyController(p);
              final sync = createSyncPrivacyModule(
                InMemorySyncPrivacyAdapter.forReview(),
              );
              await sync.initialize();
              final page = combined
                  ? PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync)
                  : LocalPrivacyPage(controller: c);
              Widget app({bool reduce = false}) => editorApp(
                page,
                suite,
                light: light,
                scale: scale,
                reduce: reduce,
              );
              final pending = Completer<LocalPrivacySnapshot>();
              try {
                await t.pumpWidget(app());
                await editorFrames(t);
                for (final key in ['privacy-save', 'privacy-discard']) {
                  visibleEditor(t, find.byKey(Key(key)));
                }
                await editorFrame(t, '$config-idle');
                c.edit(c.draft!.copyWith(roomFields: 0));
                p.pendingSave = pending;
                await t.pump();
                final scroll = find
                    .descendant(
                      of: find.byType(LocalPrivacyPage),
                      matching: find.byType(SingleChildScrollView),
                    )
                    .first;
                await t.drag(scroll, const Offset(0, -2000));
                await editorFrames(t);
                // Footer is not moved into view by the test; click where it lives.
                await t.tap(find.byKey(const Key('privacy-save')));
                await t.pump();
                await t.pump(const Duration(milliseconds: 100));
                expect(c.saving, isTrue);
                visibleEditor(t, find.byType(HelpSupportWaiting));
                for (final key in ['privacy-save', 'privacy-discard']) {
                  visibleEditor(t, find.byKey(Key(key)));
                }
                await editorFrame(t, '$config-pending');
                await t.pumpWidget(app(reduce: true));
                await editorFrames(t, 3);
                expect(find.byType(SuiteProgressBar), findsNothing);
                final before = await editorPixels(t);
                await t.pump(const Duration(milliseconds: 300));
                expect(await editorPixels(t), before);
                pending.completeError(
                  const BridgeClientException('privacy_local.write_failed'),
                );
                await editorFrames(t);
                expect(c.dirty, isTrue);
                expect(c.errorKey, 'privacy.local.saveFailed');
                expect(p.writes, 1);
                await editorFrame(t, '$config-failed');
                expect(t.takeException(), isNull);
              } finally {
                if (!pending.isCompleted) {
                  pending.complete(const LocalPrivacySnapshot(revision: 5));
                }
                await t.pumpWidget(const SizedBox.shrink());
                await editorFrames(t, 2);
                c.dispose();
                sync.dispose();
              }
            },
            timeout: const Timeout(Duration(seconds: 45)),
            skip: !Platform.isWindows,
          );
        }
      }
    }
  }
}
