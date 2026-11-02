import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/app/shell/widgets/window_controls.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_caption_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/styles/window_caption_palette.dart';
import 'package:starbridge_flutter/platform/window/window_chrome_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/friends_window/friends_window_app_test.dart' show snapshot;
import '../../app/social_windows/social_window_test.dart' show native;
import '../../features/friends/social_layout_test.dart' show size, loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder caption(String label) => find.byWidgetPredicate(
  (w) => w is StarBridgeCaptionAction && w.label == label,
);
Finder button(Finder target) =>
    find.descendant(of: target, matching: find.byType(IconButton));
EffectHostState effect(WidgetTester t, Finder target) =>
    t.state(find.descendant(of: target, matching: find.byType(EffectHost)));
bool playing(EffectHostState fx) => TransientEffect.values.any(fx.isPlaying);

Future<void> activate(WidgetTester t, Finder target, String source) async {
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'reader') {
    final node = t.getSemantics(
      find
          .descendant(
            of: target,
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.onTap != null,
            ),
          )
          .first,
    );
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    t.widget<IconButton>(button(target)).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(
      source == 'space' ? LogicalKeyboardKey.space : LogicalKeyboardKey.enter,
    );
  }
  await t.pump();
}

class Chrome implements WindowChromePort {
  final maximized = ValueNotifier(false);
  final calls = <String>[];
  final sources = <InteractionSource>[];
  void record(String command) {
    calls.add(command);
    sources.add(currentStarBridgeActivationSource);
  }

  @override
  ValueListenable<bool> get isMaximized => maximized;
  @override
  Future<void> beginDrag() async => record('drag');
  @override
  Future<void> close() async => record('close');
  @override
  Future<void> minimize() async => record('minimize');
  @override
  Future<void> toggleMaximize() async => record('toggleMaximize');
  @override
  Future<void> setIconVariant(String variant) async =>
      record('icon:$variant');
}

