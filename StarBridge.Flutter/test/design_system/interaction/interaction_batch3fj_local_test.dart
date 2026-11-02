import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/controls/semantic_action_style.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_expansion_tile.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_local_message_tile.dart';
import 'package:starbridge_flutter/features/communities/community_ship_loaners.dart';
import 'package:starbridge_flutter/features/communities/community_ships_copy.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/communities/community_ship_loaners_test.dart'
    as fixtures;
import 'interaction_batch3do_test.dart'
    show exposedNodes, loadFonts, scopedApp, size;

const _english = Locale('en');
final _time = DateTime.utc(2026, 10, 17, 12);

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _mount(
  WidgetTester t,
  Widget child,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) async {
  await t.pumpWidget(
    scopedApp(
      SizedBox(width: 360, child: child),
      suite,
      locale: _english,
      reduce: reduce,
      light: light,
    ),
  );
  await _frames(t);
}

Finder _action(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(StarBridgeActionButton),
);

FocusNode _publicFocus(WidgetTester t, Finder target) {
  final controls = find.descendant(
    of: target,
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is SuitePressable,
    ),
  );
  expect(controls, findsOneWidget);
  return switch (t.widget(controls)) {
    ButtonStyleButton b => b.focusNode!,
    SuitePressable b => b.focusNode!,
    _ => throw StateError('Missing public focus owner'),
  };
}

/// Real Tab traversal, not requestFocus or invoking a widget callback. Reader
/// input similarly dispatches the single currently exposed semantics action.
Future<void> _activate(
  WidgetTester t,
  Finder target,
  String input,
  String label,
) async {
  await t.ensureVisible(target);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'keyboard') {
    final focus = _publicFocus(t, target);
    var tabs = 0;
    do {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      tabs++;
    } while (FocusManager.instance.primaryFocus != focus && tabs < 48);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(tabs, inInclusiveRange(1, 48));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
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
  }
  await _frames(t);
}

CommunityLocalMessageTile _tile({
  String state = 'failed',
  String? error,
  bool occupied = false,
  InteractionSource source = InteractionSource.programmatic,
  VoidCallback? retry,
  VoidCallback? check,
  VoidCallback? restore,
}) => CommunityLocalMessageTile.presentation(
  key: const ValueKey('local-message'),
  text: 'Retained local message',
  state: state,
  error: error,
  createdAt: _time,
  composerOccupied: occupied,
  source: source,
  onRetry: retry,
  onCheck: check,
  onRestore: restore,
);

Finder get _progress => find.descendant(
  of: find.byType(CommunityLocalMessageTile),
  matching: find.byType(CircularProgressIndicator),
);

