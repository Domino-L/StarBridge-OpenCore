import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_loading.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/platform/window/menu_read_feedback.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_organizations_test.dart' show fixture;
import 'interaction_batch3do_test.dart'
    show exposedNodes, loadFonts, scopedApp, size;

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Map<String, Object?> _data({
  String tab = 'ships',
  String scope = 's1',
  bool loading = false,
  bool refreshing = false,
  bool busy = false,
  bool empty = false,
  Object? feedback,
}) {
  final data = fixture(tab: tab);
  data['scope'] = scope;
  data['refreshing'] = refreshing;
  data['busy'] = busy;
  data['readFeedback'] = feedback;
  final org = data['organization'] as Map;
  org['bodyLoading'] = loading;
  if (empty) {
    data['rows'] = <Map<String, Object?>>[];
    org['rows'] = <Map<String, Object?>>[];
  }
  return data;
}

Future<MenuFeatureView> _mount(
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
  return view;
}

void _expectMarker(
  WidgetTester t,
  InteractionSuite suite, {
  required bool animated,
}) {
  final markers = find.byType(MenuLoading);
  expect(markers, findsOneWidget);
  final frame = find.descendant(
    of: markers,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(frame, findsOneWidget);
  final data = InteractionScope.of(t.element(frame));
  expect(data.suite, suite);
  expect(data.reduceMotion, !animated);
  final track = find.descendant(
    of: markers,
    matching: find.byType(LinearProgressIndicator),
  );
  expect(track, findsOneWidget);
  expect(t.widget<LinearProgressIndicator>(track).minHeight, 2);
  expect(
    t.widget<LinearProgressIndicator>(track).value,
    animated &&
            (suite == InteractionSuite.standard ||
                suite == InteractionSuite.glow)
        ? isNull
        : .5,
  );
  expect(
    exposedNodes(t).where((n) => n.getSemanticsData().value.contains('50%')),
    isEmpty,
    reason: 'Static half track is a waiting marker, not 50 percent complete.',
  );
}

Future<Uint8List> _markerPixels(WidgetTester t) async {
  final marker = find.byType(MenuLoading);
  final boundaryFinder = find.descendant(
    of: marker,
    matching: find.byType(RepaintBoundary),
  );
  expect(boundaryFinder, findsOneWidget);
  final boundary = t.renderObject<RenderRepaintBoundary>(boundaryFinder);
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  testWidgets('organization first body read consumes actual feedback marker', (
    t,
  ) async {
    size(t, const Size(1300, 1000));
    final raw = fixture(tab: 'ships');
    (raw['organization'] as Map)['bodyLoading'] = true;
    raw['readFeedback'] = {'request': 1, 'source': 'pointer'};
    final view = MenuFeatureView.parse(raw);
    final calls = <(String, String)>[];
    expect(view.state, 'ready');
    await t.pumpWidget(
      scopedApp(
        MenuOrganizationsPanel(
          view: view,
          onAction: (key, value) => calls.add((key, value)),
        ),
        InteractionSuite.scan,
      ),
    );
    await _frames(t);
    expect(find.byType(MenuLoading), findsOneWidget);
    expect(calls, isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 45)));

  for (final suite in InteractionSuite.values) {
    for (final source in [
      'pointer',
      'keyboard',
      'programmatic',
      'absent',
      'bad-source',
      'bad-request',
    ]) {
      testWidgets('$suite organization waiting uses parsed $source only', (
        t,
      ) async {
        size(t, const Size(1300, 1000));
        final semantics = t.ensureSemantics();
        final calls = <(String, String)>[];
        final Object? feedback = switch (source) {
          'absent' => null,
          'bad-source' => {'request': 1, 'source': 'synthetic-reader'},
          'bad-request' => {'request': -1, 'source': 'pointer'},
          _ => {'request': 1, 'source': source},
        };
        try {
          for (final scene in [
            'first-ships',
            'retained-ships',
            'first-members',
            'retained-members',
          ]) {
            final first = scene.startsWith('first');
            final members = scene.endsWith('members');
            final view = await _mount(
              t,
              _data(
                tab: members ? 'members' : 'ships',
                loading: first,
                refreshing: !first,
                empty: first,
                feedback: feedback,
              ),
              suite,
              (key, value) => calls.add((key, value)),
            );
            if (source == 'absent' || source.startsWith('bad-')) {
              expect(view.readFeedback, isNull);
            } else {
              expect(view.readFeedback!.origin.name, source);
              expect(view.readFeedback!.origin, switch (source) {
                'pointer' => MenuReadOrigin.pointer,
                'keyboard' => MenuReadOrigin.keyboard,
                _ => MenuReadOrigin.programmatic,
              });
              expect(view.readFeedback!.request, 1);
            }
            _expectMarker(t, suite, animated: source == 'pointer');
            expect(find.byType(CircularProgressIndicator), findsNothing);
            if (members) {
              expect(find.text(first ? '正在加载成员…' : '正在更新成员…'), findsOneWidget);
              final board = t.widget<OrganizationMemberBoard>(
                find.byType(OrganizationMemberBoard),
              );
              expect(board.rows.length, first ? 0 : 4);
              expect(board.controlsEnabled, isFalse);
            } else if (!first) {
              expect(find.text('远航者 · 你'), findsOneWidget);
              expect(find.text('白鸦'), findsOneWidget);
              expect(view.rows, hasLength(4));
            }
            expect(calls, isEmpty);
            expect(t.takeException(), isNull, reason: scene);
          }
          await t.pump(const Duration(seconds: 6));
          expect(
            calls,
            isEmpty,
            reason: 'Presentation cannot start polling or dispatch opaque commands.',
          );
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      }, timeout: const Timeout(Duration(seconds: 45)));
    }

    testWidgets('$suite pure busy marker cannot borrow a prior pointer read', (
      t,
    ) async {
      size(t, const Size(1300, 1000));
      final semantics = t.ensureSemantics();
      final calls = <String>[];
      try {
        for (final tab in ['ships', 'members']) {
          await _mount(
            t,
            _data(
              tab: tab,
              refreshing: true,
              feedback: {'request': 1, 'source': 'pointer'},
            ),
            suite,
            (key, value) => calls.add('$key:$value'),
          );
          _expectMarker(t, suite, animated: true);
          final view = await _mount(
            t,
            _data(
              tab: tab,
              busy: true,
              feedback: {'request': 1, 'source': 'pointer'},
            ),
            suite,
            (key, value) => calls.add('$key:$value'),
          );
          expect(view.busy, isTrue);
          expect(view.refreshing, isFalse);
          expect(view.organization!.bodyLoading, isFalse);
          _expectMarker(t, suite, animated: false);
          expect(find.text('正在处理…'), findsOneWidget);
          if (tab == 'members') {
            expect(
              t
                  .widget<OrganizationMemberBoard>(
                    find.byType(OrganizationMemberBoard),
                  )
                  .controlsEnabled,
              isFalse,
            );
          }
          expect(calls, isEmpty);
        }
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets(
      '$suite live wait source/theme/suite/reduce affect only local decoration',
      (t) async {
        size(t, const Size(1300, 1000));
        final semantics = t.ensureSemantics();
        final calls = <String>[];
        void dispatch(String key, String value) => calls.add('$key:$value');
        try {
          await _mount(
            t,
            _data(
              refreshing: true,
              feedback: {'request': 1, 'source': 'pointer'},
            ),
            suite,
            dispatch,
          );
          final panelState = t.state(find.byType(MenuOrganizationsPanel));
          _expectMarker(t, suite, animated: true);
          await _mount(
            t,
            _data(
              refreshing: true,
              feedback: {'request': 2, 'source': 'keyboard'},
            ),
            suite,
            dispatch,
          );
          _expectMarker(t, suite, animated: false);
          expect(
            t.state(find.byType(MenuOrganizationsPanel)),
            same(panelState),
          );
          final first = await _markerPixels(t);
          await _frames(t, 4);
          expect(listEquals(first, await _markerPixels(t)), isTrue);
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await _mount(
            t,
            _data(
              refreshing: true,
              feedback: {'request': 2, 'source': 'keyboard'},
            ),
            next,
            dispatch,
            light: true,
          );
          _expectMarker(t, next, animated: false);
          expect(
            Theme.of(t.element(find.byType(MenuLoading))).brightness,
            Brightness.light,
          );
          await _mount(
            t,
            _data(
              refreshing: true,
              feedback: {'request': 3, 'source': 'pointer'},
            ),
            next,
            dispatch,
          );
          _expectMarker(t, next, animated: true);
          await _mount(
            t,
            _data(
              refreshing: true,
              feedback: {'request': 3, 'source': 'pointer'},
            ),
            next,
            dispatch,
            reduce: true,
          );
          _expectMarker(t, next, animated: false);
          final reduced = await _markerPixels(t);
          await _frames(t, 4);
          expect(listEquals(reduced, await _markerPixels(t)), isTrue);
          expect(find.text('远航者 · 你'), findsOneWidget);
          expect(calls, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite idle and unmount retire wait without commands or owned timers',
      (t) async {
        size(t, const Size(1300, 1000));
        final semantics = t.ensureSemantics();
        final calls = <String>[];
        void dispatch(String key, String value) => calls.add('$key:$value');
        try {
          await _mount(
            t,
            _data(
              refreshing: true,
              feedback: {'request': 1, 'source': 'pointer'},
            ),
            suite,
            dispatch,
          );
          _expectMarker(t, suite, animated: true);
          await _mount(t, _data(), suite, dispatch);
          expect(find.byType(MenuLoading), findsNothing);
          expect(find.byType(SuiteBusyFrame), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await _frames(t, 4);
          expect(calls, isEmpty);
          await _mount(
            t,
            _data(
              scope: 's2',
              loading: true,
              empty: true,
              feedback: {'request': 2, 'source': 'programmatic'},
            ),
            suite,
            dispatch,
          );
          _expectMarker(t, suite, animated: false);
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(seconds: 30));
          expect(find.byType(MenuLoading), findsNothing);
          expect(calls, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite retained member refresh preserves original editor/rows/scroll',
      (t) async {
        size(t, const Size(1300, 650));
        final semantics = t.ensureSemantics();
        final calls = <String>[];
        void dispatch(String key, String value) => calls.add('$key:$value');
        Map<String, Object?> data({bool refreshing = false}) {
          final value = _data(
            tab: 'members',
            refreshing: refreshing,
            feedback: {'request': 1, 'source': 'pointer'},
          );
          final org = value['organization'] as Map;
          final samples = org['rows'] as List;
          value['rows'] = [
            for (var i = 0; i < 40; i++)
              {'title': 'Retained member $i', 'detail': ''},
          ];
          org['rows'] = [
            for (var i = 0; i < 40; i++)
              {
                ...samples[i % samples.length] as Map,
                'handle': 'Retained_$i',
                'profileKey': 'om${i + 1}',
              },
          ];
          org['total'] = 40;
          org['matched'] = 40;
          return value;
        }

        try {
          await _mount(t, data(), suite, dispatch);
          final field = find.byType(TextField);
          final controller = t.widget<TextField>(field).controller!;
          final editor = t.state(find.byType(EditableText));
          await t.enterText(field, 'Draft member query');
          final body = find.byKey(const ValueKey('menu-org-body-members'));
          final scroll = find.descendant(
            of: body,
            matching: find.byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            ),
          );
          expect(scroll, findsOneWidget);
          final scrollState = t.state<ScrollableState>(scroll);
          final position = scrollState.position;
          await t.drag(body, const Offset(0, -400));
          await _frames(t, 4);
          expect(position.pixels, greaterThan(0));
          final offset = position.pixels;
          await _mount(t, data(refreshing: true), suite, dispatch);
          // Flutter may recreate its internal position on inherited settings
          // updates, absorbing the previous offset. Retain the real viewport
          // state and its current offset, not the retired internal object.
          expect(t.state<ScrollableState>(scroll), same(scrollState));
          expect(t.state<ScrollableState>(scroll).position.pixels, offset);
          expect(t.widget<TextField>(field).controller, same(controller));
          expect(t.state(find.byType(EditableText)), same(editor));
          expect(controller.text, 'Draft member query');
          final board = t.widget<OrganizationMemberBoard>(
            find.byType(OrganizationMemberBoard),
          );
          expect(board.rows, hasLength(40));
          expect(board.controlsEnabled, isFalse);
          _expectMarker(t, suite, animated: true);
          expect(calls, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite default common member board keeps original spinner and refreshing text',
      (t) async {
        size(t, const Size(1300, 1000));
        final controller = TextEditingController();
        final calls = <String>[];
        try {
          Widget board({bool loading = false, bool refreshing = false}) =>
              SizedBox(
                width: 1000,
                child: OrganizationMemberBoard(
                  rows: const [],
                  searchController: controller,
                  onSearch: calls.add,
                  namespace: 'untouched-default',
                  roleLabel: '角色',
                  loading: loading,
                  refreshing: refreshing,
                ),
              );
          await t.pumpWidget(scopedApp(board(loading: true), suite));
          await _frames(t);
          expect(find.byType(MenuLoading), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            t.getSize(find.byType(CircularProgressIndicator)),
            const Size(20, 20),
          );
          expect(find.text('正在加载成员…'), findsOneWidget);
          await t.pumpWidget(scopedApp(board(refreshing: true), suite));
          await _frames(t);
          expect(find.byType(MenuLoading), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('正在更新成员…'), findsOneWidget);
          expect(calls, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
