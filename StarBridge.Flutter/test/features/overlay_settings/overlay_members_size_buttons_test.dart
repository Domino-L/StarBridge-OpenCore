import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_members_size.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_members_size_buttons.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module_style_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_number_field.dart';

import '../friends/social_layout_test.dart' show app;
import 'overlay_visor_layout_test.dart' show visor, shipped;

void main() {
  test('size labels and accessibility copy exist in all three languages', () {
    final locales = [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ];
    final expected = ['高 5 行 · 宽 364', '高 5 行 · 寬 364', '5 rows · width 364'];
    for (var index = 0; index < locales.length; index++) {
      final copy = AppStrings.resolve(locales[index]).text;
      expect(
        copy('overlay.workspace.membersSize.dimensions')
            .replaceAll('{rows}', '5')
            .replaceAll('{width}', '364'),
        expected[index],
      );
      for (final action in ['rows', 'addRow', 'removeRow', 'widen', 'narrow']) {
        final key = 'overlay.workspace.membersSize.$action';
        expect(copy(key), isNot(key));
      }
    }
  });
  for (final height in [true, false]) {
    testWidgets(
      'steps ${height ? 'one row' : 'ten units'} and respects limits',
      (tester) async {
        final spec = height
            ? OverlayMembersSize.height
            : OverlayMembersSize.width;
        num value = height ? 394 : 364;
        var changes = 0;
        late StateSetter rebuild;
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return OverlayWorkspaceNumberField(
                  spec: spec,
                  label: 'Size',
                  value: value,
                  onChanged: (_) =>
                      fail('button must use the discrete callback'),
                  onStep: (next) => setState(() {
                    value = next! as num;
                    changes++;
                  }),
                );
              },
            ),
          ),
        );
        await tester.pump();
        final plus = find.byKey(Key('overlay-${spec.field}-plus'));
        final minus = find.byKey(Key('overlay-${spec.field}-minus'));
        final initialRows = OverlayMembersSize.rows(value);
        await tester.tap(plus);
        await tester.pump();
        expect(changes, 1);
        expect(
          height ? OverlayMembersSize.rows(value) : value,
          height ? initialRows + 1 : 374,
        );
        await tester.tap(minus);
        await tester.pump();
        expect(changes, 2);
        expect(
          height ? OverlayMembersSize.rows(value) : value,
          height ? initialRows : 364,
        );
        if (height) expect(find.text('$initialRows 行'), findsOneWidget);
        expect(tester.widget<IconButton>(plus).tooltip, height ? '增加一行' : '加宽');
        expect(
          tester.widget<IconButton>(minus).tooltip,
          height ? '减少一行' : '减窄',
        );
        rebuild(() => value = spec.maximum);
        await tester.pump();
        expect(tester.widget<IconButton>(plus).onPressed, isNull);
        await tester.tap(plus);
        expect(changes, 2);
        rebuild(() => value = spec.minimum);
        await tester.pump();
        expect(tester.widget<IconButton>(minus).onPressed, isNull);
      },
    );
  }

  testWidgets('both global layout lock and member lock disable size buttons', (
    tester,
  ) async {
    for (final global in [true, false]) {
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: OverlayWorkspaceModuleStyleControls(
              group: 'members',
              layout: [shipped('Members').copyWith(isLocked: !global)],
              settings: visor(),
              layoutLocked: global,
              onLayoutChanged: (_, _) {},
              onSettingChanged: (_, _) => fail('locked'),
              onSizeStep: (_, _) => fail('locked step'),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final field in ['visorMembersHeight', 'visorMembersWidth']) {
        for (final action in ['plus', 'minus']) {
          final button = tester.widget<IconButton>(
            find.byKey(Key('overlay-$field-$action')),
          );
          expect(button.onPressed, isNull);
        }
      }
    }
  });

  testWidgets('external size changes update rows and button values', (
    tester,
  ) async {
    num? written;
    final height =
        OverlayMembersSize.overhead + 5 * OverlayMembersSize.rowHeight;
    await tester.pumpWidget(
      app(
        OverlayMembersSizeButtons(
          field: 'visorMembersHeight',
          value: height,
          onChanged: (value) => written = value as num,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('5 行'), findsOneWidget);
    await tester.tap(find.byKey(const Key('overlay-visorMembersHeight-plus')));
    expect(
      written,
      OverlayMembersSize.overhead + 6 * OverlayMembersSize.rowHeight,
    );
  });
}
