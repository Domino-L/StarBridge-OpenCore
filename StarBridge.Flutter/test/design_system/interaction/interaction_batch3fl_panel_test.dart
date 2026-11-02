import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/communities/community_fleet_statistics_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_organizations_test.dart' show fixture;
import 'interaction_batch3do_test.dart'
    show exposedNodes, loadFonts, scopedApp, size;

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

bool _hasFocusWithin(WidgetTester t, Finder target) {
  final wanted = t.element(target);
  final context = FocusManager.instance.primaryFocus?.context;
  if (context is! Element) return false;
  if (identical(wanted, context)) return true;
  var found = false;
  context.visitAncestorElements((element) {
    found = identical(element, wanted);
    return !found;
  });
  return found;
}

Future<void> _tabEnter(WidgetTester t, Finder target) async {
  var tabs = 0;
  do {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    tabs++;
  } while (!_hasFocusWithin(t, target) && tabs < 48);
  expect(tabs, inInclusiveRange(1, 48));
  expect(_hasFocusWithin(t, target), isTrue);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await _frames(t);
}

Finder _action(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(StarBridgeActionButton),
);

Future<void> _activate(WidgetTester t, String label, String input) async {
  final target = _action(label);
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  if (input == 'pointer') {
    await t.tap(target);
    await _frames(t);
  } else if (input == 'keyboard') {
    await _tabEnter(t, target);
  } else {
    final nodes = exposedNodes(t).where((n) {
      final data = n.getSemanticsData();
      return data.label == label && data.hasAction(SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
    await _frames(t);
  }
}

Map<String, Object?> _data({
  String scope = 's1',
  String query = '',
  bool busy = false,
  bool error = false,
  bool loading = false,
  bool navigation = false,
  bool statistics = false,
}) {
  final data = fixture(tab: 'ships');
  data['scope'] = scope;
  data['busy'] = busy;
  data['rows'] = [
    {'title': 'Sample ship', 'detail': 'Original call sign'},
  ];
  data['buttons'] = <Map<String, Object?>>[
    for (final button in data['buttons'] as List)
      if ((button as Map)['key'] != 'a6') Map<String, Object?>.from(button),
    {
      'key': 'a6',
      'label': '搜索舰船',
      'role': 'searchShips',
      'input': '输入舰船名称',
      'limit': 12,
    },
    {'key': 'a7', 'label': '舰队统计', 'role': 'fleetStatistics', 'limit': 128},
    {'key': 'a8', 'label': '下一页', 'role': 'nextPage', 'limit': 128},
    {'key': 'a9', 'label': '首页', 'role': 'firstPage', 'limit': 128},
    if (statistics)
      {'key': 'a10', 'label': '关闭统计', 'role': 'closeStatistics', 'limit': 128},
  ];
  final org = data['organization'] as Map;
  org['query'] = query;
  org['bodyError'] = error;
  org['bodyLoading'] = loading;
  org['rows'] = [
    {
      'owner': 'Long owner display name',
      'presence': 'online',
      'spec': 'small',
      'role': 'combat',
      'status': 'flyable',
      'price': r'$400',
    },
  ];
  if (navigation) {
    org['navigation'] = [
      {
        'name': '第一组织',
        'summary': '原摘要',
        'time': '',
        'key': 'a20',
        'selected': true,
      },
      {
        'name': '第二组织',
        'summary': '其它摘要',
        'time': '',
        'key': 'a21',
        'selected': false,
      },
    ];
  }
  if (statistics) {
    org['fleetStatistics'] = {
      'shipCount': 0,
      'modelCount': 0,
      'sharingMemberCount': 0,
      'pricedCount': 0,
      'totalCents': 0,
      'sizes': {},
      'roles': {},
      'matrix': {},
    };
  }
  return data;
}

Future<void> _mount(
  WidgetTester t,
  Map<String, Object?> data,
  InteractionSuite suite,
  void Function(String, String) onAction, {
  bool reduce = false,
  bool light = false,
}) async {
  final view = MenuFeatureView.parse(data);
  expect(view.state, 'ready');
  expect(view.organization, isNotNull);
  await t.pumpWidget(
    scopedApp(
      MenuOrganizationsPanel(view: view, onAction: onAction),
      suite,
      reduce: reduce,
      light: light,
    ),
  );
  await _frames(t);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('organization panel keyboard footer retains command source', (
    t,
  ) async {
    size(t, const Size(1300, 1000));
    final raw = fixture(tab: 'ships');
    (raw['buttons'] as List).add({
      'key': 'a7',
      'label': '下一页',
      'role': 'nextPage',
      'limit': 128,
    });
    final calls = <(String, String, InteractionSource)>[];
    await t.pumpWidget(
      scopedApp(
        MenuOrganizationsPanel(
          view: MenuFeatureView.parse(raw),
          onAction: (key, payload) =>
              calls.add((key, payload, currentStarBridgeActivationSource)),
        ),
        InteractionSuite.scan,
      ),
    );
    await _frames(t);
    final control = find.ancestor(
      of: find.text('下一页'),
      matching: find.byWidgetPredicate(
        (w) => w is ButtonStyleButton || w is SuitePressable,
      ),
    );
    expect(control, findsOneWidget);
    await t.ensureVisible(control);
    await _tabEnter(t, control);
    expect(calls, [('a7', '', InteractionSource.keyboard)]);
    expect(t.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite organization scoped commands actual $input are single dispatch',
        (t) async {
          size(t, const Size(1300, 1000));
          final semantics = t.ensureSemantics();
          final calls = <(String, String, InteractionSource)>[];
          void dispatch(String key, String value) =>
              calls.add((key, value, currentStarBridgeActivationSource));
          try {
            final data = _data();
            await _mount(t, data, suite, dispatch);
            expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
            final field = find.byType(TextField);
            final controller = t.widget<TextField>(field).controller!;
            await t.enterText(field, 'Aurora');
            final source = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            await _activate(t, '搜索', input);
            expect(calls, [('a6', 'Aurora', source)]);
            expect(controller.text, 'Aurora');
            expect(
              (data['organization'] as Map)['query'],
              '',
              reason: 'The renderer does not commit or invent a new view.',
            );
            await _activate(t, '下一页', input);
            await _activate(t, '舰队统计', input);
            expect(calls, [
              ('a6', 'Aurora', source),
              ('a8', '', source),
              ('a7', '', source),
            ]);
            expect(find.byType(CommunityFleetStatisticsDialog), findsNothing);
            // Native submit preserves its original opaque payload and reports
            // keyboard provenance without inventing a cross-process origin.
            await t.enterText(field, 'C2');
            await t.testTextInput.receiveAction(TextInputAction.done);
            await _frames(t);
            expect(calls.last, ('a6', 'C2', InteractionSource.keyboard));
            expect(calls, hasLength(4));
            // Original body-error retry is intentionally not gated by busy.
            await _mount(t, _data(busy: true, error: true), suite, dispatch);
            expect(
              t
                  .widget<StarBridgeActionButton>(_action('暂时无法读取，点击重试'))
                  .onActivate,
              isNotNull,
            );
            await _activate(t, '暂时无法读取，点击重试', input);
            expect(calls.last, ('refresh', '', source));
            expect(calls, hasLength(5));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      testWidgets(
        '$suite narrow organization list actual $input retains query and dismisses locally',
        (t) async {
          size(t, const Size(430, 1000));
          final semantics = t.ensureSemantics();
          final calls = <(String, String)>[];
          try {
            await _mount(
              t,
              _data(navigation: true),
              suite,
              (key, value) => calls.add((key, value)),
            );
            final controller = t
                .widget<TextField>(find.byType(TextField))
                .controller!;
            await t.enterText(find.byType(TextField), 'Aurora');
            expect(find.text('第二组织'), findsNothing);
            await _activate(t, '组织列表', input);
            expect(find.text('第二组织'), findsOneWidget);
            expect(find.text('返回当前组织'), findsOneWidget);
            expect(
              calls,
              isEmpty,
              reason: 'Showing the local list is not an organization command.',
            );
            await _activate(t, '返回当前组织', input);
            expect(find.text('第二组织'), findsNothing);
            expect(
              t.widget<TextField>(find.byType(TextField)).controller,
              same(controller),
            );
            expect(controller.text, 'Aurora');
            expect(calls, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets('$suite busy gates original actions but not error retry', (
      t,
    ) async {
      size(t, const Size(1300, 1000));
      final semantics = t.ensureSemantics();
      final calls = <String>[];
      try {
        await _mount(
          t,
          _data(busy: true),
          suite,
          (key, value) => calls.add('$key:$value'),
        );
        expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        for (final label in ['搜索', '舰队统计', '下一页', '首页']) {
          final target = _action(label);
          expect(t.widget<StarBridgeActionButton>(target).onActivate, isNull);
          expect(
            exposedNodes(t).where(
              (n) =>
                  n.getSemanticsData().label == label &&
                  n.getSemanticsData().hasAction(SemanticsAction.tap),
            ),
            isEmpty,
          );
          await t.ensureVisible(target);
          await t.tapAt(t.getCenter(target));
          await _frames(t);
        }
        expect(calls, isEmpty);
        await _mount(
          t,
          _data(busy: true, error: true),
          suite,
          (key, value) => calls.add('$key:$value'),
        );
        await _activate(t, '暂时无法读取，点击重试', 'keyboard');
        expect(calls, ['refresh:']);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets(
      '$suite query IME identity survives style changes and resets only original scope/tab rules',
      (t) async {
        size(t, const Size(1300, 1000));
        final calls = <String>[];
        void dispatch(String key, String value) => calls.add('$key:$value');
        await _mount(t, _data(query: 'server'), suite, dispatch);
        final field = find.byType(TextField);
        final editorState = t.state(find.byType(EditableText));
        final controller = t.widget<TextField>(field).controller!;
        final focus = t.widget<TextField>(field).focusNode;
        const value = TextEditingValue(
          text: 'Draft舰船',
          selection: TextSelection.collapsed(offset: 7),
          composing: TextRange(start: 0, end: 7),
        );
        await t.tap(field);
        t.testTextInput.updateEditingValue(value);
        await _frames(t);
        expect(controller.value, value);
        final next = InteractionSuite
            .values[(suite.index + 1) % InteractionSuite.values.length];
        await _mount(
          t,
          _data(query: 'new server read'),
          next,
          dispatch,
          reduce: true,
          light: true,
        );
        expect(t.state(find.byType(EditableText)), same(editorState));
        expect(t.widget<TextField>(field).controller, same(controller));
        expect(t.widget<TextField>(field).focusNode, same(focus));
        expect(controller.value, value);
        expect(calls, isEmpty);
        // The original length formatter still limits committed input.
        await t.enterText(field, '1234567890123456');
        expect(controller.text, '123456789012');
        await _mount(
          t,
          _data(scope: 's2', query: 'next scope'),
          next,
          dispatch,
        );
        expect(t.widget<TextField>(field).controller, same(controller));
        expect(controller.text, 'next scope');
        final tabChange = _data(scope: 's2', query: 'announcement');
        (tabChange['organization'] as Map)['tab'] = 'announcements';
        await _mount(t, tabChange, next, dispatch);
        expect(controller.text, 'announcement');
        expect(calls, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite statistics barrier dismiss/reopen and scope reset stay unchanged',
      (t) async {
        size(t, const Size(1300, 1000));
        final calls = <(String, String)>[];
        void dispatch(String key, String value) => calls.add((key, value));
        await _mount(t, _data(statistics: true), suite, dispatch);
        expect(find.byType(CommunityFleetStatisticsDialog), findsOneWidget);
        final statisticsBarrier = find.byWidgetPredicate(
          (w) => w is ModalBarrier && w.color == Colors.black54,
        );
        expect(statisticsBarrier, findsOneWidget);
        expect(t.widget<ModalBarrier>(statisticsBarrier).dismissible, isFalse);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await _frames(t);
        expect(find.byType(CommunityFleetStatisticsDialog), findsNothing);
        expect(calls, [('a10', '')]);
        await _mount(t, _data(statistics: true), suite, dispatch);
        expect(find.byType(CommunityFleetStatisticsDialog), findsNothing);
        await _activate(t, '舰队统计', 'pointer');
        expect(calls, [('a10', ''), ('a7', '')]);
        expect(find.byType(CommunityFleetStatisticsDialog), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await _frames(t);
        expect(calls.last, ('a10', ''));
        await _mount(t, _data(scope: 's2', statistics: true), suite, dispatch);
        expect(find.byType(CommunityFleetStatisticsDialog), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite ship owner shared tooltip is passive and keeps original full label',
      (t) async {
        size(t, const Size(1300, 1000));
        final calls = <String>[];
        await _mount(
          t,
          _data(),
          suite,
          (key, value) => calls.add('$key:$value'),
        );
        final tooltip = find.byWidgetPredicate(
          (w) =>
              w is StarBridgeTooltip && w.message == 'Long owner display name',
        );
        expect(tooltip, findsOneWidget);
        expect(
          find.descendant(
            of: tooltip,
            matching: find.text('Long owner display name'),
          ),
          findsOneWidget,
        );
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        try {
          await t.ensureVisible(tooltip);
          await mouse.moveTo(t.getCenter(tooltip));
          await _frames(t, 7);
          final state = t.state<SuiteTooltipState>(
            find.descendant(of: tooltip, matching: find.byType(SuiteTooltip)),
          );
          expect(state.isShowing, isTrue);
          expect(calls, isEmpty);
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await _mount(
            t,
            _data(),
            next,
            (key, value) => calls.add('$key:$value'),
            reduce: true,
            light: true,
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await _frames(t);
          expect(state.isShowing, isFalse);
          expect(calls, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await t.pumpWidget(const SizedBox.shrink());
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets('$suite unowned body loading remains truthful static caption', (
      t,
    ) async {
      size(t, const Size(1300, 1000));
      final calls = <String>[];
      await _mount(
        t,
        _data(loading: true),
        suite,
        (key, value) => calls.add('$key:$value'),
      );
      expect(find.text('正在读取…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SuiteProgressBar), findsNothing);
      expect(calls, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }, timeout: const Timeout(Duration(seconds: 45)));
  }
}
