import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../app/menu_overlay/menu_comms_channels_test.dart' show channel;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_test.dart' show fire;

Map<String, Object?> state({
  bool outbox = false,
  String? accepted,
  String? rejected,
  int revision = 0,
  String status = 'idle',
  String scope = 's1',
}) {
  final raw = channel(revision: revision, status: status, scope: scope);
  raw['rejectedAction'] = rejected;
  if (outbox) {
    raw['chat'] = {
      ...raw['chat'] as Map,
      'outboxVersion': 1,
      'acceptedAction': accepted,
      'localMessages': <Map<String, Object?>>[],
    };
  }
  return raw;
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final outbox in [false, true]) {
        testWidgets(
          '$suite $source channel outbox=$outbox retains original acceptance rule',
          (t) async {
            size(t, const Size(760, 900));
            final semantics = t.ensureSemantics(),
                view = ValueNotifier(state(outbox: outbox));
            expect(MenuFeatureView.parse(view.value).state, 'ready');
            expect(MenuFeatureView.parse(view.value).chat, isNotNull);
            final calls = <(String, String, InteractionSource)>[];
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder(
                  valueListenable: view,
                  builder: (_, raw, _) => MenuChannelPanel(
                    view: MenuFeatureView.parse(raw),
                    active: true,
                    onAction: (a, text) =>
                        calls.add((a, text, currentStarBridgeActivationSource)),
                  ),
                ),
                suite,
              ),
            );
            final input = find.byKey(const ValueKey('menu-channel-draft'));
            TextEditingController editor() =>
                t.widget<TextField>(input).controller!;
            try {
              await t.pump();
              expect(input, findsOneWidget);
              expect(
                find.descendant(of: input, matching: find.byType(EditableText)),
                findsOneWidget,
              );
              await t.enterText(input, '频道草稿');
              await t.pump();
              final native = editor(),
                  focus = t.widget<TextField>(input).focusNode!;
              await fire(
                t,
                source,
                find.byKey(const ValueKey('menu-channel-send')),
              );
              expect(calls.where((a) => a.$1 == 'a1'), [
                (
                  'a1',
                  '频道草稿',
                  source == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              ]);
              expect(editor(), same(native));
              expect(editor().text, '频道草稿');
              if (outbox) {
                view.value = state(
                  outbox: true,
                  accepted: 'a99',
                  revision: 100,
                );
                await t.pump();
                expect(editor().text, '频道草稿');
                // Modern outbox keeps typing editable while local handoff is pending.
                await t.enterText(input, '下一条草稿');
                await t.pump();
                view.value = state(outbox: true, accepted: 'a1', revision: 101);
                await t.pump();
                expect(editor().text, '下一条草稿');
              } else {
                expect(t.widget<TextField>(input).readOnly, isTrue);
                view.value = state(status: 'rejected');
                await t.pump();
                expect(editor().text, '频道草稿');
                await fire(
                  t,
                  source,
                  find.byKey(const ValueKey('menu-channel-send')),
                );
                view.value = state(revision: 1, status: 'sent');
                await t.pump();
                expect(editor().text, isEmpty);
              }
              expect(t.widget<TextField>(input).focusNode, same(focus));
              view.value = state(outbox: outbox, scope: 's2');
              await t.pump();
              expect(editor().text, isEmpty);
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await t.pumpWidget(const SizedBox());
              view.dispose();
            }
          },
        );
      }
    }
    testWidgets('$suite channel IME and shift enter do not dispatch', (
      t,
    ) async {
      final calls = <String>[];
      await t.pumpWidget(
        scopedApp(
          MenuChannelPanel(
            view: MenuFeatureView.parse(state()),
            active: true,
            onAction: (a, _) => calls.add(a),
          ),
          suite,
        ),
      );
      final input = find.byKey(const ValueKey('menu-channel-draft'));
      await t.pump();
      await t.showKeyboard(input);
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '舰桥',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.where((a) => a == 'a1'), isEmpty);
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '舰桥',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(calls.where((a) => a == 'a1'), isEmpty);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(calls.where((a) => a == 'a1'), ['a1']);
      await t.pumpWidget(const SizedBox());
    });
  }
}