void _expectWaiting(WidgetTester t, {required bool animated}) {
  expect(_progress, findsOneWidget);
  final indicator = t.widget<CircularProgressIndicator>(_progress);
  expect(indicator.strokeWidth, 2);
  expect(indicator.value, animated ? isNull : .5);
  expect(t.getSize(_progress), const Size(12, 12));
  final frame = find.descendant(
    of: find.byType(CommunityLocalMessageTile),
    matching: find.byType(SuiteBusyFrame),
  );
  expect(frame, findsOneWidget);
  expect(InteractionScope.of(t.element(frame)).reduceMotion, !animated);
  // The half arc is a static waiting mark, never numeric completion progress.
  expect(
    exposedNodes(t).where((n) => n.getSemanticsData().value == '50%'),
    isEmpty,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite local actions preserve callbacks/source $input', (
        t,
      ) async {
        size(t, const Size(700, 850));
        final semantics = t.ensureSemantics();
        try {
          final calls = <(String, InteractionSource)>[];
          void record(String name) =>
              calls.add((name, currentStarBridgeActivationSource));
          await _mount(
            t,
            _tile(
              retry: () => record('retry'),
              restore: () => record('restore'),
            ),
            suite,
          );
          final source = input == 'pointer'
              ? InteractionSource.pointer
              : InteractionSource.keyboard;
          final retry = _action('Retry');
          final restore = _action('Move back to composer');
          expect(
            t.widget<StarBridgeActionButton>(retry).tone,
            ActionTone.warning,
          );
          expect(
            t
                .widget<StarBridgeActionButton>(retry)
                .nativeStyle!
                .foregroundColor!
                .resolve({}),
            t.element(retry).tokens.colors.warning,
          );
          for (final target in [retry, restore]) {
            final rect = t.getRect(target);
            expect(rect.width, greaterThanOrEqualTo(64));
            expect(rect.height, greaterThanOrEqualTo(44));
          }
          await _activate(t, retry, input, 'Retry');
          await _activate(t, restore, input, 'Move back to composer');
          expect(calls, [('retry', source), ('restore', source)]);
          expect(find.text('Retained local message'), findsOneWidget);
          expect(find.text('Not sent; message kept'), findsOneWidget);
          await _mount(
            t,
            _tile(state: 'unknown', check: () => record('check')),
            suite,
          );
          expect(_action('Retry'), findsNothing);
          expect(_action('Move back to composer'), findsNothing);
          await _activate(
            t,
            _action('Check send status'),
            input,
            'Check send status',
          );
          expect(calls, [
            ('retry', source),
            ('restore', source),
            ('check', source),
          ]);
          expect(find.text('Unconfirmed; may have been sent'), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      }, timeout: const Timeout(Duration(seconds: 45)));

      testWidgets('$suite loaner disclosure real $input has one owner', (
        t,
      ) async {
        size(t, const Size(700, 850));
        final semantics = t.ensureSemantics();
        try {
          final ship = fixtures.source(
            rows: [fixtures.loaner('Replacement Test', 'large', 'flyable')],
          );
          await _mount(t, CommunityShipLoaners(ship: ship), suite);
          final target = find.byType(StarBridgeExpansionTile);
          expect(target, findsOneWidget);
          expect(
            t.widget<StarBridgeExpansionTile>(target).useNativePageStorage,
            isTrue,
          );
          expect(find.byType(ExpansionTile), findsNothing);
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isFalse,
          );
          expect(find.text('Replacement Test'), findsNothing);
          expect(
            find.descendant(of: target, matching: find.byType(SuitePressable)),
            findsOneWidget,
          );
          await _activate(t, target, input, 'Loaners · 1');
          await _frames(t, 3);
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isTrue,
          );
          expect(find.text('Replacement Test'), findsNWidgets(2));
          expect(ship.loaners, hasLength(1));
          final label = exposedNodes(t).where(
            (n) =>
                n.getSemanticsData().label == 'Loaners · 1' &&
                n.getSemanticsData().hasAction(SemanticsAction.tap),
          );
          expect(label, hasLength(1));
          await _activate(t, target, input, 'Loaners · 1');
          await _frames(t, 2);
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isFalse,
          );
          expect(find.text('Replacement Test'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      }, timeout: const Timeout(Duration(seconds: 45)));
    }

    testWidgets('$suite disabled local controls/status remain authoritative', (
      t,
    ) async {
      size(t, const Size(700, 850));
      final semantics = t.ensureSemantics();
      try {
        await _mount(t, _tile(occupied: true), suite);
        expect(find.text('Not sent; message kept'), findsOneWidget);
        expect(
          find.text(
            'The composer has a draft. Clear it before moving this message back.',
          ),
          findsOneWidget,
        );
        for (final label in ['Retry', 'Move back to composer']) {
          expect(
            t.widget<StarBridgeActionButton>(_action(label)).onActivate,
            isNull,
          );
          expect(
            exposedNodes(t).where(
              (n) =>
                  n.getSemanticsData().label == label &&
                  n.getSemanticsData().hasAction(SemanticsAction.tap),
            ),
            isEmpty,
          );
        }
        await _mount(t, _tile(state: 'unknown'), suite);
        expect(
          t
              .widget<StarBridgeActionButton>(_action('Check send status'))
              .onActivate,
          isNull,
        );
        await _mount(t, _tile(error: 'rateLimited'), suite);
        expect(
          find.text('Sending too quickly. Try again shortly'),
          findsOneWidget,
        );
        await _mount(t, _tile(state: 'sent'), suite);
        expect(find.text('Sent'), findsOneWidget);
        expect(find.byType(StarBridgeActionButton), findsNothing);
        expect(_progress, findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets(
      '$suite local wait distinguishes known source and unknown menu work',
      (t) async {
        size(t, const Size(700, 850));
        final semantics = t.ensureSemantics();
        try {
          for (final source in InteractionSource.values) {
            await _mount(t, _tile(state: 'sending', source: source), suite);
            _expectWaiting(t, animated: source == InteractionSource.pointer);
            expect(find.text('Sending'), findsOneWidget);
            expect(find.byType(StarBridgeActionButton), findsNothing);
          }
          await _mount(t, _tile(state: 'sending'), suite);
          _expectWaiting(t, animated: false);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite live suite/theme/reduce keep local wait and loaner state',
      (t) async {
        size(t, const Size(700, 1000));
        final semantics = t.ensureSemantics();
        try {
          final ship = fixtures.source(
            rows: [fixtures.loaner('Replacement Test', 'large', 'flyable')],
          );
          Widget content() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tile(state: 'sending', source: InteractionSource.pointer),
              CommunityShipLoaners(ship: ship),
            ],
          );
          await _mount(t, content(), suite);
          _expectWaiting(t, animated: true);
          await _activate(
            t,
            find.byType(StarBridgeExpansionTile),
            'pointer',
            'Loaners · 1',
          );
          await _frames(t, 3);
          final state = t.state(find.byType(StarBridgeExpansionTile));
          final switched = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await _mount(t, content(), switched, reduce: true, light: true);
          expect(t.state(find.byType(StarBridgeExpansionTile)), same(state));
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isTrue,
          );
          expect(find.text('Replacement Test'), findsNWidgets(2));
          _expectWaiting(t, animated: false);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame))).suite,
            switched,
          );
          expect(Theme.of(t.element(_progress)).brightness, Brightness.light);
          await _mount(t, content(), switched);
          _expectWaiting(t, animated: true);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets('$suite loaner header preserves native ListTile geometry', (
      t,
    ) async {
      size(t, const Size(700, 1000));
      final ship = fixtures.source(
        rows: [fixtures.loaner('Replacement Test', 'large', 'flyable')],
      );
      const nativeKey = ValueKey('native-loaners');
      await _mount(
        t,
        Builder(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommunityShipLoaners(ship: ship),
              ExpansionTile(
                key: nativeKey,
                title: const Text('Loaners · 1'),
                subtitle: Text(
                  communityShipsText(context, 'loanerHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: const [],
              ),
            ],
          ),
        ),
        suite,
      );
      final shared = find.byType(StarBridgeExpansionTile);
      final native = find.byKey(nativeKey);
      Finder header(Finder root) =>
          find.descendant(of: root, matching: find.byType(ListTile));
      final sharedRect = t.getRect(header(shared));
      final nativeRect = t.getRect(header(native));
      expect(sharedRect.size, nativeRect.size);
      for (final label in [
        'Loaners · 1',
        communityShipsText(t.element(shared), 'loanerHint'),
      ]) {
        final a = t.getRect(
          find.descendant(of: shared, matching: find.text(label)),
        );
        final b = t.getRect(
          find.descendant(of: native, matching: find.text(label)),
        );
        expect(a.topLeft - sharedRect.topLeft, b.topLeft - nativeRect.topLeft);
        expect(a.size, b.size);
      }
      final sharedGlyph = find.descendant(
        of: header(shared),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is StandardIcon &&
              widget.semantic == StandardIconSemantic.expandMore,
        ),
      );
      expect(sharedGlyph, findsOneWidget);
      final sharedIcon = t.getRect(sharedGlyph);
      final nativeIcon = t.getRect(
        find.descendant(of: native, matching: find.byIcon(Icons.expand_more)),
      );
      expect(sharedIcon.size, nativeIcon.size);
      expect(
        sharedIcon.topLeft - sharedRect.topLeft,
        nativeIcon.topLeft - nativeRect.topLeft,
      );
      expect(t.getSize(shared).height + 2, t.getSize(native).height);
      final headerWidget = t.widget<ListTile>(header(shared));
      expect(
        headerWidget.onTap,
        isNull,
        reason: 'The shared pressable alone owns activation.',
      );
      expect(t.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets(
      '$suite loaner interoperates with original context-keyed PageStorage bool',
      (t) async {
        size(t, const Size(700, 850));
        final semantics = t.ensureSemantics();
        try {
          final bucket = PageStorageBucket();
          final ship = fixtures.source(
            rows: [fixtures.loaner('Replacement Test', 'large', 'flyable')],
          );
          Widget content(bool visible) => PageStorage(
            bucket: bucket,
            child: KeyedSubtree(
              key: const PageStorageKey('ship-details'),
              child: visible
                  ? CommunityShipLoaners(ship: ship)
                  : const SizedBox.shrink(),
            ),
          );
          await _mount(t, content(true), suite);
          await _activate(
            t,
            find.byType(StarBridgeExpansionTile),
            'keyboard',
            'Loaners · 1',
          );
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isTrue,
          );
          await _mount(t, content(false), suite);
          expect(find.byType(StarBridgeExpansionTile), findsNothing);
          await _mount(t, content(true), suite);
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isTrue,
          );
          expect(find.text('Replacement Test'), findsNWidgets(2));
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
