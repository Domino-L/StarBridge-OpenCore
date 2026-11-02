import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_composer.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';

import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_test.dart' show fire;
import 'interaction_batch3bw_test.dart' show frames;

MenuCommsView projection({
  String draft = '',
  int revision = 0,
  String delivery = 'idle',
  bool locked = false,
  bool canSend = true,
  String profile = 'c1',
}) => MenuCommsView(
  'ready',
  compose: true,
  name: '白鸦',
  profileKey: profile,
  draft: draft,
  draftRevision: revision,
  delivery: delivery,
  locked: locked,
  canSend: canSend,
);

class Harness extends StatefulWidget {
  const Harness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  var view = projection(), disconnected = false, reduce = false, light = false;
  final calls = <(String, String, String, int, InteractionSource)>[];
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => scopedApp(
    SingleChildScrollView(
      child: MenuCommsComposer(
        key: ValueKey('composer-${view.profileKey}'),
        view: view,
        disconnected: disconnected,
        onCompose: (a, k, text, revision) => calls.add((
          a,
          k,
          text,
          revision,
          currentStarBridgeActivationSource,
        )),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<HarnessState> mount(WidgetTester t, InteractionSuite suite) async {
  size(t, const Size(620, 600));
  final host = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(suite, key: host));
  await frames(t);
  return host.currentState!;
}

final draftField = find.byKey(const ValueKey('menu-message-draft'));
TextEditingController controller(WidgetTester t) =>
    t.widget<TextField>(draftField).controller!;
VoidCallback sendCallback(WidgetTester t) {
  final control = t.widget(find.byKey(const ValueKey('menu-message-send')));
  if (control is FilledButton) return control.onPressed!;
  return () =>
      (control as SuitePressable).onActivate!(InteractionSource.pointer);
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite same-frame send callback cannot hand off twice', (
      t,
    ) async {
      final h = await mount(t, suite);
      await t.enterText(draftField, '保留草稿');
      await t.pump();
      final send = sendCallback(t);
      send();
      send();
      expect(h.calls.where((a) => a.$1 == 'send'), hasLength(1));
      expect(h.calls.last.$4, 2);
      await t.pumpWidget(const SizedBox());
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source send, acknowledgement and unknown check stay distinct',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = await mount(t, suite);
          try {
            await t.enterText(draftField, '你好\n舰桥');
            await t.pump();
            final edit = h.calls.single;
            expect(
              (edit.$1, edit.$2, edit.$3, edit.$4),
              ('edit', 'c1', '你好\n舰桥', 1),
            );
            await fire(
              t,
              source,
              find.byKey(const ValueKey('menu-message-send')),
            );
            expect(h.calls.last.$1, 'send');
            expect(h.calls.last.$4, 2);
            expect(
              h.calls.last.$5,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            // A command handoff is not a transport confirmation.
            expect(find.text('已发送'), findsNothing);
            expect(controller(t).text, '你好\n舰桥');
            h.change(
              () => h.view = projection(
                draft: '你好\n舰桥',
                revision: 2,
                delivery: 'sending',
                locked: true,
                canSend: false,
              ),
            );
            await t.pump();
            await t.pump();
            expect(find.byType(SuiteBusyFrame), findsOneWidget);
            final wait = t.element(find.byType(SuiteBusyLabel));
            expect(Theme.of(wait).textTheme.bodySmall?.fontSize, 13);
            expect(Theme.of(wait).textTheme.bodySmall?.height, 1.5);
            expect(InteractionScope.of(wait).reduceMotion, source != 'pointer');
            expect(t.widget<TextField>(draftField).readOnly, isTrue);
            h.change(
              () => h.view = projection(
                draft: '你好\n舰桥',
                revision: 3,
                delivery: 'unknown',
                locked: true,
                canSend: false,
              ),
            );
            await t.pump();
            await t.pump();
            expect(find.byType(SuiteBusyFrame), findsNothing);
            await fire(
              t,
              source,
              find.byKey(const ValueKey('menu-message-check')),
            );
            expect(h.calls.last.$1, 'check');
            expect(
              h.calls.last.$5,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(h.calls.last.$4, 3);
            expect(h.calls.last.$3, '你好\n舰桥');
            expect(h.calls.where((a) => a.$1 == 'send'), hasLength(1));
            h.change(() => h.view = projection(revision: 4, delivery: 'sent'));
            await t.pump();
            expect(controller(t).text, isEmpty);
            expect(find.text('已发送'), findsOneWidget);
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
    testWidgets(
      '$suite native editor survives live suite, selection and IME changes',
      (t) async {
        final h = await mount(t, suite);
        expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
        await t.showKeyboard(draftField);
        const value = TextEditingValue(
          text: '星海舰桥',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 4),
        );
        t.testTextInput.updateEditingValue(value);
        await t.pump();
        final native = controller(t),
            focus = t.widget<TextField>(draftField).focusNode!;
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(h.calls.where((a) => a.$1 == 'send'), isEmpty);
        h.change(() {
          h.suite = InteractionSuite.glow;
          h.light = true;
          h.reduce = true;
        });
        await frames(t, 2);
        expect(controller(t), same(native));
        expect(native.value, value);
        expect(t.widget<TextField>(draftField).focusNode, same(focus));
        expect(focus.hasFocus, isTrue);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite missing ack, disconnect and late echo keep newest draft',
      (t) async {
        final h = await mount(t, suite);
        await t.enterText(draftField, 'first');
        await t.enterText(draftField, 'latest');
        h.change(() => h.view = projection(draft: 'first', revision: 1));
        await t.pump();
        expect(controller(t).text, 'latest');
        await t.pump(const Duration(seconds: 5));
        expect(find.textContaining('通讯暂未响应'), findsOneWidget);
        expect(find.byType(SuiteBusyFrame), findsNothing);
        expect(h.calls.where((a) => a.$1 == 'send'), isEmpty);
        h.change(() => h.disconnected = true);
        await t.pump();
        expect(controller(t).text, 'latest');
        expect(find.textContaining('通讯连接中断'), findsOneWidget);
        h.change(() {
          h.disconnected = false;
          h.view = projection(draft: 'latest', revision: 2);
        });
        await t.pump();
        expect(find.textContaining('草稿暂未确认保存'), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite only this actual send can animate, live reduce stops wait',
      (t) async {
        final h = await mount(t, suite);
        h.change(
          () => h.view = projection(
            draft: 'restored',
            revision: 10,
            delivery: 'sending',
            locked: true,
            canSend: false,
          ),
        );
        await t.pump();
        await t.pump();
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyLabel)))
              .reduceMotion,
          isTrue,
        );
        h.change(
          () => h.view = projection(
            draft: 'restored',
            revision: 11,
            delivery: 'rejected',
          ),
        );
        await t.pump();
        await fire(
          t,
          'pointer',
          find.byKey(const ValueKey('menu-message-send')),
        );
        h.change(
          () => h.view = projection(
            draft: 'restored',
            revision: 12,
            delivery: 'sending',
            locked: true,
            canSend: false,
          ),
        );
        await t.pump();
        await t.pump();
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyLabel)))
              .reduceMotion,
          isFalse,
        );
        h.change(() => h.reduce = true);
        await t.pump();
        await t.pump();
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyLabel)))
              .reduceMotion,
          isTrue,
        );
        h.change(() {
          h.reduce = false;
          h.view = projection(
            profile: 'c2',
            draft: 'new owner',
            revision: 12,
            delivery: 'sending',
            locked: true,
            canSend: false,
          );
        });
        await t.pump();
        await t.pump();
        expect(controller(t).text, 'new owner');
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyLabel)))
              .reduceMotion,
          isTrue,
        );
        expect(h.calls.where((a) => a.$1 == 'send'), hasLength(1));
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite blocked send paths expose no activatable action', (
      t,
    ) async {
      final semantics = t.ensureSemantics(), h = await mount(t, suite);
      try {
        for (final value in [
          projection(),
          projection(draft: 'draft', canSend: false),
          projection(draft: 'draft', locked: true),
        ]) {
          h.change(() => h.view = value);
          await t.pump();
          await t.pump();
          final target = t.widget(
            find.byKey(const ValueKey('menu-message-send')),
          );
          expect(
            target is FilledButton
                ? target.onPressed
                : (target as SuitePressable).onActivate,
            isNull,
          );
        }
        h.change(() {
          h.view = projection(draft: 'retained');
          h.disconnected = true;
        });
        await t.pump();
        final target = t.widget(
          find.byKey(const ValueKey('menu-message-send')),
        );
        expect(
          target is FilledButton
              ? target.onPressed
              : (target as SuitePressable).onActivate,
          isNull,
        );
        expect(h.calls, isEmpty);
      } finally {
        semantics.dispose();
        await t.pumpWidget(const SizedBox());
      }
    });
    testWidgets(
      '$suite private IME, shift and key repeat keep shortcut contract',
      (t) async {
        final h = await mount(t, suite);
        await t.enterText(draftField, 'native text');
        await t.pump();
        await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(h.calls.where((a) => a.$1 == 'send'), isEmpty);
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(h.calls.where((a) => a.$1 == 'send'), hasLength(1));
        expect(h.calls.last.$5, InteractionSource.keyboard);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
