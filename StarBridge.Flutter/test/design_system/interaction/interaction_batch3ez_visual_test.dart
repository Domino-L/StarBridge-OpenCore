import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_draft.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_wallpaper_catalog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/personal_profile/local_personal_profile_test.dart'
    show Harness, edit;
import '../../features/personal_profile/personal_profile_collaboration_test.dart'
    show schedule;
import 'interaction_batch3eq_test.dart' show validationApp;
import 'interaction_batch3ez_editor_test.dart' show activateEditor, background;

void main() {
  testWidgets(
    'complete profile editor scaled forms and background picker retain current geometry',
    (t) async {
      const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      final h = Harness();
      try {
        await loadFonts();
        await (FontLoader('Source Code Pro')..addFont(
              rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf'),
            ))
            .load();
        final projection = PersonalProfileProjection.fromSnapshot(
          await h.port.read(),
        );
        final draft = PersonalProfileEditorDraft(
          edit(await h.port.read(), schedule: schedule),
        );
        for (final suite in [
          InteractionSuite.rail,
          InteractionSuite.scan,
          InteractionSuite.glow,
        ]) {
          for (final light in [false, true]) {
            for (final locale in [
              const Locale('zh', 'CN'),
              const Locale('zh', 'TW'),
              const Locale('en'),
            ]) {
              for (final width in [1100.0, 540.0]) {
                size(t, Size(width, 1100));
                final frame = GlobalKey();
                await t.pumpWidget(
                  RepaintBoundary(
                    key: frame,
                    child: validationApp(
                      SingleChildScrollView(
                        child: PersonalProfileEditorPanel(
                          projection: projection,
                          initialDraft: draft,
                          moduleLayout: projection.moduleLayout,
                          onCancel: () {},
                          onSaved: () {},
                          onWallpaperChanged: (_) {},
                          onSave: (_) async =>
                              const PersonalProfileActionResult(
                                PersonalProfileActionOutcome.failed,
                              ),
                        ),
                      ),
                      suite,
                      light: light,
                      locale: locale,
                      scale: 1.5,
                    ),
                  ),
                );
                await t.pumpAndSettle();
                for (final id in [
                  'profile-roles-editor',
                  'profile-interests-editor',
                  'profile-support-editor',
                  'profile-schedule-editor',
                ]) {
                  final target = find
                      .descendant(
                        of: find.byKey(Key(id)),
                        matching: find.byType(SuitePressable),
                      )
                      .first;
                  await t.ensureVisible(target);
                  await t.pumpAndSettle();
                  await t.tap(target);
                  await t.pumpAndSettle();
                  expect(t.takeException(), isNull);
                }
                await t.ensureVisible(
                  find.byKey(const Key('profile-window-0-end-minute')),
                );
                await t.pumpAndSettle();
                expect(
                  t
                      .getRect(find.byKey(const Key('profile-window-0-end-minute')))
                      .right,
                  lessThanOrEqualTo(width),
                );
                await activateEditor(t, background(), 'pointer');
                await t.pumpAndSettle();
                expect(
                  find.byKey(const Key('profile-background-picker-grid')),
                  findsOneWidget,
                );
                expect(t.takeException(), isNull);
                if (output.isNotEmpty &&
                    locale.countryCode == 'CN' &&
                    width == 1100) {
                  await t.runAsync(
                    () => Future.wait([
                      for (final preset
                          in PersonalProfileWallpaperCatalog.presets.take(20))
                        if (preset.assetPath != null)
                          precacheImage(
                            ResizeImage(
                              AssetImage(preset.assetPath!),
                              width: 640,
                            ),
                            t.element(find.byType(Dialog)),
                          ),
                    ]),
                  );
                  await t.pumpAndSettle();
                  await t.runAsync(() async {
                    final image =
                        await (frame.currentContext!.findRenderObject()!
                                as RenderRepaintBoundary)
                            .toImage();
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    await Directory(output).create(recursive: true);
                    await File(
                      '$output/${suite.name}-${light ? 'light' : 'dark'}-background.png',
                    ).writeAsBytes(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
                await t.sendKeyEvent(LogicalKeyboardKey.escape);
                await t.pumpAndSettle();
                await t.pumpWidget(const SizedBox());
              }
            }
          }
        }
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.runAsync(h.close);
        debugDisableShadows = oldShadows;
      }
    },
  );
}
