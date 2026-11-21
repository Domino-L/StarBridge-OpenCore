import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_draft.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_setting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3eq_test.dart'
    show validationApp;
import '../friends/social_layout_test.dart' show loadFonts, size;
import '../personal_profile/local_personal_profile_test.dart'
    show Harness, edit;
import 'game_id_visibility_test.dart' show Fixture;

/// 11-15 decision 甲 (one callsign): the settings card keeps the callsign above the
/// four location switches. Pass `--dart-define=CALLSIGN_PREVIEW_DIR=...` to write
/// review PNGs; without it this only checks the states render.
const _output = String.fromEnvironment('CALLSIGN_PREVIEW_DIR');

Map<String, Object?> _scm({String? callsign, String mirror = 'synced'}) => {
  'schemaVersion': 1,
  'revision': 3,
  'locations': 4,
  'canConfigure': true,
  'identityStamp': 'a' * 64,
  'callsign': callsign,
  'mirror': mirror,
};

Future<void> _capture(WidgetTester t, GlobalKey frame, String name) async {
  if (_output.isEmpty) return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_output).create(recursive: true);
    await File('$_output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
  // Finish decoration fades and drop focus so the image shows the resting state.
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadFonts);
  for (final (name, light, snapshot) in [
    ('1-card-dark', false, _scm(callsign: '飞鹰')),
    ('1-card-light', true, _scm(callsign: '飞鹰')),
    // Starts from the old name; the test saves 飞鹰 and Hong Kong lags behind.
    ('2-pending-dark', false, _scm(callsign: '老鹰')),
    ('2-restore-pending-dark', false, _scm(mirror: 'restorePending')),
    // Decision 乙: no callsign means everything shows; switches only turn on.
    (
      '3-need-callsign-dark',
      false,
      _scm()..addAll({'locations': 15, 'canConfigure': false}),
    ),
    (
      '3-need-callsign-light',
      true,
      _scm()..addAll({'locations': 15, 'canConfigure': false}),
    ),
    (
      '4-hidden-without-callsign-dark',
      false,
      _scm()..addAll({'locations': 2, 'canConfigure': false}),
    ),
  ]) {
    testWidgets('callsign settings card $name', (t) async {
      final h = Fixture();
      h.snapshot = snapshot;
      addTearDown(h.close);
      size(t, const Size(760, 420));
      final frame = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: validationApp(
            // The settings page scrolls, so the card sizes to its content.
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 720,
                  child: GameIdVisibilitySetting(session: h.session),
                ),
              ),
            ),
            InteractionSuite.standard,
            light: light,
            locale: const Locale('zh', 'CN'),
          ),
        ),
      );
      await _settle(t);
      if (name == '2-pending-dark') {
        // The Relay saves; the fixture answers with Hong Kong still pending.
        h.snapshot = _scm(callsign: '飞鹰', mirror: 'pending')..['revision'] = 4;
        await t.enterText(
          find.byKey(const Key('game-id-callsign-field')),
          '飞鹰',
        );
        await t.pump();
        await t.tap(find.byKey(const Key('game-id-callsign-save')));
        await _settle(t);
        expect(find.text('呼号已保存，但还有一处没同步好，点这里重试。'), findsOneWidget);
      }
      expect(find.byKey(const Key('game-id-callsign-field')), findsOneWidget);
      if (name != '2-pending-dark') {
        expect(find.text(snapshot['callsign'] as String? ?? ''), findsWidgets);
      }
      if (snapshot['canConfigure'] == false) {
        expect(find.byKey(const Key('game-id-needs-callsign')), findsOneWidget);
        // The legacy-account line would contradict the decision 乙 notes.
        expect(find.text('尚无可替代的独立呼号，游戏 ID 需要在各处展示。'), findsNothing);
        expect(
          find.text(
            name.startsWith('3-')
                ? '先设一个呼号才能隐藏游戏 ID。'
                : '你的游戏 ID 目前在部分地方是隐藏的，别人看到的是“成员”。设一个呼号，别人就会看到你的呼号；也可以改为显示。',
          ),
          findsOneWidget,
        );
      }
      if (snapshot['mirror'] == 'restorePending') {
        expect(
          find.byKey(const Key('game-id-mirror-restorePending')),
          findsOneWidget,
        );
      }
      await _capture(t, frame, name);
      await t.pumpWidget(const SizedBox());
      await _settle(t);
    });
  }

  testWidgets('profile editor shows the same callsign', (t) async {
    final h = Harness();
    final projection = PersonalProfileProjection.fromSnapshot(
      await h.port.read(),
    );
    final draft = PersonalProfileEditorDraft(edit(await h.port.read()));
    size(t, const Size(760, 900));
    final frame = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: frame,
        child: validationApp(
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PersonalProfileEditorPanel(
              projection: projection,
              initialDraft: draft,
              moduleLayout: projection.moduleLayout,
              onCancel: () {},
              onSaved: () {},
              onWallpaperChanged: (_) {},
              onSave: (_) async => const PersonalProfileActionResult(
                PersonalProfileActionOutcome.failed,
              ),
            ),
          ),
          InteractionSuite.standard,
          locale: const Locale('zh', 'CN'),
        ),
      ),
    );
    await _settle(t);
    // The account callsign field holds the same value as the settings card.
    await t.enterText(find.byKey(const Key('profile-call-sign-field')), '飞鹰');
    await _settle(t);
    expect(find.text('飞鹰'), findsWidgets);
    expect(find.text('呼号最多 10 个字符，中文算 2 个。'), findsNothing);
    await _capture(t, frame, '3-profile-editor-dark');
  });
}
