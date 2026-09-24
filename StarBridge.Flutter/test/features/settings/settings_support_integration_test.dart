import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/features/settings/settings_capability_catalog.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';

import 'settings_entry_test.dart' show app;

void main() {
  testWidgets(
    'product settings retain all entries and open real disconnected details',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final composition = AppComposition.forTest(
        windowChrome: InMemoryWindowChrome(),
      );
      addTearDown(composition.dispose);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => composition.features
                .byRoute('/settings')
                .buildDestination(context),
          ),
          const Locale('zh', 'CN'),
          GlobalKey(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        composition.applicationSupport.projection.value.loading,
        isTrue,
        reason: 'opening settings must not prefetch diagnostics',
      );
      final location = find.byKey(
        const Key('settings-capability-local-data-storage'),
      );
      await tester.ensureVisible(location);
      await tester.tap(location);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('data-location-dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('settings-entry-local-data-storage')),
        findsNothing,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('data-location-move')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      final export = find.byKey(
        const Key('settings-capability-local-data-management'),
      );
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('gameplay-data-export-start')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(
                const Key('settings-action-local-data-management-clearData'),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('settings-entry-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-section-diagnostics')));
      await tester.pumpAndSettle();
      for (final entry in SettingsCapabilityCatalog.plannedFor(
        SettingsSection.diagnostics,
      )) {
        if (entry.id == 'local-event-log' ||
            entry.id == 'one-click-diagnostics' ||
            entry.id == 'runtime-status' ||
            entry.id == 'local-maintenance' ||
            entry.id == 'installation-update-repair') {
          continue;
        }
        expect(
          find.byKey(Key('settings-capability-${entry.id}')),
          findsOneWidget,
        );
      }
      final diagnosis = find.byKey(const Key('diagnostics-run'));
      await tester.ensureVisible(diagnosis);
      await tester.tap(diagnosis);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('application-support-failure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-entry-one-click-diagnostics')),
        findsNothing,
      );
      expect(find.byKey(const Key('history-category')), findsOneWidget);
      expect(find.byKey(const Key('history-close')), findsNothing);
      final cleanup = find.byKey(const Key('maintenance-clear-cache'));
      await tester.ensureVisible(cleanup);
      expect(tester.widget<OutlinedButton>(cleanup).onPressed, isNull);
      expect(find.byKey(const Key('runtime-status-close')), findsNothing);
      expect(
        find.byKey(const Key('flutter-installation-scan')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
