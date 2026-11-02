import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';
import 'package:starbridge_flutter/features/settings/help_support_settings_page.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3dc_actions_test.dart' show hitRow;
import 'interaction_batch3dh_test.dart' show HelpPendingPort, stats, update;
import 'interaction_batch3i_test.dart' show scopedApp;

const names = [
  'applicationUpdates.check',
  'helpSupport.history',
  'helpSupport.stats',
];
Map<String, dynamic> payload(String name) => switch (name) {
  'helpSupport.stats' => stats(),
  'helpSupport.history' => {
    'schemaVersion': 1,
    'edition': 'starbridge',
    'entries': [
      {
        'version': 'fixture',
        'publishedOn': '2026-10-15',
        'title': 'Fixture',
        'summary': 'Retained summary',
        'highlights': ['Line'],
      },
    ],
  },
  _ => update,
};
Finder reload(String name) => find.byKey(Key('help-read-reload-$name'));
String oldLabel(String name) => switch (name) {
  'helpSupport.stats' => '9',
  'helpSupport.history' => 'vfixture · Fixture',
  _ => 'fixture',
};

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final change in ['name', 'port']) {
      testWidgets(
        '$suite pending wait identity survives $change-only replacement without a new read',
        (t) async {
          size(t, const Size(1400, 1100));
          final a = HelpPendingPort(), b = HelpPendingPort();
          final settings =
              ValueNotifier<(String, HelpPendingPort, InteractionSource)>((
                names.first,
                a,
                InteractionSource.keyboard,
              ));
          try {
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder<
                  (String, HelpPendingPort, InteractionSource)
                >(
                  valueListenable: settings,
                  builder: (context, value, _) => starBridgeInitialReadViewport(
                    context,
                    source: value.$3,
                    child: HelpSupportReadCard(
                      key: const ValueKey('read-fixture'),
                      name: value.$1,
                      port: value.$2,
                    ),
                  ),
                ),
                suite,
              ),
            );
            await t.pump();
            await t.pump();
            final card = t.state(find.byType(HelpSupportReadCard));
            final wait = t.state(find.byType(HelpSupportWaiting));
            expect(a.reads.map((r) => r.$1), [names.first]);
            expect(find.byType(SuiteProgressBar), findsNothing);
            settings.value = (
              change == 'name' ? 'another.update' : names.first,
              change == 'port' ? b : a,
              InteractionSource.pointer,
            );
            await t.pump();
            await t.pump();
            expect(t.state(find.byType(HelpSupportReadCard)), same(card));
            expect(a.reads.map((r) => r.$1), [names.first]);
            expect(b.reads, isEmpty);
            expect(t.state(find.byType(HelpSupportWaiting)), same(wait));
            expect(
              find.byType(SuiteProgressBar),
              findsNothing,
              reason: 'changing presentation cannot relabel the admitted keyboard wait',
            );
          } finally {
            await t.pumpWidget(const SizedBox());
            for (final r in a.reads) {
              if (!r.$2.isCompleted) r.$2.complete(update);
            }
            for (final r in b.reads) {
              if (!r.$2.isCompleted) r.$2.complete(update);
            }
            await t.pump();
            settings.dispose();
          }
        },
      );
    }
    for (final host in ['viewport', 'dialog']) {
      testWidgets(
        '$suite initial updates in keyboard $host inherits the original opening source',
        (t) async {
          size(t, const Size(1400, 1100));
          final port = HelpPendingPort();
          try {
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) {
                    if (host == 'viewport') {
                      return starBridgeInitialReadViewport(
                        context,
                        source: InteractionSource.keyboard,
                        child: HelpSupportSettingsPage(
                          port: port,
                          initialTopic: HelpSupportTopic.updates,
                        ),
                      );
                    }
                    return StarBridgeActionButton(
                      controlKey: const Key('open-help-fixture'),
                      onActivate: (_) => showStarBridgeDialog<void>(
                        context,
                        source: InteractionSource.keyboard,
                        builder: (_) => HelpSupportSettingsPage(
                          port: port,
                          initialTopic: HelpSupportTopic.updates,
                        ),
                      ),
                      child: const Text('Open'),
                    );
                  },
                ),
                suite,
              ),
            );
            if (host == 'dialog') {
              await t.pumpAndSettle();
              await fire(t, 'pointer', 'open-help-fixture');
            }
            await t.pump();
            await t.pump();
            expect(port.reads, hasLength(3));
            expect(find.byType(SuiteProgressBar), findsNothing);
          } finally {
            for (final r in port.reads) {
              if (!r.$2.isCompleted) r.$2.complete(payload(r.$1));
            }
            await t.pumpWidget(const SizedBox());
            await t.pump();
          }
        },
      );
    }
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final name in names) {
        testWidgets(
          '$suite $input $name original admission and retained data through failed reload',
          (t) async {
            size(t, const Size(1400, 1100));
            final sem = t.ensureSemantics();
            final port = HelpPendingPort();
            try {
              await t.pumpWidget(
                scopedApp(
                  Builder(
                    builder: (context) => starBridgeInitialReadViewport(
                      context,
                      source: input == 'pointer'
                          ? InteractionSource.pointer
                          : InteractionSource.keyboard,
                      child: HelpSupportReadCard(name: name, port: port),
                    ),
                  ),
                  suite,
                ),
              );
              await t.pump();
              await t.pump();
              expect(port.reads.map((r) => r.$1), [name]);
              expect(
                find.byType(SuiteProgressBar),
                input == 'pointer' ? findsOneWidget : findsNothing,
              );
              final action = t.widget<StarBridgeActionButton>(
                find.ancestor(
                  of: reload(name),
                  matching: find.byType(StarBridgeActionButton),
                ),
              );
              expect(action.onActivate, isNull);
              port.reads.single.$2.complete(payload(name));
              await t.pumpAndSettle();
              expect(find.text(oldLabel(name)), findsOneWidget);
              await fire(t, input, 'help-read-reload-$name');
              await t.pump();
              expect(port.reads, hasLength(2));
              expect(find.text(oldLabel(name)), findsOneWidget);
              expect(
                find.byType(SuiteProgressBar),
                input == 'pointer' ? findsOneWidget : findsNothing,
              );
              port.reads.last.$2.completeError(StateError('failed reload'));
              await t.pumpAndSettle();
              expect(find.text(oldLabel(name)), findsOneWidget);
              expect(find.text('暂时无法读取，请重试。'), findsOneWidget);
              await t.pump(const Duration(seconds: 1));
              expect(port.reads, hasLength(2));
              // A real pointer retry overrides a keyboard opening fact.
              await fire(t, 'pointer', 'help-read-reload-$name');
              await t.pump();
              expect(find.byType(SuiteProgressBar), findsOneWidget);
              port.reads.last.$2.complete(payload(name));
              await t.pumpAndSettle();
              expect(port.reads, hasLength(3));
              expect(t.takeException(), isNull);
            } finally {
              for (final r in port.reads) {
                if (!r.$2.isCompleted) r.$2.complete(payload(r.$1));
              }
              await t.pumpWidget(const SizedBox());
              await t.pump();
              sem.dispose();
            }
          },
        );
      }
    }
    for (final name in names) {
      testWidgets(
        '$suite $name 22-second timeout, explicit retry and retired late future',
        (t) async {
          size(t, const Size(1400, 1100));
          final port = HelpPendingPort();
          await t.pumpWidget(
            scopedApp(HelpSupportReadCard(name: name, port: port), suite),
          );
          await t.pump();
          await t.pump();
          await t.pump(const Duration(seconds: 21));
          expect(find.text('暂时无法读取，请重试。'), findsNothing);
          await t.pump(const Duration(seconds: 1));
          await t.pump();
          expect(find.text('暂时无法读取，请重试。'), findsOneWidget);
          await fire(t, 'pointer', 'help-read-reload-$name');
          await t.pump();
          expect(port.reads, hasLength(2));
          port.reads.first.$2.complete(payload(name));
          await t.pump();
          expect(find.text(oldLabel(name)), findsNothing);
          port.reads.last.$2.complete(payload(name));
          await t.pumpAndSettle();
          expect(find.text(oldLabel(name)), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      '$suite actual keyboard topic opening and pending source freeze across rapid pointer return',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = HelpPendingPort();
        await t.pumpWidget(
          scopedApp(HelpSupportSettingsPage(port: port), suite),
        );
        await t.pumpAndSettle();
        await hitRow(t, 'keyboard', 'help-topic-button-updates');
        await t.pump();
        await t.pump();
        expect(port.reads, hasLength(3));
        expect(find.byType(SuiteProgressBar), findsNothing);
        await hitRow(t, 'pointer', 'help-topic-button-notices');
        await t.pump();
        expect(
          find.byType(SuiteProgressBar),
          findsNothing,
          reason: 'outgoing keyboard requests cannot become pointer waits',
        );
        await hitRow(t, 'pointer', 'help-topic-button-updates');
        await t.pump();
        await t.pump();
        expect(port.reads, hasLength(6));
        expect(find.byType(SuiteProgressBar), findsNWidgets(3));
        for (final r in port.reads) {
          r.$2.complete(payload(r.$1));
        }
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite live local reduce stops waits without new reads or replacing stored data',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = HelpPendingPort();
        final reduce = ValueNotifier(false);
        try {
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder<bool>(
                valueListenable: reduce,
                builder: (_, value, _) => StarBridgeInteractionConfiguration(
                  suite: suite,
                  reduceMotion: value,
                  child: HelpSupportReadCard(name: names.first, port: port),
                ),
              ),
              suite,
            ),
          );
          await t.pump();
          await t.pump();
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          reduce.value = true;
          await t.pump();
          await t.pump();
          expect(find.byType(SuiteProgressBar), findsNothing);
          expect(port.reads, hasLength(1));
          reduce.value = false;
          await t.pump();
          await t.pump();
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          port.reads.single.$2.complete(update);
          await t.pumpAndSettle();
        } finally {
          if (port.reads.isNotEmpty && !port.reads.single.$2.isCompleted) {
            port.reads.single.$2.complete(update);
          }
          await t.pumpWidget(const SizedBox());
          await t.pump();
          reduce.dispose();
        }
      },
    );
    for (final accounts in <Object?>[null, -1, 'invalid', 0, 42, 987654321]) {
      testWidgets(
        '$suite optional account=$accounts retains unknown, zero and hours',
        (t) async {
          size(t, const Size(1400, 1100));
          final port = HelpPendingPort();
          await t.pumpWidget(
            scopedApp(HelpSupportReadCard(name: names.last, port: port), suite),
          );
          await t.pump();
          port.reads.single.$2.complete(stats(accounts));
          await t.pumpAndSettle();
          expect(
            find.text('暂不可用'),
            accounts is! int || accounts < 0 ? findsOneWidget : findsNothing,
          );
          if (accounts is int && accounts >= 0) {
            expect(find.text('$accounts'), findsOneWidget);
          }
          expect(find.text('1.0'), findsOneWidget);
          expect(find.text('暂时无法读取，请重试。'), findsNothing);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final bad in [
      <String, dynamic>{...stats(), 'downloadCount': -1},
      <String, dynamic>{...stats(), 'onlineUserCount': '3'},
      <String, dynamic>{...stats(), 'updatedAt': 'bad'},
    ]) {
      testWidgets(
        '$suite invalid required statistics remain failed ${bad.toString()}',
        (t) async {
          size(t, const Size(1400, 1100));
          final port = HelpPendingPort();
          await t.pumpWidget(
            scopedApp(HelpSupportReadCard(name: names.last, port: port), suite),
          );
          await t.pump();
          port.reads.single.$2.complete(bad);
          await t.pumpAndSettle();
          expect(find.text('暂时无法读取，请重试。'), findsOneWidget);
          expect(find.text('1.0'), findsNothing);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
