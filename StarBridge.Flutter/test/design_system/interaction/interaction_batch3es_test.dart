import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/settings/entitlement_redemption_dialog.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show activate, key;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<void> openForm(
  WidgetTester t,
  InteractionSuite suite,
  Future<String> Function(String) redeem,
) async {
  size(t, const Size(900, 850));
  await t.pumpWidget(
    scopedApp(
      Builder(
        builder: (context) => StarBridgeActionButton(
          controlKey: const Key('redemption-open'),
          onActivate: (source) => showStarBridgeDialog<void>(
            context,
            source: source,
            builder: (_) =>
                EntitlementRedemptionDialog(supported: true, redeem: redeem),
          ),
          child: const Text('Open'),
        ),
      ),
      suite,
    ),
  );
  await t.pumpAndSettle();
  await activate(t, key('redemption-open'), 'pointer');
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite redemption $input holds, rejects, retries and clears',
        (t) async {
          final semantics = t.ensureSemantics();
          final codes = <String>[];
          final sources = <InteractionSource>[];
          var receipt = Completer<String>();
          try {
            await openForm(t, suite, (code) {
              codes.add(code);
              sources.add(currentStarBridgeActivationSource);
              return receipt.future;
            });
            expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
            await t.enterText(find.byType(TextField), '  synthetic-code  ');
            await t.pumpAndSettle();
            await activate(t, key('redemption-submit'), input);
            final source = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(codes, ['synthetic-code']);
            expect(sources, [source]);
            expect(
              t.widget<TextField>(find.byType(TextField)).enabled,
              isFalse,
            );
            final button = t.widget<StarBridgeActionButton>(
              find
                  .ancestor(
                    of: key('redemption-submit'),
                    matching: find.byType(StarBridgeActionButton),
                  )
                  .first,
            );
            expect(button.onActivate, isNull);
            expect(
              t
                  .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                  .source,
              source,
            );
            expect(
              find.byType(SuiteProgressBar),
              input == 'pointer' ? findsOneWidget : findsNothing,
            );
            await t.pump(const Duration(milliseconds: 200));
            expect(codes, hasLength(1));
            receipt.complete('rejected');
            await t.pumpAndSettle();
            expect(find.text('兑换码无效或无法使用。'), findsOneWidget);
            expect(
              t.widget<TextField>(find.byType(TextField)).controller!.text,
              '  synthetic-code  ',
            );
            receipt = Completer<String>();
            await activate(t, key('redemption-submit'), input);
            expect(codes, ['synthetic-code', 'synthetic-code']);
            receipt.complete('redeemed');
            await t.pumpAndSettle();
            expect(find.text('兑换成功，权益已更新。'), findsOneWidget);
            expect(
              t.widget<TextField>(find.byType(TextField)).controller!.text,
              isEmpty,
            );
            expect(find.byType(HelpSupportWaiting), findsNothing);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '$suite actual redemption entry $input follows live settings',
        (t) async {
          size(t, const Size(900, 850));
          final semantics = t.ensureSemantics();
          final account = ValueNotifier(achievementTestAccount(7));
          var reduce = false, light = false;
          late StateSetter update;
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return scopedApp(
                    Builder(
                      builder: (context) => StarBridgeActionButton(
                        controlKey: const Key('redemption-open'),
                        onActivate: (_) =>
                            showLegacyEntitlementRedemptionDialog(
                              context,
                              account,
                              null,
                            ),
                        child: const Text('Open'),
                      ),
                    ),
                    suite,
                    reduce: reduce,
                    light: light,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            await activate(t, key('redemption-open'), input);
            final route = ModalRoute.of(
              t.element(find.byType(EntitlementRedemptionDialog)),
            )!;
            expect(route, isA<StarBridgeDialogRoute<void>>());
            expect(
              route.traversalEdgeBehavior,
              TraversalEdgeBehavior.closedLoop,
            );
            expect(
              (route as StarBridgeDialogRoute).instant,
              input != 'pointer',
            );
            update(() {
              reduce = true;
              light = true;
            });
            await t.pump();
            await t.pump();
            final data = InteractionScope.of(
              t.element(find.byType(AlertDialog)),
            );
            expect(data.reduceMotion, isTrue);
            expect(data.palette.brightness, Brightness.light);
            expect(route.animation!.value, 1);
            expect(find.byType(TextField), findsNothing);
            for (final shift in [false, true]) {
              if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              for (var step = 0; step < 4; step++) {
                await t.sendKeyEvent(LogicalKeyboardKey.tab);
                await t.pump();
                final focusContext =
                    FocusManager.instance.primaryFocus!.context!;
                expect(ModalRoute.of(focusContext), same(route));
              }
              if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            }
            account.value = achievementTestAccount(8);
            await t.pump();
            expect(find.byType(EntitlementRedemptionDialog), findsOneWidget);
            await activate(t, key('redemption-close'), input);
            await t.pumpAndSettle();
            expect(find.byType(EntitlementRedemptionDialog), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
            account.dispose();
          }
        },
      );
    }

    testWidgets('$suite unconfirmed result keeps code and cannot replay', (
      t,
    ) async {
      var calls = 0;
      await openForm(t, suite, (_) async {
        calls++;
        throw StateError('synthetic');
      });
      await t.enterText(find.byType(TextField), 'synthetic-code');
      await t.pumpAndSettle();
      await activate(t, key('redemption-submit'), 'pointer');
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'synthetic-code',
      );
      expect(find.byType(HelpSupportWaiting), findsNothing);
      await activate(t, key('redemption-close'), 'keyboard');
      await t.pumpAndSettle();
      expect(find.byType(EntitlementRedemptionDialog), findsNothing);
      expect(calls, 1);
    });

    testWidgets('$suite closing a pending redemption ignores late receipt', (
      t,
    ) async {
      final pending = Completer<String>();
      var calls = 0;
      await openForm(t, suite, (_) {
        calls++;
        return pending.future;
      });
      await t.enterText(find.byType(TextField), 'synthetic-code');
      await t.pumpAndSettle();
      await activate(t, key('redemption-submit'), 'pointer');
      await activate(t, key('redemption-close'), 'keyboard');
      await t.pumpAndSettle();
      expect(find.byType(EntitlementRedemptionDialog), findsNothing);
      pending.complete('redeemed');
      await t.pumpAndSettle();
      expect(find.text('兑换成功，权益已更新。'), findsNothing);
      expect(calls, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      '$suite live style and reduced motion keep the native draft and held request',
      (t) async {
        size(t, const Size(900, 850));
        final pending = Completer<String>();
        var calls = 0, reduce = false;
        var selected = suite;
        late StateSetter update;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return scopedApp(
                EntitlementRedemptionDialog(
                  supported: true,
                  redeem: (_) {
                    calls++;
                    return pending.future;
                  },
                ),
                selected,
                reduce: reduce,
              );
            },
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'native-draft');
        final field = t.widget<TextField>(find.byType(TextField));
        field.controller!.value = const TextEditingValue(
          text: 'native-draft',
          selection: TextSelection(baseOffset: 3, extentOffset: 6),
          composing: TextRange(start: 0, end: 6),
        );
        await t.pump();
        final value = field.controller!.value;
        final editor = t.state(find.byType(EditableText));
        update(() {
          selected = InteractionSuite.glow;
        });
        await t.pumpAndSettle();
        expect(t.state(find.byType(EditableText)), same(editor));
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.value,
          value,
        );
        await activate(t, key('redemption-submit'), 'pointer');
        update(() {
          reduce = true;
        });
        await t.pump();
        await t.pump();
        expect(find.byType(SuiteProgressBar), findsNothing);
        expect(find.byType(HelpSupportWaiting), findsOneWidget);
        expect(calls, 1);
        pending.complete('throttled');
        await t.pumpAndSettle();
        expect(find.text('操作过于频繁，请稍后再试。'), findsOneWidget);
        expect(
          t.widget<TextField>(find.byType(TextField)).controller,
          same(field.controller),
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
