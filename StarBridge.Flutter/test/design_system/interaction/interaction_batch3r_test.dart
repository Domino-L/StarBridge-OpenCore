import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_workspace.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_pane.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/app/runtime/example_scene_control.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../../features/communities/community_chat_controller_test.dart'
    show FakeChat;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, route, dialogAction;
import 'interaction_batch3m_test.dart' show activate;
import 'interaction_batch3b_test.dart' show semanticTap;
import '../../features/communities/community_holo_test_support.dart';

class Harness extends StatefulWidget {
  const Harness(this.port, this.controller, this.suite, {super.key});
  final FakeChat port;
  final CommunityChatController controller;
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  final panel = GlobalKey<CommunityChatPanelState>();
  late var controller = widget.controller;
  bool reduce = false;
  bool show = true;
  bool? result;
  int backs = 0;
  Completer<void>? held;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    Column(
      children: [
        StarBridgeActionButton(
          key: const Key('guard'),
          onActivate: (_) async {
            if (held != null) await held!.future;
            result = await panel.currentState!.confirmLeave();
          },
          child: const Text('离开保护'),
        ),
        Expanded(
          child: !show
              ? const Text('已离开')
              : CommunityChatPanel(
                  key: panel,
                  port: widget.port,
                  controller: controller,
                  targetRef: controller.targetRef,
                  name: '合成组织',
                  onBack: () => backs++,
                ),
        ),
      ],
    ),
    widget.suite,
    reduce: reduce,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  InteractionSuite suite, {
  GlobalKey? frame,
}) async {
  size(t, const Size(1100, 900));
  final port = FakeChat();
  final controller = CommunityChatController(port, 'a' * 32, localEcho: true);
  addTearDown(controller.dispose);
  addTearDown(port.changes.close);
  final key = GlobalKey<HarnessState>();
  final child = Harness(port, controller, suite, key: key);
  await t.pumpWidget(
    frame == null ? child : RepaintBoundary(key: frame, child: child),
  );
  await t.pumpAndSettle();
  controller.updateDraft('需要保护的草稿');
  await t.pumpAndSettle();
  return key.currentState!;
}

Finder primary(String route) => find.byWidgetPredicate(
  (widget) => widget is ShellNavigationItem && widget.key == ValueKey(route),
);

