// Batch 4: first load (25), progress (28), chat (31), empty states (32).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Widget _host(InteractionSuite suite, Widget child, {bool reduce = false}) => MaterialApp(
  home: Scaffold(
    body: InteractionScope(
      data: InteractionData(suite: suite, palette: palette, reduceMotion: reduce),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: child)),
      ),
    ),
  ),
);

void main() {
  group('25 first load', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: says what it reads; reduced motion is static', (t) async {
        await t.pumpWidget(_host(suite, const SuiteSkeleton(label: 'Reading fleet…'), reduce: true));
        await t.pump();
        expect(find.text('Reading fleet…'), findsOneWidget);
        expect(t.hasRunningAnimations, isFalse);
        expect(find.textContaining('%'), findsNothing);
      });
    }
  });

  group('28 progress', () {
    Future<void> pumpBar(WidgetTester t, InteractionSuite suite, double? v, ProgressPhase phase, {bool reduce = false}) =>
        t.pumpWidget(_host(suite, SuiteProgressBar(value: v, phase: phase), reduce: reduce));

    testWidgets('eases toward the real value and never runs backwards', (t) async {
      await pumpBar(t, InteractionSuite.rail, 0.2, ProgressPhase.running);
      await pumpBar(t, InteractionSuite.rail, 0.6, ProgressPhase.running);
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
      // A correction downwards applies at once.
      await pumpBar(t, InteractionSuite.rail, 0.3, ProgressPhase.running);
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
    });

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: unknown total animates; reduced motion is static', (t) async {
        await pumpBar(t, suite, null, ProgressPhase.running);
        await t.pump(const Duration(milliseconds: 100));
        expect(t.hasRunningAnimations, isTrue);
        await pumpBar(t, suite, null, ProgressPhase.running, reduce: true);
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('failure and cancel do not celebrate', (t) async {
      for (final phase in [ProgressPhase.failed, ProgressPhase.cancelled]) {
        await pumpBar(t, InteractionSuite.glow, 0.5, ProgressPhase.running);
        await t.pumpAndSettle();
        await pumpBar(t, InteractionSuite.glow, 0.5, phase);
        await t.pump();
        expect(t.hasRunningAnimations, isFalse, reason: '$phase');
      }
    });

    testWidgets('done plays one confirmation, then rests', (t) async {
      await pumpBar(t, InteractionSuite.scan, 0.9, ProgressPhase.running);
      await t.pumpAndSettle();
      await pumpBar(t, InteractionSuite.scan, 1, ProgressPhase.done);
      await t.pump(const Duration(milliseconds: 20));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
    });
  });

  group('32 empty state', () {
    testWidgets('static, with an action only when there is something to do', (t) async {
      var pressed = 0;
      await t.pumpWidget(
        _host(
          InteractionSuite.glow,
          SuiteEmptyState(icon: Icons.inbox, title: 'Empty', message: 'Import first', actionLabel: 'Import', onAction: () => pressed++),
        ),
      );
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      await t.tap(find.text('Import'));
      await t.pumpAndSettle();
      expect(pressed, 1);
      await t.pumpWidget(_host(InteractionSuite.glow, const SuiteEmptyState(icon: Icons.lock, title: 'No access', message: 'Ask an officer')));
      expect(find.byType(SuitePressable), findsNothing);
    });
  });

  group('31 chat', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: only fresh messages animate; text is intact at once', (t) async {
        await t.pumpWidget(_host(suite, const SuiteMessageBubble(text: 'old message', mine: false)));
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        await t.pumpWidget(_host(suite, const SuiteMessageBubble(key: ValueKey('n'), text: 'new message', mine: true, fresh: true)));
        expect(find.text('new message'), findsOneWidget);
        await t.pump();
        if (suite != InteractionSuite.standard) expect(t.hasRunningAnimations, isTrue);
        await t.pumpAndSettle();
        expect(t.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('failed message stays with a retry', (t) async {
      var retried = 0;
      await t.pumpWidget(
        _host(InteractionSuite.rail, SuiteMessageBubble(text: 'draft text', mine: true, status: MessageStatus.failed, onRetry: () => retried++)),
      );
      expect(find.text('draft text'), findsOneWidget);
      expect(find.text('发送失败'), findsOneWidget);
      await t.tap(find.text('重试'));
      await t.pumpAndSettle();
      expect(retried, 1);
    });

    testWidgets('new-messages pill appears once, updates, and hides', (t) async {
      var count = 0;
      late StateSetter set;
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteNewMessagesPill(count: count, onTap: () => s(() => count = 0));
            },
          ),
        ),
      );
      expect(find.text('条新消息'), findsNothing);
      set(() => count = 1);
      await t.pumpAndSettle();
      expect(find.text('条新消息'), findsOneWidget);
      set(() => count = 4);
      await t.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
      await t.tap(find.text('条新消息'));
      await t.pumpAndSettle();
      expect(find.text('条新消息'), findsNothing);
    });
  });
}
