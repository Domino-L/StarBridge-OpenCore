import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_navigation.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/features/common/organization_holo.dart';
import 'package:starbridge_flutter/features/common/organization_holo_choice.dart';

import '../../_support/visual_output_dir.dart';
import '../friends/social_layout_test.dart' show loadFonts;

final _theme = buildStarBridgeTheme(
  FutureRestraintStyle.resolve(AppearanceMode.dark),
  const Locale('zh', 'CN'),
);

Widget _host(Widget child, {bool reduce = false, Key? boundary}) => MaterialApp(
  theme: _theme,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(
      backgroundColor: const Color(0xFF0B1E2E),
      body: OrganizationHolo(
        child: Center(
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: const Color(0xFF0B1E2E),
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    ),
  ),
);

const _key = ValueKey('holo-choice');

void main() {
  setUpAll(loadFonts);

  testWidgets('tap asks for the opposite state and keeps its width', (t) async {
    final asked = <bool>[];
    await t.pumpWidget(
      _host(
        OrganizationHoloChoice(
          controlKey: _key,
          label: '全部舰船',
          selected: false,
          onSelected: asked.add,
        ),
      ),
    );
    final before = t.getSize(find.byKey(_key));
    await t.tap(find.byKey(_key));
    await t.pump();
    expect(asked, [true]);
    await t.pumpWidget(
      _host(
        OrganizationHoloChoice(
          controlKey: _key,
          label: '全部舰船',
          selected: true,
          onSelected: asked.add,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(_key)), before);
    await t.tap(find.byKey(_key));
    await t.pump();
    expect(asked, [true, false]);
  });

  testWidgets('keyboard activates and semantics report the choice', (t) async {
    final semantics = t.ensureSemantics();
    final asked = <bool>[];
    await t.pumpWidget(
      _host(
        OrganizationHoloChoice(
          controlKey: _key,
          label: '全部舰船',
          selected: true,
          onSelected: asked.add,
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(asked, [false, false]);
    expect(
      t.getSemantics(find.bySemanticsLabel('全部舰船')),
      matchesSemantics(
        label: '全部舰船',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('disabled choice ignores input and takes no focus', (t) async {
    await t.pumpWidget(
      _host(
        const OrganizationHoloChoice(
          controlKey: _key,
          label: '全部舰船',
          selected: false,
        ),
      ),
    );
    await t.tap(find.byKey(_key), warnIfMissed: false);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
  });

  testWidgets('reduced motion jumps straight to the chosen face', (t) async {
    Widget choice(bool selected) => _host(
      OrganizationHoloChoice(
        controlKey: _key,
        label: '全部舰船',
        selected: selected,
        onSelected: (_) {},
      ),
      reduce: true,
    );
    await t.pumpWidget(choice(false));
    await t.pumpWidget(choice(true));
    expect(t.hasRunningAnimations, isFalse);
    final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: t.getCenter(find.byKey(_key)));
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    await mouse.removePointer();
  });

  testWidgets('a click shows no focus; the keyboard shows it inside the face', (
    t,
  ) async {
    await t.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OrganizationHoloChoice(
              controlKey: const ValueKey('a'),
              label: '全部舰船',
              selected: true,
              onSelected: (_) {},
            ),
            const SizedBox(width: 12),
            OrganizationHoloChoice(
              controlKey: const ValueKey('b'),
              label: '按舰船',
              selected: false,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    RenderObject face(String id) => t.renderObject(
      find
          .descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    // The heavy edge painted only for visible focus, or null.
    Path? focusEdge(String id) {
      Path? edge;
      expect(
        face(id),
        paints..everything((method, args) {
          if (method == #drawPath && (args[1] as Paint).strokeWidth == 2) {
            edge = args[0] as Path;
          }
          return true;
        }),
      );
      return edge;
    }

    await t.tap(
      find.byKey(const ValueKey('a')),
      kind: ui.PointerDeviceKind.mouse,
    );
    await t.pumpAndSettle();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    expect(focusEdge('a'), isNull, reason: '点击不画焦点');

    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(focusEdge('a'), isNull);
    final size = t.getSize(find.byKey(const ValueKey('b')));
    final bounds = focusEdge('b')!.getBounds();
    expect(bounds.top, greaterThanOrEqualTo(1), reason: '键盘焦点只画在按钮内');
    expect(bounds.bottom, lessThanOrEqualTo(size.height - 1));

    await t.tap(
      find.byKey(const ValueKey('b')),
      kind: ui.PointerDeviceKind.mouse,
    );
    await t.pumpAndSettle();
    expect(focusEdge('b'), isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(focusEdge('b'), isNotNull, reason: '点击后再用键盘，焦点要看得见');
  });

  testWidgets('section tabs use the holo face and keep keys and arrow keys', (
    t,
  ) async {
    var selected = 'one';
    await t.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => StarBridgeChoiceNavigation(
            faceBuilder: organizationHoloNavigationFace,
            selected: selected,
            onSelected: (id) => setState(() => selected = id),
            choices: const [
              StarBridgeNavigationChoice(
                id: 'one',
                label: '成员',
                controlKey: ValueKey('tab-one'),
                child: Text('成员'),
              ),
              StarBridgeNavigationChoice(
                id: 'two',
                label: '聊天, 3',
                controlKey: ValueKey('tab-two'),
                child: Text('聊天'),
              ),
              StarBridgeNavigationChoice(
                id: 'off',
                label: '活动',
                enabled: false,
                controlKey: ValueKey('tab-off'),
                child: Text('活动'),
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(OrganizationHoloChoice), findsNWidgets(3));

    await t.tap(find.byKey(const ValueKey('tab-off')), warnIfMissed: false);
    await t.pump();
    expect(selected, 'one');
    await t.tap(find.byKey(const ValueKey('tab-two')));
    await t.pumpAndSettle();
    expect(selected, 'two');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(selected, 'one');

    final handle = t.ensureSemantics();
    expect(
      t.getSemantics(find.bySemanticsLabel('聊天, 3')),
      matchesSemantics(
        label: '聊天, 3',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
    expect(t.takeException(), isNull);
  });

  testWidgets('render the states for review', (t) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(1500, 500);
    addTearDown(t.view.reset);
    final boundary = GlobalKey();
    Widget row(List<(String, bool, bool)> items) => Wrap(
      spacing: 6,
      children: [
        for (final (label, selected, enabled) in items)
          OrganizationHoloChoice(
            controlKey: ValueKey('c-$label'),
            label: label,
            selected: selected,
            onSelected: enabled ? (_) {} : null,
          ),
      ],
    );
    await t.pumpWidget(
      _host(
        boundary: boundary,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row([
              ('全部舰船', true, true),
              ('可调度', false, true),
              ('静止悬停', false, true),
              ('按住', false, true),
              ('不可用', false, false),
              ('不可用选中', true, false),
            ]),
            const SizedBox(height: 12),
            StarBridgeChoiceNavigation(
              faceBuilder: organizationHoloNavigationFace,
              selected: 'members',
              onSelected: (_) {},
              choices: const [
                StarBridgeNavigationChoice(
                  id: 'members',
                  label: '成员',
                  child: Text('成员'),
                ),
                StarBridgeNavigationChoice(
                  id: 'chat',
                  label: '聊天',
                  child: Text('聊天'),
                ),
                StarBridgeNavigationChoice(
                  id: 'ships',
                  label: '舰船',
                  child: Text('舰船'),
                ),
                StarBridgeNavigationChoice(
                  id: 'activity',
                  label: '活动',
                  child: Text('活动'),
                ),
                StarBridgeNavigationChoice(
                  id: 'settings',
                  label: '设置',
                  enabled: false,
                  child: Text('设置'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OrganizationHoloChoiceFrame(child: Text('排序 · 规格')),
                const SizedBox(width: 8),
                OrganizationHoloChoice(
                  controlKey: const ValueKey('c-focus'),
                  label: '键盘焦点',
                  selected: false,
                  onSelected: (_) {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: t.getCenter(find.byKey(const ValueKey('c-静止悬停'))),
    );
    await t.pumpAndSettle();
    final press = await t.startGesture(
      t.getCenter(find.byKey(const ValueKey('c-按住'))),
    );
    await t.pump(const Duration(milliseconds: 20));
    await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory(visualOutputDir('holo-choice'));
        await dir.create(recursive: true);
        await File('${dir.path}/holo-choice-states.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
    await press.up();
    await mouse.removePointer();
    await t.pumpAndSettle();
    for (var i = 0; i < 9; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory(visualOutputDir('holo-choice'));
        await dir.create(recursive: true);
        await File('${dir.path}/holo-choice-focus.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  });
}
