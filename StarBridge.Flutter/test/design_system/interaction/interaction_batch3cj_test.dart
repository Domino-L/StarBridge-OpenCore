import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ca_test.dart' show fire;

class Harness extends StatefulWidget {
  const Harness(this.suite, {this.outlined = false, super.key});
  final InteractionSuite suite;
  final bool outlined;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  var identity = 'scope1', grant = 'a1', label = '操作';
  String? confirm = '确认这个操作？', inputLabel = '房间密码';
  var limit = 4, enabled = true, reduce = false, light = false, visible = true;
  final calls = <(String, String, InteractionSource)>[];
  void change(VoidCallback fn) => setState(fn);
  @override
  Widget build(BuildContext context) => scopedApp(
    Center(
      child: SizedBox(
        width: 340,
        height: 320,
        child: visible
            ? MenuFeatureAction(
                identity: identity,
                action: (
                  key: grant,
                  label: label,
                  confirm: confirm,
                  input: inputLabel,
                  limit: limit,
                  role: null,
                  secret: inputLabel != null,
                ),
                outlined: widget.outlined,
                enabled: enabled,
                onAction: (key, value) =>
                    calls.add((key, value, currentStarBridgeActivationSource)),
              )
            : const Text('已离开'),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  InteractionSuite suite, {
  bool outlined = false,
}) async {
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(suite, outlined: outlined, key: key));
  await frames(t);
  return key.currentState!;
}

Finder control(String label) => find.byWidgetPredicate(
  (w) =>
      w is BridgeMenuAction && w.label == label ||
      w is StarBridgeActionButton && w.semanticLabel == label,
);
Future<void> act(WidgetTester t, String source, String label) async {
  await fire(t, source, control(label));
  await frames(t);
}

VoidCallback callback(WidgetTester t, String label) =>
    t.widget<BridgeMenuAction>(control(label)).onPressed!;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final outlined in [false, true]) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite outlined=$outlined $source preserves native input, captured decision and source once',
          (t) async {
            final semantics = t.ensureSemantics();
            try {
              final h = await mount(t, suite, outlined: outlined);
              await t.enterText(find.byType(TextField), '123456');
              await t.pump();
              final input = t.widget<TextField>(find.byType(TextField));
              expect(input.obscureText, true);
              expect(input.maxLines, 1);
              expect(input.controller!.text, '1234');
              await act(t, source, '操作');
              expect(h.calls, isEmpty);
              await t.enterText(find.byType(TextField), 'zzzz');
              await t.pump();
              final stale = callback(t, '确认操作');
              await act(t, source, '确认操作');
              expect(h.calls, [
                (
                  'a1',
                  '1234',
                  source == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              ]);
              stale();
              stale();
              await t.pump();
              expect(h.calls, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              await frames(t);
              semantics.dispose();
            }
          },
        );
      }
    }
    for (final change in [
      'context',
      'grant',
      'label',
      'confirm',
      'input',
      'limit',
      'dispose',
    ]) {
      testWidgets(
        '$suite $change retires decision without borrowing a later one',
        (t) async {
          final h = await mount(t, suite);
          await t.enterText(find.byType(TextField), '1234');
          await act(t, 'pointer', '操作');
          final stale = callback(t, '确认操作');
          h.change(() {
            switch (change) {
              case 'context':
                h.identity = 'scope2';
              case 'grant':
                h.grant = 'a2';
              case 'label':
                h.label = '新操作';
              case 'confirm':
                h.confirm = null;
              case 'input':
                h.inputLabel = '另一个输入';
              case 'limit':
                h.limit = 5;
              case 'dispose':
                h.visible = false;
            }
          });
          await t.pump();
          await t.pump();
          stale();
          await t.pump();
          expect(h.calls, isEmpty);
          expect(find.text('确认操作'), findsNothing);
          if (change != 'dispose') {
            final text = t
                .widget<TextField>(find.byType(TextField))
                .controller!
                .text;
            expect(
              text,
              (change == 'context' || change == 'input') ? '' : '1234',
            );
            h.change(() => h.confirm = '新的确认');
            await t.pump();
            await act(t, 'pointer', h.label);
            final fresh = callback(t, '确认${h.label}');
            stale();
            expect(h.calls, isEmpty);
            fresh();
            await t.pump();
            expect(h.calls, hasLength(1));
            expect(h.calls.single.$1, h.grant);
          }
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await frames(t);
        },
      );
    }
    testWidgets(
      '$suite disabled confirmation cannot dispatch but cancel stays available',
      (t) async {
        final h = await mount(t, suite);
        await act(t, 'pointer', '操作');
        final stale = callback(t, '确认操作');
        h.change(() => h.enabled = false);
        await t.pump();
        stale();
        expect(h.calls, isEmpty);
        expect(t.widget<BridgeMenuAction>(control('确认操作')).onPressed, isNull);
        await act(t, 'keyboard', '取消');
        expect(find.text('确认操作'), findsNothing);
        stale();
        expect(h.calls, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
    testWidgets(
      '$suite cancelled decision cannot consume a newly prepared identical decision',
      (t) async {
        final h = await mount(t, suite);
        await act(t, 'pointer', '操作');
        final stale = callback(t, '确认操作');
        await act(t, 'pointer', '取消');
        await act(t, 'pointer', '操作');
        stale();
        expect(h.calls, isEmpty);
        expect(control('确认操作'), findsOneWidget);
        await act(t, 'pointer', '确认操作');
        expect(h.calls, hasLength(1));
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
    testWidgets(
      '$suite style and live reduced motion keep the same native editor and decision',
      (t) async {
        final h = await mount(t, suite);
        await t.enterText(find.byType(TextField), '1234');
        final editor = t.widget<TextField>(find.byType(TextField)).controller;
        await act(t, 'pointer', '操作');
        h.change(() {
          h.reduce = true;
          h.light = true;
          h.suite = InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(
          t.widget<TextField>(find.byType(TextField)).controller,
          same(editor),
        );
        expect(control('确认操作'), findsOneWidget);
        await act(t, 'keyboard', '确认操作');
        expect(h.calls.single.$2, '1234');
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
    testWidgets(
      '$suite actual archive decision cannot cross selected conversation',
      (t) async {
        size(t, const Size(900, 900));
        final selected = ValueNotifier('c1'),
            calls = <(String, String, String)>[];
        await t.pumpWidget(
          scopedApp(
            ValueListenableBuilder<String>(
              valueListenable: selected,
              builder: (_, key, _) => MenuCommsHistory(
                view: MenuCommsView(
                  'ready',
                  name: '同名用户',
                  profileKey: key,
                  pageKey: '$key/page',
                  archiveAvailable: true,
                ),
                active: false,
                onAction: (a, k) => calls.add((selected.value, a, k)),
              ),
            ),
            suite,
          ),
        );
        await frames(t);
        await t.tap(find.text('清除本机记录'));
        await frames(t);
        expect(find.text('确认清除本机记录'), findsOneWidget);
        expect(calls, isEmpty);
        selected.value = 'c2';
        await t.pump();
        await t.pump();
        expect(find.text('确认清除本机记录'), findsNothing);
        expect(calls, isEmpty);
        await t.pumpWidget(const SizedBox());
        await frames(t);
        selected.dispose();
      },
    );
  }
}
