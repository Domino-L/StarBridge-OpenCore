import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/runtime/community_sharing_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';

import '../features/settings/community_sharing_test.dart'
    show SharingFixture, target;

void main() {
  testWidgets(
    'member confirmations wait for manual routes and serialize one organization at a time',
    (tester) async {
      final h = await Harness.create(tester);
      h.key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Manual task')),
        ),
      );
      await tester.pumpAndSettle();
      await h.controller.refresh();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('community-sharing-dialog')), findsNothing);
      expect(h.port.writes, 0);
      h.key.currentState!.pop();
      await h.settle(tester);
      expect(find.text('Organization B'), findsOneWidget);
      expect(find.text('Organization C'), findsNothing);
      await tester.tap(find.byKey(const Key('community-sharing-2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(find.text('Organization C'), findsOneWidget);
      expect(h.port.settings.communities!.first.fields, 1);
      expect(h.port.settings.communities!.last.fields, 2);
      await tester.tap(find.byKey(const Key('community-sharing-none')));
      await h.settle(tester);
      expect(h.port.settings.communities!.last.fields, 0);
      expect(h.port.writes, 2);
      expect(
        h.port.applies,
        0,
        reason:
            'Per-organization confirmation does not re-enable global consent.',
      );
      expect(find.byKey(const Key('community-sharing-dialog')), findsNothing);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'failed save can retry without losing its choice; account invalidation dismisses old prompt',
    (tester) async {
      final h = await Harness.create(tester);
      await h.controller.refresh();
      await h.settle(tester);
      h.port.failSave = true;
      await tester.tap(find.byKey(const Key('community-sharing-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(find.text('未能保存选择，请稍后再试。'), findsOneWidget);
      h.port.failSave = false;
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.writes, 1);
      expect(find.text('Organization C'), findsOneWidget);
      h.ready = false;
      h.port.events.add(null);
      await h.settle(tester);
      expect(find.byKey(const Key('community-sharing-dialog')), findsNothing);
      expect(h.port.writes, 1);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'remote membership changes prompt after polling and old consent is not inherited',
    (tester) async {
      final h = await Harness.create(tester);
      h.port.targets = CommunitySharingTargets(
        primaryFleetCode: 'A',
        communities: [target('A')],
      );
      await h.controller.refresh();
      await h.settle(tester);
      expect(find.byKey(const Key('community-sharing-dialog')), findsNothing);
      h.port.targets = CommunitySharingTargets(
        primaryFleetCode: 'A',
        communities: [target('A'), target('B')],
      );
      await tester.pump(const Duration(seconds: 16));
      await h.settle(tester);
      expect(find.text('Organization B'), findsOneWidget);
      expect(h.port.writes, 0);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('community-sharing-1')),
            )
            .value,
        isFalse,
      );
      await h.dispose(tester);
    },
  );
}

class Harness {
  Harness(this.port, this.controller, this.queue, this.key) {
    flow = CommunitySharingFlow(
      privacy: controller,
      queue: queue,
      ready: () => ready,
    );
  }
  final SharingFixture port;
  final LocalPrivacyController controller;
  final StartupPromptQueue queue;
  final GlobalKey<NavigatorState> key;
  late final CommunitySharingFlow flow;
  bool ready = true;
  static Future<Harness> create(WidgetTester tester) async {
    final port = SharingFixture()
      ..settings = LocalPrivacySettings.editorDefaults.copyWith(
        communities: [target('A').choice(fields: 1)],
      );
    port.targets = CommunitySharingTargets(
      primaryFleetCode: 'A',
      communities: [target('A'), target('B'), target('C')],
    );
    final controller = LocalPrivacyController(port);
    final queue = StartupPromptQueue();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [queue],
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(),
      ),
    );
    await tester.pumpAndSettle();
    return Harness(port, controller, queue, key);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    flow.dispose();
    queue.dispose();
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
}
