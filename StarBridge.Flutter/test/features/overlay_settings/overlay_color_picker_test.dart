import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_color_picker.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;
import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  test('picker and info source labels are localized in all languages', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in [
        'choose',
        'preview',
        'palette',
        'hue',
        'saturation',
        'brightness',
        'hex',
        'invalid',
        'draftHint',
        'apply',
      ]) {
        expect(strings.text('overlay.color.$key'), isNot('overlay.color.$key'));
      }
      expect(strings.text('overlay.source.title'), isNot(contains('场景')));
      expect(strings.text('overlay.source.title'), isNot(contains('場景')));
    }
  });

  testWidgets('picker validates hex and only changes the draft on Apply', (
    tester,
  ) async {
    size(tester, const Size(800, 900));
    final changed = <String>[];
    await tester.pumpWidget(
      app(
        Center(
          child: SizedBox(
            width: 320,
            child: OverlayColorField(
              label: '准星颜色',
              value: '#FFFFFF',
              onChanged: changed.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('overlay-color-hex')), '#12');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('overlay-color-apply')))
          .onPressed,
      isNull,
    );
    expect(find.text('请输入 #RRGGBB 格式的颜色值。'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('overlay-color-hex')),
      '#ab12ef',
    );
    await tester.pump();
    expect(changed, isEmpty);
    await tester.tap(find.byKey(const Key('overlay-color-apply')));
    await tester.pumpAndSettle();
    expect(changed, ['#AB12EF']);
    expect(find.byType(OverlayColorPickerDialog), findsNothing);
  });

  testWidgets('cancel and Escape discard local changes', (tester) async {
    size(tester, const Size(800, 900));
    final changed = <String>[];
    await tester.pumpWidget(
      app(
        Center(
          child: SizedBox(
            width: 320,
            child: OverlayColorField(
              label: '准星颜色',
              value: '#FFFFFF',
              onChanged: changed.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final escape in [false, true]) {
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('overlay-color-hex')),
        '#123456',
      );
      if (escape) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tap(find.text('取消'));
      }
      await tester.pumpAndSettle();
      expect(changed, isEmpty);
      expect(find.byType(OverlayColorPickerDialog), findsNothing);
    }
  });

  testWidgets(
    'palette clamps pointer and sliders support keyboard adjustment',
    (tester) async {
      size(tester, const Size(800, 900));
      await tester.pumpWidget(
        app(
          const OverlayColorPickerDialog(
            label: '准星颜色',
            initialValue: '#FF0000',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pad = find.byKey(const Key('overlay-color-palette'));
      await tester.tapAt(tester.getRect(pad).topRight - const Offset(1, -1));
      await tester.pump();
      final hex = tester.widget<TextField>(
        find.byKey(const Key('overlay-color-hex')),
      );
      expect(hex.controller!.text, isNot('#FFFFFF'));
      final gesture = await tester.startGesture(tester.getCenter(pad));
      await gesture.moveBy(const Offset(-1000, 1000));
      await gesture.up();
      await tester.pump();
      expect(hex.controller!.text, '#000000');
      final hue = find.byKey(const Key('overlay-color-hue'));
      await tester.tap(hue);
      await tester.pump();
      final before = tester.widget<Slider>(hue).value;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(tester.widget<Slider>(hue).value, greaterThan(before));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('theme-bound crosshair color cannot open the picker', (
    tester,
  ) async {
    size(tester, const Size(900, 1600));
    final changed = <Object?>[];
    await tester.pumpWidget(
      app(
        OverlayWorkspaceSettingsGroup(
          group: 'crosshair',
          fields: overlayWorkspaceFieldSpecs
              .where((f) => f.group == 'crosshair')
              .toList(),
          settings: settings({
            'showCrosshair': true,
            'crosshairUseThemeColor': true,
          }),
          onChanged: (_, value) => changed.add(value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(OverlayColorField);
    expect(tester.widget<OverlayColorField>(field).onChanged, isNull);
    await tester.tap(
      find.descendant(of: field, matching: find.byType(OutlinedButton)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OverlayColorPickerDialog), findsNothing);
    expect(changed, isEmpty);
  });

  testWidgets(
    'late dialog result cannot overwrite a changed or disabled field',
    (tester) async {
      size(tester, const Size(800, 900));
      final value = ValueNotifier('#FFFFFF');
      final enabled = ValueNotifier(true);
      addTearDown(value.dispose);
      addTearDown(enabled.dispose);
      final changed = <String>[];
      await tester.pumpWidget(
        app(
          ListenableBuilder(
            listenable: Listenable.merge([value, enabled]),
            builder: (_, _) => Center(
              child: SizedBox(
                width: 320,
                child: OverlayColorField(
                  label: '准星颜色',
                  value: value.value,
                  onChanged: enabled.value ? changed.add : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final disable in [false, true]) {
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('overlay-color-hex')),
          '#ABCDEF',
        );
        if (disable) {
          enabled.value = false;
        } else {
          value.value = '#FF0000';
        }
        await tester.pump();
        await tester.tap(find.byKey(const Key('overlay-color-apply')));
        await tester.pumpAndSettle();
        expect(changed, isEmpty);
      }
    },
  );

  testWidgets('narrow short dialog scrolls without hiding its actions', (
    tester,
  ) async {
    size(tester, const Size(360, 420));
    await tester.pumpWidget(
      app(
        const OverlayColorPickerDialog(label: '准星颜色', initialValue: '#FFFFFF'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const Key('overlay-color-apply'))).bottom,
      lessThan(420),
    );
    await tester.ensureVisible(find.byKey(const Key('overlay-color-hex')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-color-hex')).hitTestable(),
      findsOneWidget,
    );
  });

  for (final mode in AppearanceMode.values) {
    testWidgets('color picker golden ${mode.name}', (tester) async {
      await loadFonts();
      size(tester, const Size(560, 800));
      await tester.pumpWidget(
        app(
          const OverlayColorPickerDialog(
            label: '准星颜色',
            initialValue: '#41B6FF',
          ),
          mode,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/overlay-color-picker-${mode.name}.png'),
      );
    });
  }
}
