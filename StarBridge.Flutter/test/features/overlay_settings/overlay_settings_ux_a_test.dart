import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_value_format.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_rules.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';

import '../friends/social_layout_test.dart' show app, size;

OverlayWorkspaceSettings settings([Map<String, Object?> changes = const {}]) =>
    OverlayWorkspaceSettings.fromMap({
      'hideMissionWhenIdle': false,
      'showMission': false,
      for (final f in overlayWorkspaceFieldSpecs)
        f.field: switch (f.kind) {
          OverlayWorkspaceFieldKind.toggle => false,
          OverlayWorkspaceFieldKind.choice ||
          OverlayWorkspaceFieldKind.readOnlyChoice => f.options.first,
          OverlayWorkspaceFieldKind.numberChoice => f.numberOptions.first,
          OverlayWorkspaceFieldKind.number =>
            f.field == 'chatMaxVisibleCount' ? f.minimum.round() : f.minimum,
          OverlayWorkspaceFieldKind.color => '#FFFFFF',
          OverlayWorkspaceFieldKind.eventTypes => 0,
          OverlayWorkspaceFieldKind.eventDurations => <String, Object?>{
            for (final entry in overlayDurationFields) entry.$1: 0,
            'squadChange': 0,
            'commanderChange': 0,
          },
        },
      ...changes,
    });

void main() {
  test('A9 description states local scope in every locale', () {
    expect(
      AppStrings.resolve(const Locale('zh', 'CN'))
          .text('overlay.workspace.description'),
      '调整浮层显示的内容和位置。设置只保存在这台电脑上。',
    );
    expect(
      AppStrings.resolve(const Locale('zh', 'TW'))
          .text('overlay.workspace.description'),
      '調整浮層顯示的內容和位置。設定只保存在這台電腦上。',
    );
    expect(
      AppStrings.resolve(const Locale('en'))
          .text('overlay.workspace.description'),
      'Adjust what the overlay shows and where it appears. Settings stay on this computer.',
    );
  });
  testWidgets('A5 legacy tray value survives but has no settings entry', (
    tester,
  ) async {
    size(tester, const Size(1000, 1600));
    for (final value in [false, true]) {
      final saved = settings({'enableTrayMode': value});
      await tester.pumpWidget(
        app(
          OverlayWorkspaceSettingsGroup(
            group: 'startup',
            fields: overlayWorkspaceFieldSpecs
                .where((f) => f.group == 'startup')
                .toList(),
            settings: saved,
            onChanged: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('overlay-field-enableTrayMode')),
        findsNothing,
      );
      expect(saved.toMap()['enableTrayMode'], value);
      expect(tester.takeException(), isNull);
    }
  });
  test('A1 values carry localized units without redundant zeroes', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      String value(String field, num number) => overlayWorkspaceFormatValue(
        overlayWorkspaceFieldSpecs.singleWhere((f) => f.field == field),
        number,
        strings,
      );
      expect(
        value('communicationEventDurationSeconds', 2),
        '2 ${locale.languageCode == 'en' ? 's' : '秒'}',
      );
      expect(
        value('eventNotificationDurationSeconds', 2.5),
        '2.5 ${locale.languageCode == 'en' ? 's' : '秒'}',
      );
      for (final f in overlayWorkspaceFieldSpecs.where(
        (f) => f.unit == OverlayWorkspaceUnit.percent,
      )) {
        expect(value(f.field, .85), '85%');
        expect(value(f.field, 0), '0%');
      }
      expect(value('memberNameColumnRatio', .18), '18%');
      expect(value('crosshairSize', 24), '24 px');
      expect(
        value('chatMaxVisibleCount', 3),
        '3 ${strings.text('overlay.workspace.unit.count')}',
      );
    }
  });
  test('A2 every schema choice is translated in all three languages', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final f in overlayWorkspaceFieldSpecs.where(
        (f) => f.kind == OverlayWorkspaceFieldKind.choice,
      )) {
        for (final option in f.options) {
          final key = 'overlay.workspace.option.$option';
          expect(
            strings.text(key),
            isNot(key),
            reason: '$locale ${f.field} $option',
          );
        }
      }
    }
  });
  test('A3 module heading describes lock and opacity controls', () {
    expect(
      AppStrings.resolve(const Locale('zh', 'CN'))
          .text('overlay.editor.opacityControls'),
      '当前模块',
    );
    expect(
      AppStrings.resolve(const Locale('zh', 'TW'))
          .text('overlay.editor.opacityControls'),
      '目前模組',
    );
    expect(
      AppStrings.resolve(const Locale('en', 'US'))
          .text('overlay.editor.opacityControls'),
      'This module',
    );
  });
  test('A4 all disable paths have localized reasons from the same policy', () {
    final samples = [
      settings(),
      settings({'showCrosshair': true, 'crosshairUseThemeColor': true}),
      settings({'showCrosshair': true, 'crosshairMode': 'Dot'}),
      settings({'showCrosshair': true, 'crosshairMode': 'Circle'}),
      settings({'skin': 'Verdict'}),
      settings({'showNotice': true}),
    ];
    final seen = <String>{};
    for (final s in samples) {
      for (final f in overlayWorkspaceFieldSpecs) {
        final reason = overlayWorkspaceFieldDisabledReason(f.field, s);
        expect(overlayWorkspaceFieldEnabled(f.field, s), reason == null);
        if (reason != null) {
          seen.add(reason.split('.').last);
          for (final locale in AppStrings.supportedLocales) {
            expect(AppStrings.resolve(locale).text(reason), isNot(reason));
          }
        }
      }
    }
    expect(
      seen,
      containsAll([
        'fixedPalette',
        'crosshair',
        'themeColor',
        'crosshairStyle',
        'centerMark',
        'events',
        'chat',
        'offlineMembers',
        'notice',
        'friendEvents',
        'startup',
      ]),
    );
    expect(
      overlayWorkspaceFieldDisabledReason('crosshairColor', settings()),
      endsWith('.crosshair'),
    );
    expect(
      overlayWorkspaceFieldEnabled(
        'crosshairSize',
        settings({'showCrosshair': true}),
      ),
      true,
    );
  });
  testWidgets('A1 A4 controls display units and disabled explanations', (
    tester,
  ) async {
    size(tester, const Size(1000, 1600));
    await tester.pumpWidget(
      app(
        OverlayWorkspaceSettingsGroup(
          group: 'crosshair',
          fields: overlayWorkspaceFieldSpecs
              .where((f) => f.group == 'crosshair')
              .toList(),
          settings: settings(),
          onChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('开启“显示准星”后可调整'), findsWidgets);
    expect(find.textContaining('8 px'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('overlay-field-crosshairSize')))
          .onChanged,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
