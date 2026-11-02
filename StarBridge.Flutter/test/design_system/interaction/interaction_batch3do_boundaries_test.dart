import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/diagnostics_maintenance_panel.dart';
import 'package:starbridge_flutter/features/settings/flutter_installation_panel.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';

import 'interaction_batch3do_test.dart'
    show
        BridgeFixture,
        SupportFixture,
        scopedApp,
        size,
        loadFonts,
        invoke,
        waiting,
        template;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite disconnected capability gates retain no side effects', (
      t,
    ) async {
      size(t, const Size(900, 700));
      final fixture = BridgeFixture(capabilities: []),
          support = SupportFixture();
      addTearDown(fixture.close);
      addTearDown(support.dispose);
      await t.pumpWidget(
        scopedApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DiagnosticsMaintenancePanel(
                support: support,
                session: fixture.session,
              ),
              FlutterInstallationPanel(session: fixture.session),
            ],
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      for (final key in [
        'maintenance-open-folder',
        'maintenance-clear-cache',
        'flutter-installation-scan',
      ]) {
        expect(template(t, key).onPressed, isNull);
      }
      expect(fixture.requests, isEmpty);
      expect(support.opens, 0);
      expect(support.reads, 0);
      expect(find.byType(HelpSupportWaiting), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    for (final operation in ['uninstall', 'clean']) {
      testWidgets(
        '$suite $operation success is only shown after authoritative completed acknowledgement',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = BridgeFixture();
          addTearDown(fixture.close);
          try {
            size(t, const Size(900, 700));
            await t.pumpWidget(
              scopedApp(
                FlutterInstallationPanel(session: fixture.session),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await scanReadyLocal(t, fixture, operation);
            final label = operation == 'clean' ? '清理安装残留' : '卸载客户端';
            await invoke(
              t,
              'flutter-installation-$operation',
              label,
              'pointer',
            );
            await t.pumpAndSettle();
            await t.tapAt(const Offset(4, 4));
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              fixture.requests,
              hasLength(1),
              reason: 'barrier cancellation sends no execute request',
            );
            await invoke(
              t,
              'flutter-installation-$operation',
              label,
              'keyboard',
            );
            await t.pumpAndSettle();
            await invoke(t, 'installation-confirm-execute', label, 'pointer');
            await t.pump(const Duration(milliseconds: 350));
            waiting(t, 'pointer');
            final result = operation == 'clean'
                ? '失效安装记录已清理。'
                : '卸载向导已启动，请在向导中继续。';
            expect(find.text(result), findsNothing);
            expect(fixture.requests.last.payload, {
              'schemaVersion': 1,
              'ticket': 'synthetic-ticket',
              'action': operation,
            });
            await fixture.reply(1, {'schemaVersion': 1, 'completed': true});
            await t.pumpAndSettle();
            expect(find.text(result), findsOneWidget);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(fixture.requests, hasLength(2));
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite confirmation replacement preserves distinct installation and maintenance session rules',
      (t) async {
        size(t, const Size(900, 700));
        final a = BridgeFixture(),
            b = BridgeFixture(),
            support = SupportFixture();
        addTearDown(a.close);
        addTearDown(b.close);
        addTearDown(support.dispose);
        final installKey = GlobalKey();
        Widget installation(BridgeFixture fixture) => scopedApp(
          FlutterInstallationPanel(key: installKey, session: fixture.session),
          suite,
        );
        await t.pumpWidget(installation(a));
        await t.pumpAndSettle();
        await scanReadyLocal(t, a, 'uninstall');
        await invoke(t, 'flutter-installation-uninstall', '卸载客户端', 'pointer');
        await t.pumpAndSettle();
        await t.pumpWidget(installation(b));
        await t.pump();
        await invoke(t, 'installation-confirm-execute', '卸载客户端', 'keyboard');
        await t.pumpAndSettle();
        expect(a.requests, hasLength(1));
        expect(b.requests, isEmpty);
        expect(find.byType(HelpSupportWaiting), findsNothing);
        final maintainKey = GlobalKey();
        Widget maintenance(BridgeFixture fixture) => scopedApp(
          DiagnosticsMaintenancePanel(
            key: maintainKey,
            support: support,
            session: fixture.session,
          ),
          suite,
        );
        await t.pumpWidget(maintenance(a));
        await t.pumpAndSettle();
        await invoke(t, 'maintenance-clear-cache', '清理图片缓存', 'pointer');
        await t.pumpAndSettle();
        await t.pumpWidget(maintenance(b));
        await t.pump();
        await invoke(t, 'maintenance-confirm-execute', '清理图片缓存', 'keyboard');
        await t.pump();
        waiting(t, 'keyboard');
        expect(a.requests, hasLength(1));
        expect(
          b.requests.single.name,
          'diagnostics.clearImageCache',
          reason: 'original maintenance reads the current widget.session after confirmation',
        );
        await b.reply(0, {'schemaVersion': 1, 'count': 0});
        await t.pumpAndSettle();
        expect(find.textContaining('已清理可重新下载'), findsOneWidget);
        expect(support.opens, 0);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite late scan, execution and folder acknowledgements after unmount never revive UI',
      (t) async {
        size(t, const Size(900, 700));
        final fixture = BridgeFixture(), support = SupportFixture();
        addTearDown(fixture.close);
        addTearDown(support.dispose);
        await t.pumpWidget(
          scopedApp(FlutterInstallationPanel(session: fixture.session), suite),
        );
        await t.pumpAndSettle();
        await invoke(t, 'flutter-installation-scan', '检查安装状态', 'pointer');
        await t.pump();
        expect(fixture.requests, hasLength(1));
        await t.pumpWidget(const SizedBox());
        await fixture.reply(0, fixture.plan());
        await t.pump();
        expect(t.takeException(), isNull);
        await t.pumpWidget(
          scopedApp(FlutterInstallationPanel(session: fixture.session), suite),
        );
        await t.pumpAndSettle();
        await invoke(t, 'flutter-installation-scan', '检查安装状态', 'pointer');
        await t.pump();
        await fixture.reply(1, fixture.plan());
        await t.pumpAndSettle();
        await invoke(t, 'flutter-installation-uninstall', '卸载客户端', 'pointer');
        await t.pumpAndSettle();
        await invoke(t, 'installation-confirm-execute', '卸载客户端', 'keyboard');
        await t.pump();
        expect(fixture.requests, hasLength(3));
        await t.pumpWidget(const SizedBox());
        await fixture.reply(2, {'schemaVersion': 1, 'completed': true});
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.byType(HelpSupportWaiting), findsNothing);
        await t.pumpWidget(
          scopedApp(
            DiagnosticsMaintenancePanel(
              support: support,
              session: fixture.session,
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await invoke(t, 'maintenance-open-folder', '打开数据目录', 'pointer');
        await t.pump();
        expect(support.opens, 1);
        await t.pumpWidget(const SizedBox());
        support.opening.complete(ApplicationSupportActionResult.completed);
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.byType(HelpSupportWaiting), findsNothing);
        expect(fixture.requests, hasLength(3));
      },
    );
    testWidgets(
      '$suite six accepted installation modes and original field type checks stay intact',
      (t) async {
        size(t, const Size(900, 700));
        final fixture = BridgeFixture();
        addTearDown(fixture.close);
        await t.pumpWidget(
          scopedApp(FlutterInstallationPanel(session: fixture.session), suite),
        );
        await t.pumpAndSettle();
        for (final mode in [
          'portable',
          'installed',
          'other',
          'orphaned',
          'damaged',
          'unverified',
        ]) {
          final index = fixture.requests.length;
          await invoke(t, 'flutter-installation-scan', '检查安装状态', 'keyboard');
          await t.pump();
          await fixture.reply(
            index,
            fixture.plan(mode: mode, clean: mode == 'orphaned'),
          );
          await t.pumpAndSettle();
          expect(find.textContaining('操作未确认完成'), findsNothing, reason: mode);
          expect(
            find.byKey(const Key('flutter-installation-uninstall')),
            mode == 'installed' ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('flutter-installation-clean')),
            mode == 'orphaned' ? findsOneWidget : findsNothing,
          );
        }
        for (final patch in <Map<String, dynamic>>[
          {'ticket': 1},
          {'directory': null},
          {'canUninstall': 'true'},
          {'canClean': 1},
          {'mode': 'unknown'},
        ]) {
          final index = fixture.requests.length;
          await invoke(t, 'flutter-installation-scan', '检查安装状态', 'keyboard');
          await t.pump();
          await fixture.reply(index, {...fixture.plan(), ...patch});
          await t.pumpAndSettle();
          expect(find.textContaining('操作未确认完成'), findsOneWidget);
          expect(
            find.byKey(const Key('flutter-installation-uninstall')),
            findsNothing,
          );
        }
        expect(
          fixture.requests.every(
            (r) => r.name == 'diagnostics.flutterInstallation',
          ),
          isTrue,
        );
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
}

Future<void> scanReadyLocal(
  WidgetTester t,
  BridgeFixture fixture,
  String operation,
) async {
  await invoke(t, 'flutter-installation-scan', '检查安装状态', 'keyboard');
  await t.pump();
  await fixture.reply(
    0,
    fixture.plan(
      mode: operation == 'clean' ? 'orphaned' : 'installed',
      clean: operation == 'clean',
    ),
  );
  await t.pumpAndSettle();
}
