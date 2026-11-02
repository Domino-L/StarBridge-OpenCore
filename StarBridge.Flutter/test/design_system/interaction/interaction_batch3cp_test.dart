import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_tool.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_preferences.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_browser_tabs_test.dart'
    show BrowserFake, workspace, flush;
import '../../features/friends/social_layout_test.dart' show size, loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

class Harness extends StatefulWidget {
  const Harness(this.native, this.work, this.suite, {super.key});
  final BrowserFake native;
  final MenuWorkspaceController work;
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  bool reduce = false, light = false, visible = true;
  bool scopeActive = true;
  VoidCallback? otherOpen, otherClose;
  MenuBrowserPreferences preferences = const MenuBrowserPreferences();
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    NativeViewportMenu(
      builder: (open, close) {
        otherOpen = open;
        otherClose = close;
        return NativeViewportScope(
          active: scopeActive,
          child: visible
              ? MenuBrowserTool(
                  call: widget.native.call,
                  workspace: widget.work,
                  preferences: preferences,
                )
              : const SizedBox(),
        );
      },
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Finder key(String value) => find.byKey(ValueKey(value));
TextField field(WidgetTester t) => t.widget<TextField>(key('browser-address'));
Future<HarnessState> mount(
  WidgetTester t,
  BrowserFake native,
  MenuWorkspaceController work,
  InteractionSuite suite,
) async {
  size(t, const Size(900, 650));
  final h = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(native, work, suite, key: h));
  await flush(t);
  return h.currentState!;
}

Future<void> hit(WidgetTester t, Finder target, String input) async {
  await t.ensureVisible(target);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'reader') {
    final node = t.getSemantics(
      find
          .ancestor(
            of: target,
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.onTap != null,
            ),
          )
          .first,
    );
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    final button = t.widget<IconButton>(target);
    button.focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(
      input == 'space'
          ? LogicalKeyboardKey.space
          : input == 'numpad'
          ? LogicalKeyboardKey.numpadEnter
          : LogicalKeyboardKey.enter,
    );
  }
  await flush(t);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader', 'space', 'numpad']) {
      testWidgets('$suite $input native tab maps/gates and measured geometry', (
        t,
      ) async {
        final native = BrowserFake(), work = workspace();
        await mount(t, native, work, suite);
        expect(t.getSize(key('browser-new-tab')), const Size(48, 48));
        expect(t.getSize(key('browser-close-t1')), const Size(48, 48));
        expect(
          t.getRect(key('browser-address')),
          const Rect.fromLTRB(8, 89, 831.5, 133),
        );
        expect(native.calls.lastWhere((c) => c.$1 == 'browserBounds').$2, {
          'visible': true,
          'x': 0.0,
          'y': 134.0,
          'width': 900.0,
          'height': 516.0,
          'opacity': 1.0,
          'occlusions': [],
        });
        await hit(t, key('browser-close-t2'), input);
        expect(native.calls.singleWhere((c) => c.$1 == 'browserCloseTab').$2, {
          'tabId': 't2',
          'url': 'https://www.bing.com/',
        });
        expect(native.active, 't1');
        expect(key('browser-tab-t2'), findsNothing);
        final reply = native.pendingAction = Completer<Object?>();
        await hit(t, key('browser-new-tab'), input);
        expect(native.calls.singleWhere((c) => c.$1 == 'browserNewTab').$2, {
          'url': 'https://www.bing.com/',
        });
        expect(t.widget<IconButton>(key('browser-new-tab')).onPressed, isNull);
        expect(t.widget<IconButton>(key('browser-close-t1')).onPressed, isNull);
        await t.tap(key('browser-new-tab'), warnIfMissed: false);
        await flush(t);
        expect(
          native.calls.where((c) => c.$1 == 'browserNewTab'),
          hasLength(1),
        );
        reply.complete();
        await flush(t);
        expect(
          t.widget<IconButton>(key('browser-new-tab')).onPressed,
          isNotNull,
        );
        await t.pumpWidget(const SizedBox());
        work.dispose();
      });
    }
    for (final outcome in ['success', 'failure']) {
      for (final edit in [
        'newValue',
        'sameValueAgain',
        'selectionOnly',
        'noEdit',
      ]) {
        testWidgets(
          '$suite navigate $outcome $edit preserves newest draft/IME',
          (t) async {
            final native = BrowserFake(), work = workspace();
            await mount(t, native, work, suite);
            await t.enterText(key('browser-address'), 'first.test');
            final reply = native.pendingAction = Completer<Object?>();
            await t.tap(find.text('访问'));
            await flush(t);
            expect(
              native.calls.singleWhere((c) => c.$1 == 'browserNavigate').$2,
              {'tabId': 't1', 'url': 'https://first.test'},
            );
            var latest = field(t).controller!.value;
            if (edit != 'noEdit') {
              if (edit != 'selectionOnly') {
                await t.enterText(key('browser-address'), 'later input');
              }
              latest = TextEditingValue(
                text: edit == 'newValue' ? 'later input' : 'first.test',
                selection: const TextSelection(baseOffset: 2, extentOffset: 6),
                composing: const TextRange(start: 0, end: 6),
              );
              t.testTextInput.updateEditingValue(latest);
              await t.pump();
              expect(field(t).controller!.value, latest);
            }
            if (outcome == 'success') {
              native.tabs.first['url'] = 'https://first.test';
              reply.complete();
            } else {
              reply.completeError(PlatformException(code: 'fixture-failure'));
            }
            await flush(t);
            if (edit != 'noEdit' || outcome == 'failure') {
              expect(field(t).controller!.value, latest);
              expect(field(t).focusNode!.hasFocus, true);
            } else {
              expect(field(t).controller!.text, 'https://first.test');
              expect(field(t).focusNode!.hasFocus, false);
            }
            expect(
              native.calls.where((c) => c.$1 == 'browserNavigate'),
              hasLength(1),
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            work.dispose();
          },
        );
      }
    }
    testWidgets(
      '$suite live suite/reduce retains actual editor composition and focus',
      (t) async {
        final native = BrowserFake(), work = workspace();
        final h = await mount(t, native, work, suite);
        final editor = t.element(key('browser-address'));
        final controller = field(t).controller, focus = field(t).focusNode;
        await t.enterText(key('browser-address'), '星际 citizen');
        const value = TextEditingValue(
          text: '星际 citizen',
          selection: TextSelection(baseOffset: 1, extentOffset: 7),
          composing: TextRange(start: 0, end: 7),
        );
        t.testTextInput.updateEditingValue(value);
        await t.pump();
        for (final next in InteractionSuite.values) {
          h.change(() {
            h.suite = next;
            h.reduce = true;
            h.light = true;
          });
          await flush(t);
          expect(t.element(key('browser-address')), same(editor));
          expect(field(t).controller, same(controller));
          expect(field(t).focusNode, same(focus));
          expect(controller!.value, value);
          expect(focus!.hasFocus, true);
          expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
          expect(find.byType(StarBridgeNativeIconAction), findsNWidgets(3));
        }
        await t.pumpWidget(const SizedBox());
        work.dispose();
      },
    );
    for (final outcome in ['success', 'failure']) {
      for (final leaving in ['hidden', 'disposed']) {
        testWidgets(
          '$suite pending navigation $outcome after $leaving is not replayed',
          (t) async {
            final native = BrowserFake(), work = workspace();
            final h = await mount(t, native, work, suite);
            await t.enterText(key('browser-address'), 'submitted.test');
            final reply = native.pendingAction = Completer<Object?>();
            await t.tap(find.text('访问'));
            await flush(t);
            await t.enterText(key('browser-address'), 'keep newest draft');
            if (leaving == 'hidden') {
              work.setVisible(false);
            } else {
              h.change(() => h.visible = false);
            }
            await flush(t);
            final afterLeave = native.calls.length;
            if (outcome == 'success') {
              native.tabs.first['url'] = 'https://submitted.test';
              reply.complete();
            } else {
              reply.completeError(PlatformException(code: 'late-failure'));
            }
            await flush(t);
            expect(
              native.calls
                  .lastWhere((c) => c.$1 == 'browserBounds')
                  .$2['visible'],
              false,
            );
            if (leaving == 'disposed') {
              expect(native.calls.length, afterLeave);
            } else {
              expect(field(t).controller!.text, 'keep newest draft');
              work.setVisible(true);
              await flush(t);
              expect(field(t).controller!.text, 'keep newest draft');
            }
            expect(
              native.calls.where((c) => c.$1 == 'browserNavigate'),
              hasLength(1),
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            work.dispose();
          },
        );
      }
    }
    testWidgets('$suite failed navigation retries only explicit latest draft', (
      t,
    ) async {
      final native = BrowserFake(), work = workspace();
      await mount(t, native, work, suite);
      await t.enterText(key('browser-address'), 'first.test');
      native.failure = PlatformException(code: 'menu.browser_tab_stale');
      await t.tap(find.text('访问'));
      await flush(t);
      expect(find.text('标签页已变化，请在当前页面重新操作。'), findsOneWidget);
      expect(
        native.calls.where((c) => c.$1 == 'browserNavigate'),
        hasLength(1),
      );
      await t.enterText(key('browser-address'), 'second.test');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await flush(t);
      expect(native.calls.lastWhere((c) => c.$1 == 'browserNavigate').$2, {
        'tabId': 't1',
        'url': 'https://second.test',
      });
      expect(
        native.calls.where((c) => c.$1 == 'browserNavigate'),
        hasLength(2),
      );
      expect(field(t).controller!.text, 'https://second.test');
      await t.pumpWidget(const SizedBox());
      work.dispose();
    });
  }
  testWidgets(
    'shared icon keeps its owned focus across all suites without refocus',
    (t) async {
      final calls = <InteractionSource>[];
      Widget app(InteractionSuite suite) => scopedApp(
        StarBridgeIconAction(
          label: 'shared-icon',
          controlKey: const Key('shared-control'),
          onActivate: calls.add,
          icon: const Icon(Icons.add),
        ),
        suite,
      );
      await t.pumpWidget(app(InteractionSuite.standard));
      await t.pumpAndSettle();
      final focus = t
          .widget<IconButton>(find.byKey(const Key('shared-control')))
          .focusNode!;
      focus.requestFocus();
      await t.pump();
      for (final suite in [
        ...InteractionSuite.values,
        InteractionSuite.standard,
      ]) {
        await t.pumpWidget(app(suite));
        await flush(t);
        expect(focus.hasFocus, true);
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await flush(t);
        expect(focus.hasFocus, true);
      }
      expect(calls, List.filled(5, InteractionSource.keyboard));
      await t.pumpWidget(const SizedBox());
    },
  );
}
