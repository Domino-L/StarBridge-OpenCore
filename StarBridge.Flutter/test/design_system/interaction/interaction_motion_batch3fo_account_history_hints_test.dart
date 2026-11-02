import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_menu.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart';
import 'package:starbridge_flutter/features/settings/local_event_history_dialog.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3bc_test.dart' show HistoryPort;
import 'interaction_batch3by_test.dart' show MenuFixture, menuProjection;
import 'interaction_batch3i_test.dart' show scopedApp;

// Component regression only: the real account menu and history dialog, with
// their existing fixture projection/read port. No shell, bridge, or user files.
class _Probe {
  _Probe(this.suite, {this.history = false, this.accountDialog = false}) {
    if (history) {
      port = HistoryPort('3fo retained original history');
      controller = LocalHistoryController(port!);
    }
  }

  final InteractionSuite suite;
  final bool history;
  final bool accountDialog;
  HistoryPort? port;
  LocalHistoryController? controller;
  bool reduce = false, closed = false;
  late StateSetter update;
  Future<Object?>? result;
  final commands = <(String, InteractionSource)>[];

  Widget account() => AccountMenu(
    destinations: const [MenuFixture.descriptor],
    projection: menuProjection,
    expanded: true,
    // Intentionally no ManualPresenceController: exercise _AccountButton,
    // not the separate signed-in AccountIdentityButton hint.
    onSelect: (value) =>
        commands.add((value.id, currentStarBridgeActivationSource)),
    onLogin: () => commands.add(('login', currentStarBridgeActivationSource)),
    onLogout: () => commands.add(('logout', currentStarBridgeActivationSource)),
    onIssueAction: () =>
        commands.add(('issue', currentStarBridgeActivationSource)),
  );

  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        Builder(
          builder: (context) => Align(
            alignment: Alignment.topRight,
            child: history || accountDialog
                ? StarBridgeActionButton(
                    controlKey: const Key('3fo-open-parent'),
                    onActivate: (source) {
                      result = showStarBridgeDialog<Object?>(
                        context,
                        source: source,
                        builder: (_) => history
                            ? LocalEventHistoryDialog(controller: controller!)
                            : Dialog(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: account(),
                                ),
                              ),
                      ).whenComplete(() => closed = true);
                    },
                    child: const Text('Open actual parent'),
                  )
                : account(),
          ),
        ),
        suite,
        reduce: reduce,
      );
    },
  );

  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await _frames(t);
    controller?.dispose();
  }
}