class Harness extends StatefulWidget {
  const Harness(this.suite, this.action, {super.key});
  final InteractionSuite suite;
  final ValueChanged<InteractionSource> action;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  bool reduce = false, enabled = true, light = false;
  void change(VoidCallback update) => setState(update);
  static final style = IconButton.styleFrom(
    shape: const RoundedRectangleBorder(),
    foregroundColor: Colors.white,
    hoverColor: WindowCaptionPalette.closeHover,
  ).copyWith(side: const WidgetStatePropertyAll(BorderSide.none));
  @override
  Widget build(BuildContext context) => scopedApp(
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 34,
          child: RepaintBoundary(
            key: const Key('caption-pixels'),
            child: StarBridgeCaptionAction(
              label: 'caption',
              icon: const Icon(Icons.close),
              style: style,
              padding: EdgeInsets.zero,
              iconSize: 15,
              onActivate: enabled ? widget.action : null,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          height: 34,
          child: RepaintBoundary(
            key: const Key('reference-pixels'),
            child: IconButton(
              key: const Key('native-reference'),
              tooltip: 'reference',
              padding: EdgeInsets.zero,
              iconSize: 15,
              style: style,
              onPressed: () {},
              icon: const Icon(Icons.close),
            ),
          ),
        ),
      ],
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'space', 'reader']) {
      testWidgets(
        '$suite caption $source preserves geometry and exact callback',
        (t) async {
          final calls = <InteractionSource>[];
          final zoneSources = <InteractionSource>[];
          await t.pumpWidget(
            Harness(suite, (source) {
              calls.add(source);
              zoneSources.add(currentStarBridgeActivationSource);
            }),
          );
          await t.pumpAndSettle();
          final target = caption('caption');
          expect(t.getSize(target), const Size(44, 34));
          expect(
            t.getSize(button(target)),
            t.getSize(find.byKey(const Key('native-reference'))),
          );
          for (var i = 0; i < 5; i++) {
            await activate(t, target, source);
            expect(
              calls.length,
              i + 1,
            ); // No rapid-click coalescing or queuing.
            if (source == 'keyboard' || source == 'space') {
              expect(
                t.widget<IconButton>(button(target)).focusNode!.hasFocus,
                true,
              );
            }
            expect(
              playing(effect(t, target)),
              source == 'pointer' && suite != InteractionSuite.standard,
            );
          }
          final expected = source == 'pointer'
              ? InteractionSource.pointer
              : InteractionSource.keyboard;
          expect(calls, everyElement(expected));
          expect(zoneSources, calls);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets('$suite live reduce/disable retains focus and stops feedback', (
      t,
    ) async {
      final calls = <InteractionSource>[];
      final key = GlobalKey<HarnessState>();
      await t.pumpWidget(Harness(suite, calls.add, key: key));
      await t.pumpAndSettle();
      final target = caption('caption');
      final focus = t.widget<IconButton>(button(target)).focusNode!;
      focus.requestFocus();
      await t.pump();
      await t.tap(target);
      await t.pump(const Duration(milliseconds: 20));
      key.currentState!.change(() {
        key.currentState!.reduce = true;
        key.currentState!.light = true;
      });
      await t.pump();
      await t.pump();
      expect(playing(effect(t, target)), false);
      expect(t.widget<IconButton>(button(target)).focusNode, same(focus));
      expect(focus.hasFocus, true);
      expect(
        t.widget<IconButton>(button(target)).style!.animationDuration,
        Duration.zero,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.last, InteractionSource.keyboard);
      key.currentState!.change(() => key.currentState!.enabled = false);
      await t.pumpAndSettle();
      final count = calls.length;
      await t.tap(target, warnIfMissed: false);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.length, count);
      expect(
        t
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        false,
      );
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite actual main controls keep original command owner and state',
      (t) async {
        final chrome = Chrome();
        await t.pumpWidget(
          scopedApp(WindowControls(windowChrome: chrome), suite),
        );
        await t.pumpAndSettle();
        for (final entry in {
          '最小化': 'minimize',
          '最大化': 'toggleMaximize',
          '关闭': 'close',
        }.entries) {
          await t.tap(caption(entry.key));
          await t.pump();
          expect(chrome.calls.last, entry.value);
        }
        expect(caption('最大化'), findsOneWidget); // No optimistic state mutation.
        chrome.maximized.value = true;
        await t.pump();
        expect(caption('还原'), findsOneWidget);
        await activate(t, caption('还原'), 'keyboard');
        expect(chrome.calls.last, 'toggleMaximize');
        expect(chrome.sources.last, InteractionSource.keyboard);
        final originals = t
            .widgetList<StarBridgeCaptionAction>(
              find.byType(StarBridgeCaptionAction),
            )
            .toList();
        final sizes = [for (final w in originals) t.getSize(caption(w.label))];
        await t.pumpWidget(
          scopedApp(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final w in originals)
                  IconButton(style: w.style, icon: w.icon, onPressed: () {}),
              ],
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        expect([
          for (final f in find.byType(IconButton).evaluate())
            t.getSize(find.byElementPredicate((e) => identical(e, f))),
        ], sizes);
        await t.pumpWidget(const SizedBox());
        chrome.maximized.dispose();
      },
    );
    for (final title in ['聊天', '通知']) {
      testWidgets(
        '$suite $title native 132 DIP caption bounds and string commands',
        (t) async {
          size(t, const Size(392, 400));
          final calls = <String>[];
          await t.pumpWidget(
            scopedApp(
              SocialWindowFrame(
                title: title,
                control: calls.add,
                child: const SizedBox(),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final targets = find.byType(StarBridgeCaptionAction);
          expect(targets, findsNWidgets(3));
          expect(t.getRect(targets.first), const Rect.fromLTWH(260, 0, 44, 34));
          expect(t.getRect(targets.last), const Rect.fromLTWH(348, 0, 44, 34));
          for (final entry in {
            '最小化': 'minimize',
            '最大化': 'toggleMaximize',
            '关闭$title窗口': 'close',
          }.entries) {
            await t.tap(caption(entry.key));
            await t.pump();
            expect(calls.last, entry.value);
          }
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final outcome in ['success', 'false', 'error']) {
      testWidgets(
        '$suite friends caption independent of pending messages: $outcome',
        (t) async {
          const channel = MethodChannel('starbridge/friends-surface');
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          final calls = <MethodCall>[];
          final pending = Completer<bool>();
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'ready') {
              return {
                ...snapshot(),
                'presentation': {'interactionStyle': suite.name},
              };
            }
            if (call.method == 'action') return pending.future;
            return true;
          });
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
          size(t, const Size(392, 640));
          await t.pumpWidget(const FriendsWindowApp());
          await t.pumpAndSettle();
          await t.tap(find.text('打开最近聊天'));
          await t.pump();
          final action = calls
              .singleWhere((c) => c.method == 'action')
              .arguments;
          expect(action, {
            'opening': 1,
            'revision': 1,
            'scope': 'friends1',
            'action': 'messages',
            'key': '',
            'value': '',
            'motionSource': 'pointer',
          });
          await t.tap(find.text('打开最近聊天'), warnIfMissed: false);
          await t.pump();
          expect(calls.where((c) => c.method == 'action'), hasLength(1));
          await t.tap(caption('关闭好友窗口'));
          await t.pump();
          expect(
            calls.lastWhere((c) => c.method == 'windowControl').arguments,
            'close',
          );
          await native(channel.name, 'windowState', true);
          await t.pump();
          expect(caption('还原'), findsOneWidget);
          if (outcome == 'error') {
            pending.completeError(PlatformException(code: 'fixture'));
          } else {
            pending.complete(outcome == 'success');
          }
          await t.pumpAndSettle();
          expect(
            find.text('操作未确认，请刷新列表核对后再试。'),
            outcome == 'success' ? findsNothing : findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final leaving in ['newOpening', 'dispose']) {
      testWidgets('$suite friends ignores old failure after $leaving', (
        t,
      ) async {
        const channel = MethodChannel('starbridge/friends-surface');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final pending = Completer<bool>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'ready') {
            return {
              ...snapshot(),
              'presentation': {'interactionStyle': suite.name},
            };
          }
          if (call.method == 'action') return pending.future;
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        size(t, const Size(392, 640));
        await t.pumpWidget(const FriendsWindowApp());
        await t.pumpAndSettle();
        await t.tap(find.text('打开最近聊天'));
        await t.pump();
        if (leaving == 'dispose') {
          await t.pumpWidget(const SizedBox());
        } else {
          await native(channel.name, 'snapshot', {
            ...snapshot(opening: 2, name: '新窗口'),
            'presentation': {'interactionStyle': suite.name},
          });
          await t.pump();
        }
        pending.completeError(PlatformException(code: 'old-response'));
        await t.pumpAndSettle();
        expect(find.text('操作未确认，请刷新列表核对后再试。'), findsNothing);
        if (leaving == 'newOpening') expect(find.text('新窗口'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
