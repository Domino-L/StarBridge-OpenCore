import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/settings/application_support_dialog.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3df_test.dart' show SupportPort, supportSnapshot;
import 'interaction_batch3df_flows_test.dart'
    show SupportFixture, readMotion, frames;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite first inline click on const loading is unknown static and still inspects',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = SupportPort()..delayed = true;
        final owner = createApplicationSupportModule(port);
        try {
          await t.pumpWidget(
            scopedApp(ApplicationSupportPanel(module: owner), suite),
          );
          await t.pumpAndSettle();
          expect(port.inspections, 0);
          await fire(t, 'pointer', 'diagnostics-run');
          await frames(t);
          expect(port.inspections, 1);
          expect(readMotion(t).staticWait, isTrue);
          expect(readMotion(t).source, InteractionSource.programmatic);
          expect(find.byType(SuiteProgressBar), findsNothing);
          port.pending.single.complete(supportSnapshot);
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('application-support-ready')),
            findsOneWidget,
          );
          expect(port.inspections, 1);
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
    for (final failFirst in [false, true]) {
      testWidgets(
        '$suite queued rechecks failFirst=$failFirst keep one queued read and retire origin',
        (t) async {
          final h = SupportFixture();
          try {
            await h.mount(t, suite);
            h.port.delayed = true;
            final state = readMotion(t);
            final first = runStarBridgeActivation(
              InteractionSource.pointer,
              state.refresh,
            );
            await frames(t);
            expect(state.source, InteractionSource.pointer);
            await runStarBridgeActivation(
              InteractionSource.keyboard,
              state.refresh,
            );
            await runStarBridgeActivation(
              InteractionSource.programmatic,
              state.refresh,
            );
            await frames(t);
            expect(h.port.inspections, 2);
            expect(state.source, InteractionSource.pointer);
            expect(state.staticWait, isFalse);
            if (failFirst) {
              h.port.pending.first.completeError(
                const ApplicationSupportException(
                  ApplicationSupportFailure.timeout,
                ),
              );
            } else {
              h.port.pending.first.complete(supportSnapshot);
            }
            await frames(t);
            expect(h.port.inspections, 3);
            expect(h.owner.projection.value.loading, isTrue);
            expect(state.source, InteractionSource.programmatic);
            expect(state.staticWait, isTrue);
            expect(find.byType(SuiteProgressBar), findsNothing);
            h.port.pending.last.complete(supportSnapshot);
            await first;
            await t.pumpAndSettle();
            expect(h.port.inspections, 3);
            expect(h.owner.projection.value.snapshot, same(supportSnapshot));
            expect(t.takeException(), isNull);
          } finally {
            await h.close(t);
          }
        },
      );
    }
    testWidgets(
      '$suite module swap retires old listener and old finally cannot reset new request',
      (t) async {
        final h = SupportFixture();
        final nextPort = SupportPort();
        final nextOwner = createApplicationSupportModule(nextPort);
        try {
          await h.mount(t, suite);
          h.port.delayed = true;
          final old = runStarBridgeActivation(
            InteractionSource.pointer,
            readMotion(t).refresh,
          );
          await frames(t);
          await nextOwner.initialize();
          nextPort.delayed = true;
          await t.pumpWidget(
            scopedApp(ApplicationSupportPanel(module: nextOwner), suite),
          );
          await t.pumpAndSettle();
          await fire(t, 'keyboard', 'application-support-refresh');
          await frames(t);
          expect(readMotion(t).source, InteractionSource.keyboard);
          h.port.pending.single.complete(supportSnapshot);
          await old;
          await frames(t);
          expect(readMotion(t).source, InteractionSource.keyboard);
          expect(nextOwner.projection.value.loading, isTrue);
          nextPort.pending.single.complete(supportSnapshot);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
          nextOwner.dispose();
        }
      },
    );
    testWidgets(
      '$suite unmount does not dispose borrowed module and late read remains owned',
      (t) async {
        final h = SupportFixture();
        try {
          await h.mount(t, suite);
          h.port.delayed = true;
          await fire(t, 'pointer', 'application-support-refresh');
          await frames(t);
          await t.pumpWidget(scopedApp(const SizedBox(), suite));
          await t.pump();
          expect(h.port.closes, 0);
          h.port.pending.single.complete(supportSnapshot);
          await frames(t);
          expect(h.owner.projection.value.snapshot, same(supportSnapshot));
          expect(t.takeException(), isNull);
          await t.pumpWidget(h.page(suite));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('diagnostics-run')), findsOneWidget);
          expect(h.port.inspections, 2);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite unhealthy directory stays disabled without widening other gates',
      (t) async {
        final h = SupportFixture();
        h.port.snapshot = ApplicationSupportSnapshot(
          hasIssues: true,
          hasUnavailableChecks: false,
          dataDirectory: const ApplicationSupportCheck(
            state: ApplicationSupportCheckState.actionRequired,
            detail: 'pathMissing',
          ),
          gameLog: supportSnapshot.gameLog,
          startup: supportSnapshot.startup,
          installation: supportSnapshot.installation,
        );
        try {
          await h.mount(t, suite);
          final open = find.ancestor(
            of: find.byKey(
              const Key('application-support-open-data-directory'),
            ),
            matching: find.byType(StarBridgeActionButton),
          );
          expect(t.widget<StarBridgeActionButton>(open).onActivate, isNull);
          final copy = find.ancestor(
            of: find.byKey(const Key('application-support-copy')),
            matching: find.byType(StarBridgeActionButton),
          );
          expect(t.widget<StarBridgeActionButton>(copy).onActivate, isNotNull);
          expect(h.port.opens, 0);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite live reduce during pending then restore keeps request and origin',
      (t) async {
        final h = SupportFixture();
        try {
          await h.mount(t, suite);
          h.port.delayed = true;
          await fire(t, 'pointer', 'application-support-refresh');
          await frames(t);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          await t.pumpWidget(h.page(suite, reduce: true));
          await frames(t);
          expect(find.byType(SuiteProgressBar), findsNothing);
          expect(readMotion(t).source, InteractionSource.pointer);
          await t.pumpWidget(h.page(suite));
          await frames(t);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          expect(h.port.inspections, 2);
          h.port.pending.single.complete(supportSnapshot);
          await t.pumpAndSettle();
        } finally {
          await h.close(t);
        }
      },
    );
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input actual support dialog preserves pending queue and independent close',
        (t) async {
          size(t, const Size(1400, 1100));
          final sem = t.ensureSemantics();
          final port = SupportPort()..delayed = true;
          final owner = createApplicationSupportModule(port);
          final initial = owner.initialize();
          try {
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) => StarBridgeActionButton(
                    controlKey: const Key('open-support'),
                    onActivate: (_) =>
                        showApplicationSupportDialog(context, owner),
                    child: const Text('Open'),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await fire(t, input, 'open-support');
            await t.pumpAndSettle();
            expect(port.inspections, 1);
            expect(find.text('正在检查当前设备…'), findsOneWidget);
            expect(readMotion(t).staticWait, isTrue);
            port.pending.first.complete(supportSnapshot);
            await frames(t);
            expect(port.inspections, 2);
            expect(owner.projection.value.loading, isTrue);
            expect(readMotion(t).source, InteractionSource.programmatic);
            await fire(t, 'keyboard', 'application-support-close');
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('application-support-page')),
              findsNothing,
            );
            expect(port.closes, 0);
            port.pending.last.complete(supportSnapshot);
            await initial;
            await frames(t);
            expect(t.takeException(), isNull);
          } finally {
            sem.dispose();
            await t.pumpWidget(const SizedBox());
            owner.dispose();
          }
        },
      );
    }
  }
}