Future<void> _frames(WidgetTester t, [int count = 3]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _mount(WidgetTester t, _Probe probe) async {
  size(t, const Size(1180, 960));
  await t.pumpWidget(probe.app());
  await _frames(t);
  if (probe.history || probe.accountDialog) {
    await t.tap(find.byKey(const Key('3fo-open-parent')));
    // Finish route entrance and the history's one finite read acknowledgement.
    // There is no pending port or periodic embedded-history watcher here.
    await _frames(t, 11);
    expect(probe.closed, isFalse);
  }
}

Finder _target(String key) => find.byKey(Key(key));

Finder _hint(String key) => find
    .ancestor(of: _target(key), matching: find.byType(StarBridgeTooltip))
    .first;

List<SuiteTooltipState> _showing(WidgetTester t) => t
    .stateList<SuiteTooltipState>(find.byType(SuiteTooltip))
    .where((state) => state.isShowing)
    .toList();

String _message(WidgetTester t, String key) =>
    t.widget<StarBridgeTooltip>(_hint(key)).message;

Future<void> _hover(WidgetTester t, TestGesture mouse, String key) async {
  await t.ensureVisible(_target(key));
  await mouse.moveTo(t.getCenter(_target(key)));
  await t.pump(const Duration(milliseconds: 451));
  await _frames(t);
  expect(_showing(t), hasLength(1));
  expect(_showing(t).single.widget.message, _message(t, key));
}

void _bounded(WidgetTester t, String message) {
  final text = find.text(message).last;
  final box = t.getRect(
    find.ancestor(of: text, matching: find.byType(Container)).first,
  );
  expect(box.left, greaterThanOrEqualTo(7.99));
  expect(box.top, greaterThanOrEqualTo(7.99));
  expect(box.right, lessThanOrEqualTo(1172.01));
  expect(box.bottom, lessThanOrEqualTo(952.01));
}

Future<void> _reduceWhileShowing(
  WidgetTester t,
  _Probe probe,
  String message,
) async {
  probe.update(() => probe.reduce = true);
  await t.pump();
  await t.pump();
  expect(_showing(t), hasLength(1));
  final opacity = t.widget<Opacity>(
    find
        .ancestor(of: find.text(message).last, matching: find.byType(Opacity))
        .first,
  );
  expect(opacity.opacity, 1);
  _bounded(t, message);
}

SemanticsNode _accountSemantics(WidgetTester t, String message) {
  final nodes = exposedNodes(t);
  final data = nodes.map((node) => node.getSemanticsData()).toList();
  final ownerLabel = AppStrings.of(t.element(_target('account-command')))
      .text('top.account');
  final diagnostic = [
    'Expected existing cascade trigger owner: $ownerLabel; visual hint: $message',
    for (var i = 0; i < nodes.length; i++)
      'id=${nodes[i].id} label="${data[i].label}" '
          'hint="${data[i].hint}" tooltip="${data[i].tooltip}" '
          'tap=${data[i].hasAction(SemanticsAction.tap)} '
          'labelRunes=${data[i].label.runes.toList()}',
  ].join('\n');
  // The existing cascade root intentionally owns this one accessible trigger
  // and excludes its subtree. This does NOT claim the full visual hint is
  // exposed in AX; its state information is readable in the opened header.
  final owners = nodes
      .where((node) => node.getSemanticsData().label == ownerLabel)
      .toList();
  expect(owners, hasLength(1), reason: diagnostic);
  expect(
    owners.single.getSemanticsData().flagsCollection.isButton,
    isTrue,
    reason: diagnostic,
  );
  expect(
    owners.single.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: diagnostic,
  );
  expect(
    data.where((node) => node.tooltip == message || node.hint == message),
    isEmpty,
    reason:
        'The passive hint must not add a duplicate announcement\n$diagnostic',
  );
  return owners.single;
}

StarBridgeActionButton _action(WidgetTester t, String key) =>
    t.widget<StarBridgeActionButton>(
      find
          .ancestor(
            of: _target(key),
            matching: find.byType(StarBridgeActionButton),
          )
          .first,
    );

void _disabledHistory(WidgetTester t, _Probe probe, String key) {
  expect(_action(t, key).onActivate, isNull);
  final label = t
      .widget<Text>(
        find.descendant(of: _target(key), matching: find.byType(Text)).first,
      )
      .data!;
  final nodes = exposedNodes(t)
      .map((node) => node.getSemanticsData())
      .where((node) => node.label == label)
      .toList();
  expect(nodes, hasLength(1));
  expect(nodes.single.hasAction(SemanticsAction.tap), isFalse);
  expect(probe.port!.reads, hasLength(1));
  expect(find.text('3fo retained original history'), findsOneWidget);
  expect(probe.commands, isEmpty);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '3fo $suite account hover and existing reader owner stay separate',
      (t) async {
        final probe = _Probe(suite);
        final semantics = t.ensureSemantics();
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await _mount(t, probe);
          final message = _message(t, 'account-command');
          final config = t.widget<StarBridgeTooltip>(_hint('account-command'));
          expect(config.excludeFromSemantics, isTrue);
          expect(config.consumeEscape, isFalse);
          _accountSemantics(t, message);
          await mouse.addPointer(location: const Offset(10, 900));
          await _hover(t, mouse, 'account-command');
          _accountSemantics(t, message);
          _bounded(t, message);
          await _reduceWhileShowing(t, probe, message);
          await mouse.moveTo(const Offset(10, 900));
          await _frames(t);
          expect(_showing(t), isEmpty);
          await _hover(t, mouse, 'account-command');
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await _frames(t);
          expect(_showing(t), isEmpty);
          expect(probe.commands, isEmpty);
          expect(nativeViewportMenus.value, 0);
          await mouse.moveTo(const Offset(10, 900));
          await _frames(t);
          final owner = _accountSemantics(t, message);
          t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
            owner.id,
            SemanticsAction.tap,
          );
          await _frames(t, 6);
          expect(nativeViewportMenus.value, 1);
          final exposed = exposedNodes(t)
              .map((node) => node.getSemanticsData().label)
              .toList();
          for (final statusKey in [
            'account-app-presence',
            'account-game-presence',
          ]) {
            final status = t.widget<Text>(_target(statusKey)).data!;
            expect(status, isNotEmpty);
            expect(
              exposed.any((label) => label.contains(status)),
              isTrue,
              reason:
                  'Existing opened account header must expose $statusKey: $status',
            );
          }
          expect(
            probe.commands,
            isEmpty,
            reason: 'Reader opening is not a business command',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(nativeViewportMenus.value, 0);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await probe.clean(t);
          semantics.dispose();
        }
      },
    );

    testWidgets('3fo $suite account touch hint and original menu callbacks', (
      t,
    ) async {
      final probe = _Probe(suite);
      try {
        await _mount(t, probe);
        final touch = await t.startGesture(
          t.getCenter(_target('account-command')),
        );
        await t.pump(const Duration(milliseconds: 600));
        await _frames(t);
        expect(_showing(t), hasLength(1));
        expect(probe.commands, isEmpty);
        expect(nativeViewportMenus.value, 0);
        await touch.up();
        await _frames(t);
        expect(
          nativeViewportMenus.value,
          0,
          reason: 'Long press is not a menu tap',
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await _frames(t);
        await t.tap(_target('account-command'));
        await _frames(t, 6);
        expect(nativeViewportMenus.value, 1);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(
          nativeViewportMenus.value,
          0,
          reason: 'A single Esc reaches the existing menu',
        );
        expect(probe.commands, isEmpty);
        await t.tap(_target('account-command'));
        await _frames(t, 6);
        await t.tap(_target('account-menu-sample'));
        await _frames(t);
        expect(probe.commands, [
          (MenuFixture.descriptor.id, InteractionSource.pointer),
        ]);
        expect(nativeViewportMenus.value, 0);
        expect(t.takeException(), isNull);
      } finally {
        await probe.clean(t);
      }
    });

    testWidgets(
      '3fo $suite hovered account hint passes same Esc to parent dialog',
      (t) async {
        final probe = _Probe(suite, accountDialog: true);
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await _mount(t, probe);
          await mouse.addPointer(location: const Offset(10, 900));
          await _hover(t, mouse, 'account-command');
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(probe.closed, isTrue);
          expect(find.byType(Dialog), findsNothing);
          expect(_showing(t), isEmpty);
          expect(probe.commands, isEmpty);
          expect(nativeViewportMenus.value, 0);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await probe.clean(t);
        }
      },
    );

    for (final kind in ['export', 'clear']) {
      final key = 'history-$kind';
      testWidgets(
        '3fo $suite missing $kind port hover and same-Esc dialog exit',
        (t) async {
          final probe = _Probe(suite, history: true);
          final semantics = t.ensureSemantics();
          final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
          try {
            await _mount(t, probe);
            _disabledHistory(t, probe, key);
            expect(
              t.widget<StarBridgeTooltip>(_hint(key)).consumeEscape,
              isFalse,
            );
            await mouse.addPointer(location: const Offset(10, 900));
            await _hover(t, mouse, key);
            final message = _message(t, key);
            _bounded(t, message);
            await _reduceWhileShowing(t, probe, message);
            _disabledHistory(t, probe, key);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
            expect(probe.closed, isTrue);
            expect(find.byType(LocalEventHistoryDialog), findsNothing);
            expect(_showing(t), isEmpty);
            expect(probe.port!.reads, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await probe.clean(t);
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '3fo $suite missing $kind port touch hint never becomes a command',
        (t) async {
          final probe = _Probe(suite, history: true);
          final semantics = t.ensureSemantics();
          try {
            await _mount(t, probe);
            _disabledHistory(t, probe, key);
            final touch = await t.startGesture(t.getCenter(_target(key)));
            await t.pump(const Duration(milliseconds: 600));
            await _frames(t);
            expect(_showing(t), hasLength(1));
            expect(_showing(t).single.widget.message, _message(t, key));
            _disabledHistory(t, probe, key);
            await touch.up();
            await _frames(t);
            await t.tapAt(t.getCenter(_target(key)));
            await _frames(t);
            _disabledHistory(t, probe, key);
            expect(probe.closed, isFalse);
            expect(find.byType(LocalEventHistoryDialog), findsOneWidget);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
            expect(probe.closed, isTrue);
            expect(probe.port!.reads, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await probe.clean(t);
            semantics.dispose();
          }
        },
      );
    }
  }
}
