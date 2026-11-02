import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_actions.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_trade_profile_test.dart' show ProfilePort, fixtureProfile;
import 'marketplace_trade_button_motion_test.dart' show focusOf;
import 'marketplace_diagnostic_toast_motion_test.dart' show toastAnimation;
import 'marketplace_trades_test.dart' show TradesPort;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../friends/social_layout_test.dart' show size;

class InnerTradePort extends TradesPort {
  final commands = <(String, MarketRow)>[];
  @override
  Future<MarketRow> trade(String operation, [MarketRow input = const {}]) {
    if (!['list', 'detail', 'revision'].contains(operation)) {
      commands.add((operation, Map<String, Object?>.from(input)));
    }
    return super.trade(operation, input);
  }
}

class InnerProfilePort extends ProfilePort {
  Completer<MarketRow>? profileGate;
  String? readError;
  int profileReads = 0;
  MarketRow? changes;
  @override
  Future<MarketRow> tradeProfile([MarketRow? value]) async {
    if (value == null) {
      profileReads++;
      if (readError != null) {
        throw MarketplaceTradeError(readError!);
      }
    } else {
      changes = Map<String, Object?>.from(value);
      if (profileGate != null) {
        saves++;
        return profileGate!.future;
      }
    }
    return super.tradeProfile(value);
  }

  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) => operation == 'timezones'
      ? Future.value(
          MarketRead({
            'rows': [
              {'id': 1, 'label': 'UTC +08:00', 'offsetMinutes': 480},
            ],
          }, DateTime.utc(2026, 10, 19)),
        )
      : super.read(
          operation,
          id: id,
          keyword: keyword,
          category: category,
          side: side,
          page: page,
          language: language,
          options: options,
        );
  MarketRow get accepted => {
    'profile': {...fixtureProfile(), ...?changes},
    'confirmed': true,
  };
}

Finder action(String suffix) => find.byKey(Key('market-trade-action-$suffix'));
Finder profile(String suffix) =>
    find.byKey(Key('market-trade-profile-$suffix'));
Finder control(Finder target, InteractionSuite suite) => find.descendant(
  of: target,
  matching: suite == InteractionSuite.standard
      ? find.byWidgetPredicate((w) => w is ButtonStyleButton)
      : find.byType(SuitePressable),
);

SemanticsNode namedButton(WidgetTester tester, String label) {
  final nodes = exposedNodes(tester).where((n) {
    final d = n.getSemanticsData();
    return d.label == label && d.flagsCollection.isButton;
  }).toList();
  expect(nodes, hasLength(1), reason: 'One exposed button named $label');
  return nodes.single;
}

SemanticsNode keyedButton(WidgetTester tester, Finder key) {
  final label = tester
      .widget<Text>(find.descendant(of: key, matching: find.byType(Text)))
      .data!;
  return namedButton(tester, label);
}

void activate(WidgetTester tester, SemanticsNode node) {
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
}

Widget app(
  MarketplaceController controller,
  InteractionSuite suite,
  FocusNode trigger, {
  bool isProfile = false,
  String operation = 'cancel',
  bool reduce = false,
  ValueChanged<MarketRow?>? result,
}) => scopedApp(
  Builder(
    builder: (context) => TextButton(
      focusNode: trigger,
      onPressed: isProfile
          ? () async {
              final value = await editTradeProfile(context, controller);
              result?.call(value);
            }
          : () => tradeDialog(
              context,
              controller,
              operation,
              (controller.port as TradesPort).row,
            ),
      child: Text(isProfile ? '打开资料' : '打开操作'),
    ),
  ),
  suite,
  reduce: reduce,
);

Future<void> open(WidgetTester tester, {bool isProfile = false}) async {
  await tester.tap(find.text(isProfile ? '打开资料' : '打开操作'));
  await tester.pumpAndSettle();
}

