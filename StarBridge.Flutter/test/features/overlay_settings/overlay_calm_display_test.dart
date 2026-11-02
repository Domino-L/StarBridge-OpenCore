import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_calm_display_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  group('levels follow the overlay opacity until the user picks their own', () {
    test('full opacity rests at 35% and lights to 100%', () {
      final levels = OverlayCalmLevels.of(
        settings({'opacity': 1.0, 'calmDisplay': 'On'}),
      );
      expect(levels.enabled, isTrue);
      expect(levels.idle, 0.35);
      expect(levels.lit, 1.0);
      expect(levels.idleSet || levels.litSet, isFalse);
    });

    test('a low opacity never rests darker and lights to a readable 85%', () {
      final levels = OverlayCalmLevels.of(settings({'opacity': 0.25}));
      expect(levels.idle, 0.25);
      expect(levels.lit, 0.85);
      expect(levels.enabled, isFalse, reason: 'Unset (an older file) is off');
    });

    test('custom levels are used, floored at 15%, resting never above lit', () {
      final custom = OverlayCalmLevels.of(
        settings({'calmIdleOpacity': 0.5, 'calmLitOpacity': 0.7}),
      );
      expect((custom.idle, custom.lit), (0.5, 0.7));
      final crossed = OverlayCalmLevels.of(
        settings({'calmIdleOpacity': 0.9, 'calmLitOpacity': 0.5}),
      );
      expect((crossed.idle, crossed.lit), (0.5, 0.5));
      final floor = OverlayCalmLevels.of(settings({'opacity': 0.15}));
      expect(floor.idle, greaterThanOrEqualTo(OverlayCalmLevels.minimum));
    });
  });

  test(
    'settings from an older Host read as Unset, peek keys are validated',
    () {
      final legacy = settings().toMap()
        ..removeWhere((key, _) => key.startsWith('calm'));
      final read = OverlayWorkspaceSettings.fromMap(legacy);
      expect(read['calmDisplay'], 'Unset');
      expect(read['calmWaitSeconds'], 10);
      expect(read['calmPeekHotkey'], '');
      for (final valid in ['', 'Ctrl+Q', 'Alt+Shift+7', 'F5']) {
        expect(settings({'calmPeekHotkey': valid})['calmPeekHotkey'], valid);
      }
      for (final invalid in ['Ctrl+,', 'ctrl+q', 'Ctrl+Space', 'Q;']) {
        expect(
          () => settings({'calmPeekHotkey': invalid}),
          throwsFormatException,
          reason: invalid,
        );
      }
    },
  );

  testWidgets('controls edit the shared levels and keep idle at or below lit', (
    tester,
  ) async {
    size(tester, const Size(520, 1400));
    var current = settings({'opacity': 1.0, 'calmDisplay': 'Off'});
    final changes = <(String, Object?)>[];
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: OverlayCalmDisplayControls(
              settings: current,
              onSettingChanged: (field, value) {
                changes.add((field, value));
                setState(() => current = current.withValue(field, value));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    StarBridgeSlider slider(String key) => tester.widget<StarBridgeSlider>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(StarBridgeSlider),
      ),
    );
    expect(
      slider('overlay-calm-idle').onChanged,
      isNull,
      reason: 'shown, but locked while off',
    );
    expect(find.text('开启安静显示后可调整下面的设置。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('overlay-calm-enabled')));
    await tester.pumpAndSettle();
    expect(current['calmDisplay'], 'On');
    expect(slider('overlay-calm-idle').value, 0.35);
    expect(slider('overlay-calm-lit').value, 1.0);
    expect(find.text('跟随浮层不透明度自动设定'), findsNWidgets(2));

    slider('overlay-calm-lit').onChanged!(0.5);
    await tester.pumpAndSettle();
    expect(current['calmLitOpacity'], 0.5);
    slider('overlay-calm-idle').onChanged!(0.8);
    await tester.pumpAndSettle();
    expect(current['calmIdleOpacity'], 0.8);
    expect(current['calmLitOpacity'], 0.8, reason: 'lit rises with idle');
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('overlay-calm-preview-idle')))
          .opacity,
      0.8,
    );

    await tester.tap(find.byKey(const Key('overlay-calm-idle-follow')));
    await tester.pumpAndSettle();
    expect(current['calmIdleOpacity'], 0.0, reason: 'back to automatic');
    expect(slider('overlay-calm-idle').value, 0.35);

    await tester.tap(find.byKey(const Key('overlay-calm-peek-record')));
    await tester.pump();
    expect(find.text('请按下按键…'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(current['calmPeekHotkey'], '', reason: 'a letter needs a modifier');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(current['calmPeekHotkey'], 'Ctrl+Q');
    expect(find.text('Ctrl+Q'), findsOneWidget);
    await tester.tap(find.byKey(const Key('overlay-calm-peek-clear')));
    await tester.pumpAndSettle();
    expect(current['calmPeekHotkey'], '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the introduction offers to turn calm display on or not', (
    tester,
  ) async {
    size(tester, const Size(900, 400));
    final choices = <String>[];
    await tester.pumpWidget(
      app(OverlayCalmDisplayIntro(onChoose: choices.add)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('新功能：安静显示'), findsOneWidget);
    for (final choice in ['on', 'off']) {
      await tester.tap(find.byKey(const Key('overlay-calm-intro-open')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('overlay-calm-intro-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('overlay-calm-intro-$choice')));
      await tester.pumpAndSettle();
    }
    expect(choices, ['On', 'Off']);
  });
}
