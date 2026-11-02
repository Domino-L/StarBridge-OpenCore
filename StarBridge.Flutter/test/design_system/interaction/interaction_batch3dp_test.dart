import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/community_sharing_dialog.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import 'interaction_batch3do_test.dart' as fixture;

final sharingTarget = CommunitySharingTarget(
  code: 'B',
  name: 'Organization B',
  joinedAt: '2026-09-30T00:00:00Z',
);

class SharingProbe {
  final calls = <String>[];
  final fields = <int>[];
  final hangar = <bool>[];
  final events = <EventSharingChoice>[];
  final gates = List.generate(3, (_) => Completer<bool>());
  CommunitySharingDialog dialog() => CommunitySharingDialog(
    target: sharingTarget,
    onSaveHangar: (value) {
      calls.add('hangar');
      hangar.add(value);
      return gates[0].future;
    },
    onSaveEvents: (value) {
      calls.add('events');
      events.add(value);
      return gates[1].future;
    },
    onSave: (value) {
      calls.add('status');
      fields.add(value.fields);
      return gates[2].future;
    },
  );
}

Future<void> openSharing(
  WidgetTester tester,
  Widget dialog,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) async {
  await tester.pumpWidget(
    fixture.scopedApp(
      Builder(
        builder: (context) => GestureDetector(
          onTap: () => showStarBridgeDialog<void>(
            context,
            source: InteractionSource.programmatic,
            barrierDismissible: false,
            builder: (_) => dialog,
          ),
          child: const Text('Open'),
        ),
      ),
      suite,
      reduce: reduce,
      light: light,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Widget sharingApp(
  Widget dialog,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
  double scale = 1,
  Locale locale = const Locale('zh', 'CN'),
}) {
  final base = fixture.scopedApp(
    Builder(
      builder: (context) => GestureDetector(
        onTap: () => showStarBridgeDialog<void>(
          context,
          source: InteractionSource.programmatic,
          barrierDismissible: false,
          builder: (_) => dialog,
        ),
        child: const Text('Open'),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
    locale: locale,
  ) as MaterialApp;
  return RepaintBoundary(
    key: const Key('3dp-frame'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: base.supportedLocales,
      localizationsDelegates: base.localizationsDelegates,
      theme: base.theme,
      themeAnimationDuration: Duration.zero,
      home: base.home,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: base.builder!(context, child),
      ),
    ),
  );
}

HelpSupportAction sharingAction(WidgetTester t, String action) =>
    t.widget<HelpSupportAction>(
      find.byWidgetPredicate(
        (w) =>
            w is HelpSupportAction &&
            w.controlKey == Key('community-sharing-$action'),
      ),
    );

Future<void> submit(
  WidgetTester t,
  String source, {
  String action = 'confirm',
}) => fixture.act(
  t,
  find.byKey(Key('community-sharing-$action')),
  source,
  action == 'none' ? '不共享' : '确认共享',
);

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '${suite.name}/$source staged pending never skips or duplicates consent',
        (t) async {
          fixture.size(t, const Size(960, 900));
          final semantics = t.ensureSemantics();
          try {
            final p = SharingProbe();
            await openSharing(t, p.dialog(), suite);
            expect(p.calls, isEmpty);
            final old = sharingAction(t, 'confirm').onActivate!;
            await submit(t, source);
            await t.pump();
            old(InteractionSource.pointer);
            expect(p.calls, ['hangar']);
            expect(p.hangar, [true]);
            final wait = t.widget<HelpSupportWaiting>(
              find.byType(HelpSupportWaiting),
            );
            expect(
              wait.source,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(sharingAction(t, 'confirm').onActivate, isNull);
            expect(sharingAction(t, 'none').onActivate, isNull);
            for (final checkbox in t.widgetList<StarBridgeCheckboxTile>(
              find.byType(StarBridgeCheckboxTile),
            )) {
              expect(checkbox.onChanged, isNull);
            }
            expect(
              find.byType(SuiteProgressBar),
              source == 'pointer' ? findsOneWidget : findsNothing,
            );
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.tapAt(const Offset(4, 4));
            await t.pump();
            expect(find.byType(CommunitySharingDialog), findsOneWidget);
            p.gates[0].complete(true);
            await t.pump();
            expect(p.calls, ['hangar', 'events']);
            expect(p.events.single.effectiveTypes, EventSharingChoice.allTypes);
            p.gates[1].complete(true);
            await t.pump();
            expect(p.calls, ['hangar', 'events', 'status']);
            expect(p.fields, [15]);
            final route = ModalRoute.of(
              t.element(find.byType(CommunitySharingDialog)),
            )!;
            p.gates[2].complete(true);
            await t.pump();
            if (source != 'pointer') {
              expect(route.animation!.value, 0);
              await t.pump();
              expect(
                find.byType(CommunitySharingDialog),
                findsNothing,
                reason: 'Keyboard/reader completion has no route exit tail.',
              );
            }
            await t.pumpAndSettle();
            expect(find.byType(CommunitySharingDialog), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    for (final failedStage in [0, 1, 2]) {
      testWidgets(
        '${suite.name} failure $failedStage preserves choices and stops later owners',
        (t) async {
          fixture.size(t, const Size(960, 900));
          final p = SharingProbe();
          await openSharing(t, p.dialog(), suite);
          await t.tap(find.byKey(const Key('community-sharing-8')));
          await t.pump();
          await submit(t, 'pointer');
          await t.pump();
          for (var stage = 0; stage <= failedStage; stage++) {
            p.gates[stage].complete(stage < failedStage);
            await t.pump();
          }
          await t.pumpAndSettle();
          expect(p.calls.length, failedStage + 1);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(
            t
                .widget<StarBridgeCheckboxTile>(
                  find.byKey(const Key('community-sharing-8')),
                )
                .value,
            isFalse,
          );
          expect(sharingAction(t, 'confirm').onActivate, isNotNull);
          expect(
            find.text(
              [
                '机库设置未能确认，选择已保留。请重试。',
                '活动事件设置未能确认，选择已保留。请重试。',
                '部分设置未能保存，选择已保留。请重试。',
              ][failedStage],
            ),
            findsOneWidget,
          );
          await t.pumpWidget(const SizedBox());
        },
      );
      testWidgets(
        '${suite.name} unmount during stage $failedStage blocks later stages and stale pop',
        (t) async {
          fixture.size(t, const Size(960, 900));
          final p = SharingProbe();
          await openSharing(t, p.dialog(), suite);
          await submit(t, 'pointer');
          await t.pump();
          for (var stage = 0; stage < failedStage; stage++) {
            p.gates[stage].complete(true);
            await t.pump();
          }
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(const MaterialApp(home: Text('New owner')));
          p.gates[failedStage].complete(true);
          await t.pumpAndSettle();
          expect(p.calls.length, failedStage + 1);
          expect(find.text('New owner'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets('${suite.name} none is an explicit three-owner refusal', (
      t,
    ) async {
      fixture.size(t, const Size(960, 900));
      final p = SharingProbe();
      await openSharing(t, p.dialog(), suite);
      await submit(t, 'pointer', action: 'none');
      await t.pump();
      expect(p.hangar, [false]);
      for (var stage = 0; stage < 3; stage++) {
        p.gates[stage].complete(true);
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(p.calls, ['hangar', 'events', 'status']);
      expect(p.events.single.enabled, isFalse);
      expect(p.fields, [0]);
    });
    testWidgets(
      '${suite.name} unavailable optional owners remain disabled without writes on open',
      (t) async {
        fixture.size(t, const Size(960, 900));
        final fields = <int>[];
        await openSharing(
          t,
          CommunitySharingDialog(
            target: sharingTarget,
            onSave: (value) async {
              fields.add(value.fields);
              return true;
            },
          ),
          suite,
        );
        for (final key in [
          'hangar',
          'events',
          'event-presence',
          'event-life',
        ]) {
          final checkbox = t.widget<StarBridgeCheckboxTile>(
            find.byKey(Key('community-sharing-$key')),
          );
          expect(checkbox.onChanged, isNull);
          expect(checkbox.value, isFalse);
        }
        expect(fields, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
