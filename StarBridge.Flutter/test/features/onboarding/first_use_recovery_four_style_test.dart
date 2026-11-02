import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/first_use_recovery_flow.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/onboarding/first_use_recovery_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp, keyPress;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name} late recheck preserves newer manual draft', (
      t,
    ) async {
      late BuildContext entry;
      await t.pumpWidget(
        scopedApp(
          Builder(
            builder: (context) {
              entry = context;
              return const SizedBox();
            },
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      final held = Completer<String?>();
      final notice = FirstUseRecoveryNotice(
        'pending',
        () => true,
        () => held.future,
      );
      final result = showFirstUseRecovery(entry, notice);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('first-use-recovery-recheck')));
      await t.pump();
      final draft = Navigator.of(entry).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('unsaved draft')),
        ),
      );
      await t.pumpAndSettle();
      held.complete('ready');
      await t.pumpAndSettle();
      expect(find.text('unsaved draft'), findsOneWidget);
      expect(await result, FirstUseRecoveryChoice.keepCurrent);
      Navigator.of(entry).pop();
      await t.pumpAndSettle();
      await draft;
      expect(t.takeException(), isNull);
      notice.dispose();
    });
    for (final reduce in [false, true]) {
      testWidgets('${suite.name} reduce=$reduce recovery uses suite route', (
        t,
      ) async {
        late BuildContext entry;
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) {
                entry = context;
                return const SizedBox();
              },
            ),
            suite,
            reduce: reduce,
          ),
        );
        await t.pumpAndSettle();
        final notice = FirstUseRecoveryNotice(
          'pending',
          () => true,
          () async => 'pending',
        );
        final result = showFirstUseRecovery(entry, notice);
        await t.pump();
        await t.pump();
        final context = t.element(find.byType(AlertDialog));
        final route = ModalRoute.of(context)!;
        expect(route, isA<StarBridgeDialogRoute<FirstUseRecoveryChoice>>());
        expect(route.barrierDismissible, isFalse);
        expect(InteractionScope.of(context).suite, suite);
        if (reduce) expect(route.animation!.value, 1);
        await t.pumpAndSettle();
        await t.tapAt(const Offset(1, 1));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await keyPress(t, find.byKey(const Key('first-use-recovery-keep')));
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'keyboard exit has no animation tail',
        );
        expect(await result, FirstUseRecoveryChoice.keepCurrent);
        expect(t.takeException(), isNull);
        notice.dispose();
      });
    }
  }
}
