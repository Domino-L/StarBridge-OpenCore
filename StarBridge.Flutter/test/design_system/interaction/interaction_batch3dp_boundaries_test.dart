import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/community_sharing_dialog.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import '../../app/community_sharing_flow_test.dart' as flow;
import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dp_test.dart';

Future<void> check(WidgetTester t, String key, String source) async {
  final target = find.byKey(Key(key));
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'reader') {
    final label = t.widget<StarBridgeCheckboxTile>(target).label;
    final nodes = fixture
        .exposedNodes(t)
        .where(
          (node) =>
              node.getSemanticsData().label == label &&
              node.getSemanticsData().hasAction(SemanticsAction.tap),
        )
        .toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  } else {
    final checkbox = t.widget(
      find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is Checkbox || w is SuiteCheckbox,
        ),
      ),
    );
    final focus = checkbox is Checkbox
        ? checkbox.focusNode!
        : (checkbox as SuiteCheckbox).focusNode!;
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  }
  await t.pump();
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '${suite.name}/$source selection remains immediate and never writes consent',
        (t) async {
          fixture.size(t, const Size(960, 900));
          final semantics = t.ensureSemantics();
          try {
            final p = SharingProbe();
            await openSharing(t, p.dialog(), suite);
            for (final value in [false, true, false, true]) {
              await check(t, 'community-sharing-1', source);
              expect(
                t
                    .widget<StarBridgeCheckboxTile>(
                      find.byKey(const Key('community-sharing-1')),
                    )
                    .value,
                value,
              );
              if (suite != InteractionSuite.standard) {
                final checkbox = t.widget<SuiteCheckbox>(
                  find.descendant(
                    of: find.byKey(const Key('community-sharing-1')),
                    matching: find.byType(SuiteCheckbox),
                  ),
                );
                expect(
                  checkbox.changeSource,
                  source == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                );
              }
              await t.pump(const Duration(milliseconds: 40));
            }
            expect(p.calls, isEmpty);
            await check(t, 'community-sharing-events', source);
            expect(
              t
                  .widget<StarBridgeCheckboxTile>(
                    find.byKey(const Key('community-sharing-event-location')),
                  )
                  .onChanged,
              isNull,
            );
            for (final bit in [1, 2, 4, 8]) {
              await check(t, 'community-sharing-$bit', source);
            }
            await check(t, 'community-sharing-hangar', source);
            expect(sharingAction(t, 'confirm').onActivate, isNull);
            expect(sharingAction(t, 'none').onActivate, isNotNull);
            expect(p.calls, isEmpty);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '${suite.name} real automatic flow uses live suite route and invalidates only its prompt',
      (t) async {
        fixture.size(t, const Size(960, 900));
        final h = await flow.Harness.create(t);
        final base = fixture.scopedApp(const SizedBox(), suite) as MaterialApp;
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: h.key,
            navigatorObservers: [h.queue],
            locale: base.locale,
            supportedLocales: base.supportedLocales,
            localizationsDelegates: base.localizationsDelegates,
            theme: base.theme,
            builder: base.builder,
            home: const Scaffold(),
          ),
        );
        await t.pumpAndSettle();
        await h.controller.refresh();
        await h.settle(t);
        final route = ModalRoute.of(
          t.element(find.byType(CommunitySharingDialog)),
        );
        expect(route, isA<StarBridgeDialogRoute<void>>());
        expect(
          (route as StarBridgeDialogRoute).instant,
          isFalse,
          reason: 'Background membership discovery is programmatic, not the previous command.',
        );
        expect(route.barrierDismissible, isFalse);
        expect(h.port.writes, 0);
        final liveSuite = suite == InteractionSuite.glow
            ? InteractionSuite.scan
            : InteractionSuite.glow;
        final changed = fixture.scopedApp(
          const SizedBox(),
          liveSuite,
          light: true,
          reduce: true,
        ) as MaterialApp;
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: h.key,
            navigatorObservers: [h.queue],
            locale: changed.locale,
            supportedLocales: changed.supportedLocales,
            localizationsDelegates: changed.localizationsDelegates,
            theme: changed.theme,
            themeAnimationDuration: Duration.zero,
            builder: changed.builder,
            home: const Scaffold(),
          ),
        );
        await t.pump();
        await t.pump();
        final live = InteractionScope.of(
          t.element(find.byType(CommunitySharingDialog)),
        );
        expect(live.suite, liveSuite);
        expect(live.reduceMotion, isTrue);
        expect(live.palette.brightness, Brightness.light);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.tapAt(const Offset(4, 4));
        await t.pump();
        expect(route.isActive, isTrue);
        h.ready = false;
        h.port.events.add(null);
        await h.settle(t);
        expect(route.isActive, isFalse);
        expect(h.port.writes, 0);
        expect(find.byType(CommunitySharingDialog), findsNothing);
        await h.dispose(t);
      },
    );
    testWidgets(
      '${suite.name} retry uses a new wait identity and latest explicit source',
      (t) async {
        fixture.size(t, const Size(960, 900));
        var tries = 0;
        final retry = Completer<bool>();
        final dialog = CommunitySharingDialog(
          target: sharingTarget,
          onSaveHangar: (_) async {
            tries++;
            if (tries == 1) throw StateError('unconfirmed');
            return retry.future;
          },
          onSave: (_) async => true,
        );
        await openSharing(t, dialog, suite);
        await submit(t, 'pointer');
        await t.pumpAndSettle();
        expect(find.text('机库设置未能确认，选择已保留。请重试。'), findsOneWidget);
        await submit(t, 'keyboard');
        await t.pump();
        final wait = t.widget<HelpSupportWaiting>(
          find.byType(HelpSupportWaiting),
        );
        expect(wait.key, const ValueKey(('community-sharing-wait', 2)));
        expect(wait.source, InteractionSource.keyboard);
        expect(find.byType(SuiteProgressBar), findsNothing);
        expect(tries, 2);
        retry.complete(true);
        await t.pump();
        await t.pump();
        expect(find.byType(CommunitySharingDialog), findsNothing);
      },
    );
  }
}