Future<void> back(WidgetTester t, String source) async {
  final target = find.byKey(const Key('community-chat-back'));
  if (source == 'reader') {
    await semanticTap(t, find.bySemanticsLabel('返回组织资料'));
  } else if (source == 'keyboard') {
    final icon = find.descendant(
      of: target,
      matching: find.byType(StandardIcon),
    );
    Focus.of(t.element(icon)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(target);
  }
  await t.pump();
  await t.pump();
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3R'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3r');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  test(
    'legacy void callback keeps origin through await and expires afterwards',
    () async {
      final gate = Completer<void>();
      InteractionSource? observed;
      late InteractionSource Function() later;
      Future<void> legacyWork() async {
        later = Zone.current.bindCallback(
          () => currentStarBridgeActivationSource,
        );
        await gate.future;
        observed = currentStarBridgeActivationSource;
      }

      final VoidCallback legacy = legacyWork;
      final pending = runStarBridgeActivation<void>(
        InteractionSource.keyboard,
        legacy,
      );
      expect(observed, isNull);
      gate.complete();
      await pending;
      expect(observed, InteractionSource.keyboard);
      expect(later(), InteractionSource.pointer);
      expect(currentStarBridgeActivationSource, InteractionSource.pointer);
    },
  );
  test(
    'concurrent and nested commands retain their own origin and error cleanup',
    () async {
      final gate = Completer<void>();
      final first = runStarBridgeActivation(
        InteractionSource.keyboard,
        () async {
          await gate.future;
          return currentStarBridgeActivationSource;
        },
      );
      final second = runStarBridgeActivation(
        InteractionSource.pointer,
        () async {
          await runStarBridgeActivation(InteractionSource.keyboard, () async {
            expect(
              currentStarBridgeActivationSource,
              InteractionSource.keyboard,
            );
          });
          expect(currentStarBridgeActivationSource, InteractionSource.pointer);
          gate.complete();
          return currentStarBridgeActivationSource;
        },
      );
      expect(await first, InteractionSource.keyboard);
      expect(await second, InteractionSource.pointer);
      await expectLater(
        runStarBridgeActivation<void>(
          InteractionSource.keyboard,
          () => throw StateError('test'),
        ),
        throwsStateError,
      );
      expect(currentStarBridgeActivationSource, InteractionSource.pointer);
    },
  );
  for (final suite in InteractionSuite.values) {
    for (final width in [700.0, 1100.0]) {
      testWidgets(
        '$suite online members $width preserves draft and keyboard origin',
        (t) async {
          size(t, Size(width, 900));
          final port = ExampleCommunities();
          addTearDown(port.close);
          await t.pumpWidget(
            scopedApp(
              CommunityWorkspaceView(
                port: port,
                targetRef: '00000000000000000000000000000001',
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await activate(
            t,
            find.byKey(const ValueKey('community-section-chat')),
            'keyboard',
          );
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('community-chat-input')),
            '在线名单不应清空草稿',
          );
          await t.pumpAndSettle();
          final editorFinder = find.descendant(
            of: find.byKey(const Key('community-chat-input')),
            matching: find.byType(EditableText),
          );
          final editor = t.state<EditableTextState>(editorFinder);
          if (width >= 900) {
            final refresh = find.byKey(
              const Key('community-workspace-refresh'),
            );
            final refreshIcon = find.descendant(
              of: refresh,
              matching: find.byType(StandardIcon),
            );
            Focus.of(t.element(refreshIcon)).requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
            await t.pump();
            await t.pump();
            expect(route(t).animation!.value, 1);
            await activate(t, dialogAction('继续编辑'), 'keyboard');
            await t.pumpAndSettle();
            expect(t.state<EditableTextState>(editorFinder), same(editor));
            expect(editor.widget.controller.text, '在线名单不应清空草稿');
          }
          final toggle = find.byKey(const Key('community-online-toggle'));
          Future<void> toggleWithKeyboard() async {
            final icon = find.descendant(
              of: toggle,
              matching: find.byType(StandardIcon),
            );
            Focus.of(t.element(icon)).requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
            await t.pump();
            await t.pump();
          }

          if (width < 900) {
            await toggleWithKeyboard();
            expect(route(t).animation!.value, 1);
            await activate(
              t,
              find.byKey(const Key('community-online-close')),
              'keyboard',
            );
            expect(find.byType(AlertDialog), findsNothing);
            await t.pumpAndSettle();
            await t.tap(toggle);
            await t.pump();
            expect(route(t).animation!.value, lessThan(1));
            await t.pumpAndSettle();
          } else {
            await toggleWithKeyboard();
            expect(
              find.byKey(const Key('community-online-members')),
              findsNothing,
            );
            await toggleWithKeyboard();
            await t.pumpAndSettle();
          }
          await activate(
            t,
            find.byKey(const Key('community-all-members')),
            'keyboard',
          );
          expect(route(t).animation!.value, 1);
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await activate(t, dialogAction('继续编辑'), 'keyboard');
          await t.pumpAndSettle();
          expect(t.state<EditableTextState>(editorFinder), same(editor));
          expect(editor.widget.controller.text, '在线名单不应清空草稿');
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets('$suite same destination retains editor when origin changes', (
      t,
    ) async {
      size(t, const Size(900, 600));
      var interaction = NavigationInteraction.keyboard;
      late StateSetter rebuild;
      final destination = FeatureDescriptor(
        id: 'retained-editor',
        route: '/retained-editor',
        labelKey: 'navigation.communities',
        descriptionKey: '',
        icon: StarBridgeIconSemantic.community,
        navigationRegion: NavigationRegion.primary,
        order: 0,
        buildDestination: (_) => const TextField(key: Key('retained-editor')),
      );
      await t.pumpWidget(
        scopedApp(
          StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return ShellWorkspace(
                selected: destination,
                interaction: interaction,
              );
            },
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('retained-editor')), '保留输入与焦点');
      final editor = t.state<EditableTextState>(find.byType(EditableText));
      for (final origin in [
        NavigationInteraction.pointer,
        NavigationInteraction.keyboard,
      ]) {
        rebuild(() => interaction = origin);
        await t.pumpAndSettle();
        expect(
          t.state<EditableTextState>(find.byType(EditableText)),
          same(editor),
        );
        expect(editor.widget.controller.text, '保留输入与焦点');
        expect(editor.widget.focusNode.hasFocus, true);
      }
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source chat back cancel, block barrier and explicit discard',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final frame = GlobalKey();
            final state = await mount(t, suite, frame: frame);
            await back(t, source);
            expect(
              route(t).animation!.value,
              source == 'pointer' ? lessThan(1) : 1,
            );
            await t.pumpAndSettle();
            if (source == 'pointer') {
              await capture(t, frame, '${suite.name}-leave');
            }
            await t.tapAt(const Offset(5, 5));
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(find.byType(AlertDialog), findsOneWidget);
            await activate(t, dialogAction('继续编辑'), source);
            await t.pumpAndSettle();
            expect(state.backs, 0);
            expect(state.controller.draft, '需要保护的草稿');
            await back(t, source);
            await t.pumpAndSettle();
            state.change(() => state.reduce = true);
            await t.pump();
            await t.pump();
            await activate(t, dialogAction('丢弃草稿并返回'), 'keyboard');
            expect(find.byType(AlertDialog), findsNothing);
            expect(state.backs, 1);
            expect(state.controller.draft, isEmpty);
            expect(state.widget.port.sends, isEmpty);
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite invalidation removes only its leave route below an independent window',
      (t) async {
        final state = await mount(t, suite);
        await activate(t, find.byKey(const Key('guard')), 'keyboard');
        await t.pumpAndSettle();
        unawaited(
          showDialog<void>(
            context: state.panel.currentContext!,
            builder: (context) => AlertDialog(
              title: const Text('独立窗口'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭独立窗口'),
                ),
              ],
            ),
          ),
        );
        await t.pumpAndSettle();
        state.widget.port.changes.add(null);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('独立窗口'), findsOneWidget);
        expect(state.result, false);
        expect(state.backs, 0);
        await t.tap(find.text('关闭独立窗口'));
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite unmount cancels owned leave and keeps retained model draft',
      (t) async {
        final state = await mount(t, suite);
        await activate(t, find.byKey(const Key('guard')), 'keyboard');
        state.change(() => state.show = false);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(state.result, false);
        expect(state.controller.draft, '需要保护的草稿');
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite sending blocks leave and unknown response cannot be resent',
      (t) async {
        final state = await mount(t, suite);
        final port = state.widget.port;
        port.heldSend = Completer();
        final sending = state.controller.submit();
        await t.pump();
        expect(
          t
              .widget<StarBridgeIconAction>(
                find.byType(StarBridgeIconAction).first,
              )
              .onActivate,
          isNull,
        );
        expect(await state.panel.currentState!.confirmLeave(), false);
        expect(find.byType(AlertDialog), findsNothing);
        port.heldSend!.complete(
          const CommunityChatSendOutcome('unknown', error: 'outcomeUnknown'),
        );
        await sending;
        await t.pumpAndSettle();
        await back(t, 'keyboard');
        await t.pumpAndSettle();
        await activate(t, dialogAction('继续编辑'), 'keyboard');
        await t.pumpAndSettle();
        await state.controller.submit();
        expect(port.sends, hasLength(1));
        expect(state.controller.sendUncertain, true);
        expect(state.backs, 0);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite real shell, shortcuts and tabs retain keyboard guard origin',
      (t) async {
        size(t, const Size(1600, 1000));
        final composition = AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          communitiesPortFactory: ExampleCommunities.new,
        );
        addTearDown(composition.dispose);
        final frame = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: scopedApp(
              StarBridgeShell(
                composition: composition,
                exampleSceneControl: const ExampleSceneControl.hidden(),
              ),
              suite,
            ),
          ),
        );
        await t.pumpAndSettle();
        await activate(t, primary('/communities'), 'pointer');
        await t.pumpAndSettle();
        final module = composition.communities;
        await activate(
          t,
          find.byKey(ValueKey('community-shortcut-${module.joined.last.key}')),
          'keyboard',
        );
        await t.pumpAndSettle();
        expect(
          t
              .widget<StarBridgeNavigationPane>(
                find.byType(StarBridgeNavigationPane),
              )
              .interaction,
          NavigationInteraction.keyboard,
        );
        await enterCommunitySection(t);
        await activate(
          t,
          find.byKey(const ValueKey('community-section-chat')),
          'keyboard',
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('community-chat-input')),
          '真实组合草稿',
        );
        await t.pumpAndSettle();
        await activate(
          t,
          find.byKey(const ValueKey('community-section-members')),
          'keyboard',
        );
        expect(route(t).animation!.value, 1);
        await activate(t, dialogAction('继续编辑'), 'keyboard');
        await t.pumpAndSettle();
        final before = module.selected;
        await activate(t, primary('/communities'), 'pointer');
        await t.pumpAndSettle();
        await activate(t, dialogAction('继续编辑'), 'keyboard');
        await t.pumpAndSettle();
        expect(module.selected, before);
        expect(
          t
              .widget<StarBridgeNavigationPane>(
                find.byType(StarBridgeNavigationPane),
              )
              .interaction,
          NavigationInteraction.keyboard,
        );
        await activate(t, primary('/tools'), 'keyboard');
        expect(route(t).animation!.value, 1);
        await activate(t, dialogAction('继续编辑'), 'keyboard');
        await t.pumpAndSettle();
        expect(find.byType(CommunityChatPanel), findsOneWidget);
        await capture(t, frame, '${suite.name}-shell');
        await back(t, 'pointer');
        await t.pumpAndSettle();
        await activate(t, dialogAction('丢弃草稿并返回'), 'keyboard');
        await t.pumpAndSettle();
        expect(
          t
              .widget<CommunityWorkspaceView>(
                find.byType(CommunityWorkspaceView),
              )
              .targetRef,
          before!.targetRef,
        );
        expect(
          find.byKey(const ValueKey('community-section-members')),
          findsOneWidget,
        );
        final track = find.byWidgetPredicate(
          (w) =>
              w is SuiteSelectionTrack &&
              w.items.any((item) => item.id == 'members'),
        );
        expect(
          t.widget<SuiteSelectionTrack>(track).changeSource,
          InteractionSource.keyboard,
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite delayed keyboard guard uses pinned origin after await',
      (t) async {
        final state = await mount(t, suite);
        state.held = Completer();
        await activate(t, find.byKey(const Key('guard')), 'keyboard');
        expect(find.byType(AlertDialog), findsNothing);
        state.held!.complete();
        await t.pump();
        await t.pump();
        expect(route(t).animation!.value, 1);
        await activate(t, dialogAction('继续编辑'), 'keyboard');
        await t.pumpAndSettle();
        expect(state.result, false);
        expect(state.controller.draft, '需要保护的草稿');
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite old leave confirmation cannot discard a rebound chat draft',
      (t) async {
        final state = await mount(t, suite);
        await activate(t, find.byKey(const Key('guard')), 'keyboard');
        await t.pumpAndSettle();
        final replacement = CommunityChatController(
          state.widget.port,
          'a' * 32,
          localEcho: true,
        );
        addTearDown(replacement.dispose);
        replacement.updateDraft('新上下文的草稿');
        state.change(() => state.controller = replacement);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(state.result, false);
        expect(replacement.draft, '新上下文的草稿');
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