void disabled(SemanticsNode node) {
  final d = node.getSemanticsData();
  expect(d.flagsCollection.isEnabled, Tristate.isFalse);
  expect(d.hasAction(SemanticsAction.tap), isFalse);
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'trade action ${suite.name} preserves geometry danger focus and all cancel sources',
      (tester) async {
        size(tester, const Size(900, 900));
        final semantics = tester.ensureSemantics();
        final port = InnerTradePort();
        final c = MarketplaceController(port);
        final trigger = FocusNode();
        try {
          await tester.pumpWidget(app(c, suite, trigger));
          await tester.pumpAndSettle();
          trigger.requestFocus();
          await tester.pump();
          await open(tester);
          expect(
            control(action('cancel'), suite),
            findsOneWidget,
            reason: 'Trade operation buttons must participate in the selected interaction suite.',
          );
          final confirm = control(action('submit'), suite);
          expect(confirm, findsOneWidget);
          final error = Theme.of(tester.element(confirm)).colorScheme.error;
          if (suite == InteractionSuite.standard) {
            expect(
              tester
                  .widget<FilledButton>(confirm)
                  .style!
                  .backgroundColor!
                  .resolve({}),
              error,
            );
          } else {
            expect(
              InteractionScope.of(tester.element(confirm)).palette.accent,
              error,
            );
          }
          expect(
            tester.getRect(action('close')),
            const Rect.fromLTRB(612, 333, 660, 381),
          );
          expect(
            tester.getRect(action('cancel')),
            const Rect.fromLTRB(492, 519, 564, 567),
          );
          expect(
            tester.getRect(action('submit')),
            const Rect.fromLTRB(572, 519, 660, 567),
          );
          expect(
            tester.getRect(find.text('取消')),
            const Rect.fromLTRB(516, 537, 540, 549),
          );
          expect(
            tester.getRect(find.text('取消交易').last),
            const Rect.fromLTRB(592, 537, 640, 549),
          );
          expect(
            focusOf(tester, control(action('cancel'), suite), suite).hasFocus,
            isTrue,
          );
          final press = await tester.startGesture(
            tester.getCenter(action('cancel')),
          );
          await tester.pump(const Duration(milliseconds: 120));
          EffectHostState? effects;
          if (suite != InteractionSuite.standard) {
            effects = tester.state<EffectHostState>(
              find.descendant(
                of: action('cancel'),
                matching: find.byType(EffectHost),
              ),
            );
            if (suite == InteractionSuite.scan ||
                suite == InteractionSuite.glow) {
              expect(
                effects.isPlaying(
                  suite == InteractionSuite.scan
                      ? TransientEffect.beam
                      : TransientEffect.ring,
                ),
                isTrue,
              );
            }
          }
          await tester.pumpWidget(app(c, suite, trigger, reduce: true));
          await tester.pump();
          if (effects != null) {
            expect(TransientEffect.values.any(effects.isPlaying), isFalse);
          }
          await press.up();
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          await tester.pumpWidget(app(c, suite, trigger));
          await tester.pumpAndSettle();
          await open(tester);
          focusOf(
            tester,
            control(action('cancel'), suite),
            suite,
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          await open(tester);
          activate(tester, namedButton(tester, '关闭'));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'trade action ${suite.name} keeps pending failure draft retry and confirmed response',
      (tester) async {
        size(tester, const Size(900, 900));
        final semantics = tester.ensureSemantics();
        var gate = Completer<MarketRow>();
        final port = InnerTradePort()..writeGate = gate;
        final c = MarketplaceController(port);
        final trigger = FocusNode();
        try {
          await tester.pumpWidget(app(c, suite, trigger));
          await tester.pumpAndSettle();
          trigger.requestFocus();
          await tester.pump();
          await open(tester);
          activate(tester, keyedButton(tester, action('submit')));
          await tester.pump();
          expect(c.trades.pending, isTrue);
          expect(port.writes, 1);
          disabled(keyedButton(tester, action('cancel')));
          disabled(keyedButton(tester, action('submit')));
          disabled(namedButton(tester, '关闭'));
          if (suite == InteractionSuite.standard) {
            final native = tester.widget<Material>(
              find
                  .descendant(
                    of: action('submit'),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(
              native.color,
              FilledButtonTheme.of(tester.element(action('submit')))
                  .style!
                  .backgroundColor!
                  .resolve({WidgetState.disabled}),
            );
          }
          await tester.tap(action('cancel'), warnIfMissed: false);
          await tester.tap(action('submit'), warnIfMissed: false);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await Navigator.of(tester.element(action('submit'))).maybePop();
          await tester.pump();
          expect(find.byType(Dialog), findsOneWidget);
          expect(port.writes, 1);
          gate.completeError(
            const MarketplaceTradeError('marketplace.trade_rejected'),
          );
          await tester.pumpAndSettle();
          expect(c.trades.pending, isFalse);
          expect(find.byType(Dialog), findsOneWidget);
          expect(find.text('重试'), findsOneWidget);
          gate = Completer<MarketRow>();
          port.writeGate = gate;
          focusOf(
            tester,
            control(action('submit'), suite),
            suite,
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(port.writes, 2);
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump();
          expect(toastAnimation(tester).value, 1);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          expect(port.commands.map((v) => v.$1), ['cancel', 'cancel']);
          expect(port.commands.last.$2['transactionNumber'], 'T1');
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'trade action ${suite.name} retains delivery and report validation gates',
      (tester) async {
        size(tester, const Size(900, 900));
        final gate = Completer<MarketRow>();
        final port = InnerTradePort()..writeGate = gate;
        final c = MarketplaceController(port);
        final trigger = FocusNode();
        try {
          await tester.pumpWidget(app(c, suite, trigger, operation: 'ship'));
          await tester.pumpAndSettle();
          await open(tester);
          final semantics = tester.ensureSemantics();
          await tester.pump();
          try {
            disabled(keyedButton(tester, action('submit')));
            await tester.tap(action('submit'), warnIfMissed: false);
            expect(port.writes, 0);
            await tester.tap(find.byType(StarBridgeCheckboxTile));
            await tester.pumpAndSettle();
            expect(
              keyedButton(
                tester,
                action('submit'),
              ).getSemanticsData().hasAction(SemanticsAction.tap),
              isTrue,
            );
            await tester.tap(action('cancel'));
            await tester.pumpAndSettle();
            expect(port.writes, 0);
            await tester.pumpWidget(
              app(c, suite, trigger, operation: 'report'),
            );
            await tester.pumpAndSettle();
            await open(tester);
            await tester.tap(action('submit'));
            await tester.pumpAndSettle();
            expect(port.writes, 0);
            expect(find.byType(Dialog), findsOneWidget);
            await tester.tap(find.byType(StarBridgeChoiceChip).first);
            await tester.enterText(find.byType(TextField), 'fixture report');
            await tester.pumpAndSettle();
            await tester.tap(action('submit'));
            await tester.pump();
            expect(port.writes, 1);
            expect(port.commands.single.$1, 'report');
            expect(port.commands.single.$2['reportType'], 1);
            expect(port.commands.single.$2['content'], 'fixture report');
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
        }
      },
    );

    testWidgets(
      'trade action ${suite.name} ignores late UI work after leaving',
      (tester) async {
        size(tester, const Size(900, 900));
        final gate = Completer<MarketRow>();
        final port = InnerTradePort()..writeGate = gate;
        final c = MarketplaceController(port);
        final trigger = FocusNode();
        try {
          await tester.pumpWidget(app(c, suite, trigger));
          await tester.pumpAndSettle();
          await open(tester);
          await tester.tap(action('submit'));
          await tester.pump();
          expect(port.writes, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump();
          expect(c.trades.pending, isFalse);
          expect(find.byType(SnackBar), findsNothing);
          expect(port.writes, 1);
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
        }
      },
    );

    testWidgets(
      'profile ${suite.name} preserves geometry reload login availability and cancel result',
      (tester) async {
        size(tester, const Size(900, 900));
        final semantics = tester.ensureSemantics();
        final port = InnerProfilePort();
        final c = MarketplaceController(port);
        final trigger = FocusNode();
        var returned = false, logins = 0;
        MarketRow? result;
        try {
          await tester.pumpWidget(
            app(
              c,
              suite,
              trigger,
              isProfile: true,
              result: (v) {
                returned = true;
                result = v;
              },
            ),
          );
          await tester.pumpAndSettle();
          trigger.requestFocus();
          await tester.pump();
          await open(tester, isProfile: true);
          expect(control(profile('save'), suite), findsOneWidget);
          // Slice18: suites draw the trading-day chips with their own chip
          // face (20px shorter than native), so the centred dialog's actions
          // sit 10px higher; standard keeps the native layout.
          final dy = suite == InteractionSuite.standard ? 0.0 : -10.0;
          expect(
            tester.getRect(profile('close')),
            Rect.fromLTRB(526, 691 + dy, 574, 739 + dy),
          );
          expect(
            tester.getRect(profile('reload')),
            Rect.fromLTRB(582, 691 + dy, 650, 739 + dy),
          );
          expect(
            tester.getRect(profile('save')),
            Rect.fromLTRB(658, 691 + dy, 710, 739 + dy),
          );
          expect(
            tester.getRect(find.text('取消')),
            Rect.fromLTRB(538, 709 + dy, 562, 721 + dy),
          );
          expect(
            tester.getRect(find.text('重新读取')),
            Rect.fromLTRB(592, 709 + dy, 640, 721 + dy),
          );
          expect(
            tester.getRect(find.text('保存')),
            Rect.fromLTRB(672, 709 + dy, 696, 721 + dy),
          );
          expect(port.profileReads, 1);
          activate(tester, keyedButton(tester, profile('reload')));
          await tester.pumpAndSettle();
          expect(port.profileReads, 2);
          await tester.tap(profile('close'));
          await tester.pumpAndSettle();
          expect(returned, isTrue);
          expect(result, isNull);
          expect(trigger.hasFocus, isTrue);
          port.readError = 'marketplace.reauthorize_required';
          await open(tester, isProfile: true);
          disabled(keyedButton(tester, profile('login')));
          await tester.tap(profile('login'), warnIfMissed: false);
          expect(logins, 0);
          await tester.tap(profile('close'));
          await tester.pumpAndSettle();
          c.login = (_) async {
            logins++;
          };
          await open(tester, isProfile: true);
          activate(tester, keyedButton(tester, profile('login')));
          await tester.pumpAndSettle();
          expect(logins, 1);
          await tester.tap(profile('close'));
          await tester.pumpAndSettle();
          expect(port.saves, 0);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'profile ${suite.name} preserves pending draft rejection and accepted result',
      (tester) async {
        size(tester, const Size(900, 900));
        final semantics = tester.ensureSemantics();
        var gate = Completer<MarketRow>();
        final port = InnerProfilePort()..profileGate = gate;
        final c = MarketplaceController(port);
        final trigger = FocusNode();
        MarketRow? result;
        try {
          await tester.pumpWidget(
            app(c, suite, trigger, isProfile: true, result: (v) => result = v),
          );
          await tester.pumpAndSettle();
          trigger.requestFocus();
          await tester.pump();
          await open(tester, isProfile: true);
          final contact = find.byKey(const ValueKey('trade-profile-contact'));
          await tester.enterText(contact, 'fixture-contact-new');
          focusOf(
            tester,
            control(profile('save'), suite),
            suite,
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(port.saves, 1);
          for (final suffix in ['close', 'reload', 'save']) {
            disabled(keyedButton(tester, profile(suffix)));
            await tester.tap(profile(suffix), warnIfMissed: false);
          }
          await Navigator.of(tester.element(profile('save'))).maybePop();
          await tester.pump();
          expect(find.byType(TradeProfileForm), findsOneWidget);
          expect(port.saves, 1);
          gate.completeError(
            const MarketplaceTradeError('trade_profile.rejected'),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(contact).controller!.text,
            'fixture-contact-new',
          );
          gate = Completer<MarketRow>();
          port.profileGate = gate;
          activate(tester, keyedButton(tester, profile('save')));
          await tester.pump();
          expect(port.saves, 2);
          gate.complete(port.accepted);
          await tester.pumpAndSettle();
          expect(profile('save'), findsNothing);
          expect(profile('reload'), findsNothing);
          expect(find.text('完成'), findsOneWidget);
          activate(tester, keyedButton(tester, profile('close')));
          await tester.pumpAndSettle();
          expect(result?['userMobile'], 'fixture-contact-new');
          expect(trigger.hasFocus, isTrue);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete(port.accepted);
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    for (final unmount in [false, true]) {
      testWidgets(
        'profile ${suite.name} ${unmount ? "ignores late UI result after unmount" : "rejects late result from old context"}',
        (tester) async {
          size(tester, const Size(900, 900));
          final gate = Completer<MarketRow>();
          final port = InnerProfilePort()..profileGate = gate;
          final c = MarketplaceController(port);
          final trigger = FocusNode();
          var returned = false;
          MarketRow? result;
          try {
            await tester.pumpWidget(
              app(
                c,
                suite,
                trigger,
                isProfile: true,
                result: (v) {
                  returned = true;
                  result = v;
                },
              ),
            );
            await tester.pumpAndSettle();
            await open(tester, isProfile: true);
            await tester.enterText(
              find.byKey(const ValueKey('trade-profile-contact')),
              'late-fixture-contact',
            );
            await tester.tap(profile('save'));
            await tester.pump();
            expect(port.saves, 1);
            if (unmount) {
              await tester.pumpWidget(const SizedBox.shrink());
            } else {
              c.contextChanged();
            }
            gate.complete(port.accepted);
            await tester.pump();
            await tester.pump();
            if (!unmount) {
              await tester.pumpAndSettle();
              final semantics = tester.ensureSemantics();
              await tester.pump();
              try {
                disabled(keyedButton(tester, profile('save')));
                await tester.tap(profile('close'));
                await tester.pumpAndSettle();
                expect(returned, isTrue);
                expect(result, isNull);
              } finally {
                semantics.dispose();
              }
            }
            expect(port.saves, 1);
            expect(port.writes, 0);
            expect(find.byType(SnackBar), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            if (!gate.isCompleted) {
              gate.complete(port.accepted);
            }
            await tester.pump();
            await tester.pumpWidget(const SizedBox.shrink());
            c.dispose();
            trigger.dispose();
          }
        },
      );
    }
  }
}
