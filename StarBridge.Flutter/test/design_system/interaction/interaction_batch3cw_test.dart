import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_frame.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../app/menu_overlay/menu_overlay_workspace_test.dart' show Fixture;
import 'interaction_batch3ct_test.dart' show host, detach;

FocusNode focusTarget(WidgetTester t, Finder target) {
  var w = t.widget(target);
  if (w is! IconButton && w is! ButtonStyleButton && w is! SuitePressable) {
    w = t.widget(
      find
          .descendant(
            of: target,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is IconButton ||
                  w is ButtonStyleButton ||
                  w is SuitePressable,
            ),
          )
          .first,
    );
  }
  if (w is IconButton) return w.focusNode!;
  if (w is ButtonStyleButton) return w.focusNode!;
  if (w is SuitePressable) return w.focusNode!;
  throw StateError('No public focus target');
}

Future<void> fire(
  WidgetTester t,
  String source,
  Finder target,
  String label,
) async {
  expect(target, findsOneWidget);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    focusTarget(t, target).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final w = t.widget(target);
    final actual =
        w is IconButton || w is ButtonStyleButton || w is SuitePressable
        ? target
        : find
              .descendant(
                of: target,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is IconButton ||
                      w is ButtonStyleButton ||
                      w is SuitePressable,
                ),
              )
              .first;
    final node = t.getSemantics(actual);
    expect(node.getSemanticsData().label, label);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        viewId: t.view.viewId,
        nodeId: node.id,
      ),
    );
  }
}

Widget sampleFrame(void Function(String) record) => MenuOverlayFrame(
  contextLabel: '工作区',
  returnLabel: '返回游戏',
  settingsLabel: '设置',
  onReturn: () => record('return'),
  onSettings: () => record('settings'),
  tools: [
    MenuOverlayTool(
      id: 'probe',
      label: '工具',
      icon: StarBridgeIconSemantic.tools,
      onActivate: () => record('tool'),
      isOpen: true,
      isActive: true,
      hasUnread: true,
    ),
  ],
);

Widget workbench(Fixture f, {MenuWorkspaceController? controller}) =>
    MenuOverlayWorkbench(
      controller: controller ?? f.controller,
      panels: f.panels,
      contextLabel: '工作区',
      returnLabel: '返回游戏',
      settingsLabel: '设置',
      closeLabel: '关闭',
      moveLabel: '移动',
      resizeLabel: '缩放',
      onReturn: () => f.controller.setVisible(false),
    );

// Trace the public command seam but execute the unchanged real controller.
// Pointer-down raising and the eventual button command are distinct events.
class ObservedController extends MenuWorkspaceController {
  ObservedController(Fixture f) : super(scope: 'fixture', panels: f.specs);
  final commands = <(String, InteractionSource)>[];
  @override
  void activate(String id) {
    commands.add(('activate:$id', captureStarBridgeActivationSource()()));
    super.activate(id);
  }

  @override
  void close(String id) {
    commands.add(('close:$id', captureStarBridgeActivationSource()()));
    super.close(id);
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final action in ['close', 'move', 'resize']) {
        testWidgets(
          '$suite $source panel $action preserves controller and origin',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = const Size(1200, 850);
            final semantics = t.ensureSemantics();
            final f = Fixture();
            final controller = ObservedController(f);
            controller.open('chat');
            controller.open('friends');
            final lease = controller.openPanels.last;
            try {
              await t.pumpWidget(
                host(workbench(f, controller: controller), suite),
              );
              await t.pumpAndSettle();
              final target = find.byKey(ValueKey('menu-$action-friends'));
              final label = switch (action) {
                'close' => '关闭',
                'move' => '移动: 好友',
                _ => '缩放: 好友',
              };
              if (source == 'keyboard') {
                focusTarget(t, target).requestFocus();
                await t.pump();
              }
              controller.commands.clear();
              await fire(t, source, target, label);
              expect(controller.commands, [
                if (source == 'pointer')
                  ('activate:friends', InteractionSource.programmatic),
                (
                  '${action == 'close' ? 'close' : 'activate'}:friends',
                  source == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              ]);
              expect(controller.isCurrent(lease), action != 'close');
              expect(f.probes['friends']!.mounted, 1);
              await t.pumpAndSettle();
              expect(f.probes['friends']!.disposed, action == 'close' ? 1 : 0);
              expect(
                controller.activeId,
                action == 'close' ? 'chat' : 'friends',
              );
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await detach(t);
              controller.dispose();
              t.view.reset();
            }
          },
        );
      }
    }
    for (final width in [400.0, 1200.0]) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        for (final action in ['return', 'settings', 'tool']) {
          testWidgets(
            '$suite $width $source $action exact synchronous origin',
            (t) async {
              t.view.devicePixelRatio = 1;
              t.view.physicalSize = Size(width, 700);
              final semantics = t.ensureSemantics();
              final calls = <(String, InteractionSource)>[];
              try {
                await t.pumpWidget(
                  host(
                    sampleFrame(
                      (value) => calls.add((
                        value,
                        captureStarBridgeActivationSource()(),
                      )),
                    ),
                    suite,
                  ),
                );
                await t.pumpAndSettle();
                final (target, label) = switch (action) {
                  'return' => (
                    find.byKey(const ValueKey('menu-return')),
                    '返回游戏',
                  ),
                  'settings' => (
                    find.byKey(const ValueKey('menu-settings')),
                    '设置',
                  ),
                  _ => (find.byKey(const ValueKey('menu-tool-probe')), '工具'),
                };
                await fire(t, source, target, label);
                expect(calls, [
                  (
                    action,
                    source == 'pointer'
                        ? InteractionSource.pointer
                        : InteractionSource.keyboard,
                  ),
                ]);
                expect(
                  captureStarBridgeActivationSource()(),
                  InteractionSource.programmatic,
                );
                expect(t.takeException(), isNull);
              } finally {
                semantics.dispose();
                await detach(t);
                t.view.reset();
              }
            },
          );
        }
      }
    }
  }
  testWidgets('compact return keeps synchronous command and pointer origin', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(400, 600);
    addTearDown(t.view.reset);
    final calls = <InteractionSource>[];
    await t.pumpWidget(
      host(
        MenuOverlayFrame(
          contextLabel: '工作区',
          returnLabel: '返回游戏',
          settingsLabel: '设置',
          tools: const [],
          onReturn: () => calls.add(captureStarBridgeActivationSource()()),
        ),
        InteractionSuite.scan,
      ),
    );
    await t.pumpAndSettle();
    final target = find.byKey(const ValueKey('menu-return'));
    expect(target, findsOneWidget);
    await t.tap(target);
    expect(calls, [InteractionSource.pointer]);
    await detach(t);
  });
}
