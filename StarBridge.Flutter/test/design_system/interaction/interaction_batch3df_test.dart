import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_page.dart';
import 'package:starbridge_flutter/features/settings/application_support_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

const supportSnapshot = ApplicationSupportSnapshot(
  hasIssues: false,
  hasUnavailableChecks: false,
  dataDirectory: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'writable',
  ),
  gameLog: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'readable',
  ),
  startup: ApplicationStartupCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'notEnabled',
    registered: false,
    targetExists: null,
    targetsCurrentExecutable: null,
  ),
  installation: ApplicationInstallationCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'installed',
    mode: 'installed',
    currentInstallations: 1,
    otherInstallations: 0,
    orphanedRegistrations: 0,
    scanWarnings: 0,
  ),
);

class SupportPort implements ApplicationSupportPort {
  ApplicationSupportSnapshot snapshot = supportSnapshot;
  bool delayed = false;
  int inspections = 0, opens = 0, closes = 0;
  final pending = <Completer<ApplicationSupportSnapshot>>[];
  Completer<void>? open;
  @override
  Future<ApplicationSupportSnapshot> inspect() {
    inspections++;
    if (!delayed) return Future.value(snapshot);
    final next = Completer<ApplicationSupportSnapshot>();
    pending.add(next);
    return next.future;
  }

  @override
  Future<void> openDataDirectory() async {
    opens++;
    await open?.future;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite actual inline entry and ready actions use approved feedback',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = SupportPort();
        final owner = createApplicationSupportModule(port);
        try {
          await t.pumpWidget(
            scopedApp(ApplicationSupportPanel(module: owner), suite),
          );
          await t.pumpAndSettle();
          expect(port.inspections, 0);
          expect(
            find.ancestor(
              of: find.byKey(const Key('diagnostics-run')),
              matching: find.byType(StarBridgeActionButton),
            ),
            findsOneWidget,
          );
          await t.tap(find.byKey(const Key('diagnostics-run')));
          await t.pumpAndSettle();
          expect(port.inspections, 1);
          for (final key in [
            'application-support-open-data-directory',
            'application-support-copy',
            'application-support-refresh',
          ]) {
            expect(
              find.ancestor(
                of: find.byKey(Key(key)),
                matching: find.byType(StarBridgeActionButton),
              ),
              findsOneWidget,
            );
          }
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
    testWidgets(
      '$suite unknown first read stays visible static and failure has approved retry',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = SupportPort()..delayed = true;
        final owner = createApplicationSupportModule(port);
        try {
          await t.pumpWidget(
            scopedApp(ApplicationSupportPage(module: owner), suite),
          );
          await t.pump();
          await t.pump();
          expect(port.inspections, 1);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('正在检查当前设备…'), findsOneWidget);
          port.pending.single.completeError(
            const ApplicationSupportException(
              ApplicationSupportFailure.timeout,
            ),
          );
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('application-support-failure')),
            findsOneWidget,
          );
          expect(
            find.ancestor(
              of: find.byKey(const Key('application-support-retry')),
              matching: find.byType(StarBridgeActionButton),
            ),
            findsOneWidget,
          );
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
  }
}
