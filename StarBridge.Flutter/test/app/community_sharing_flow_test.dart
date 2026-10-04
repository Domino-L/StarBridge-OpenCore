import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/runtime/community_sharing_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import '../features/settings/event_sharing_controller_test.dart'
    as event_fixture;

import '../features/settings/community_sharing_test.dart'
    show SharingFixture, target, membershipTime;
import '../features/settings/community_join_hangar_choice_test.dart'
    show JoinHangarFixture;

void main() {
  testWidgets(
    'a saved activity-event refusal is loaded before the join prompt and never reset to all',
    (tester) async {
      final events = event_fixture.Harness()..joinedAt = membershipTime;
      events.snapshot = {
        'schemaVersion': 1,
        'revision': 1,
        'operationId': '0123456789abcdef0123456789abcdef',
        'appliedAt': '2026-09-30T00:00:00Z',
        'publicationEnabled': false,
        'settings': {
          'room': {'enabled': false, 'selectedTypes': 47},
          'communities': [
            {
              'code': 'B',
              'joinedAt': membershipTime,
              'choice': {'enabled': false, 'selectedTypes': 8},
            },
          ],
        },
      };
      final h = await Harness.create(tester, eventSession: events.session);
      await h.controller.refresh();
      await h.settle(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('community-sharing-events')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('community-sharing-event-location')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('community-sharing-event-presence')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(
        events.writes,
        isEmpty,
        reason: 'Same confirmed choice needs no event write.',
      );
      await h.dispose(tester);
      await tester.runAsync(events.close);
    },
  );
  testWidgets(
    'one join prompt defaults all activity events and persists them independently',
    (tester) async {
      final events = event_fixture.Harness()..joinedAt = membershipTime;
      final h = await Harness.create(tester, eventSession: events.session);
      await h.controller.refresh();
      await h.settle(tester);
      for (final kind in ['presence', 'server', 'ship', 'location', 'life']) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(Key('community-sharing-event-$kind')),
              )
              .value,
          isTrue,
        );
      }
      expect(
        events.writes,
        isEmpty,
        reason: 'Opening a draft does not publish events.',
      );
      await tester.ensureVisible(
        find.byKey(const Key('community-sharing-event-location')),
      );
      await tester.tap(
        find.byKey(const Key('community-sharing-event-location')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(events.writes.length, 1);
      final settings = events.snapshot['settings'] as Map;
      final b = (settings['communities'] as List).singleWhere(
        (raw) => (raw as Map)['code'] == 'B',
      ) as Map;
      expect(b['choice'], {'enabled': true, 'selectedTypes': 39});
      expect(settings['room'], {'enabled': false, 'selectedTypes': 47});
      expect(h.port.settings.communities!.last.fields, 15);
      await h.dispose(tester);
      await tester.runAsync(events.close);
    },
  );
  testWidgets(
    'failed events keep the join draft pending; retry preserves opt-outs and no sharing opts out of events',
    (tester) async {
      final events = event_fixture.Harness()..joinedAt = membershipTime;
      final h = await Harness.create(tester, eventSession: events.session);
      await h.controller.refresh();
      await h.settle(tester);
      events.failSave = true;
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.writes, 0);
      expect(find.text('活动事件设置未能确认，选择已保留。请重试。'), findsOneWidget);
      events.failSave = false;
      await tester.tap(find.byKey(const Key('community-sharing-none')));
      await h.settle(tester);
      expect(h.port.settings.communities!.last.fields, 0);
      final b =
          ((events.snapshot['settings'] as Map)['communities'] as List)
                  .singleWhere((raw) => (raw as Map)['code'] == 'B')
              as Map;
      expect((b['choice'] as Map)['enabled'], isFalse);
      await h.dispose(tester);
      await tester.runAsync(events.close);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'combined join choices keep actions accessible in a small window $locale',
      (tester) async {
        tester.view.physicalSize = const Size(400, 520);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final p = JoinHangarFixture();
        addTearDown(p.events.close);
        final h = await Harness.create(tester, hangar: p, locale: locale);
        await h.controller.refresh();
        await h.settle(tester);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('community-sharing-events')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const Key('community-sharing-hangar')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('community-sharing-none')));
        await h.settle(tester);
        expect(h.port.writes, 1);
        expect(h.port.settings.communities!.last.fields, 0);
        expect(p.selected, {'A'});
        await h.dispose(tester);
      },
    );
  }
  testWidgets(
    'status failure keeps the membership pending and does not republish confirmed hangar on retry',
    (tester) async {
      final p = JoinHangarFixture();
      addTearDown(p.events.close);
      final h = await Harness.create(tester, hangar: p);
      h.port.failSave = true;
      await h.controller.refresh();
      await h.settle(tester);
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(find.text('机库选择已保存，状态设置未能确认。请重试。'), findsOneWidget);
      expect(h.port.settings.communities!.any((t) => t.code == 'B'), isFalse);
      expect(p.selected, {'A', 'B'});
      expect(p.writes, 1);
      h.port.failSave = false;
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(p.writes, 1);
      expect(h.port.writes, 1);
      expect(find.text('Organization C'), findsOneWidget);
      await h.dispose(tester);
    },
  );
  testWidgets(
    'hangar is preselected in the same prompt and only confirmed choices are saved',
    (tester) async {
      final p = JoinHangarFixture();
      addTearDown(p.events.close);
      final h = await Harness.create(tester, hangar: p);
      await h.controller.refresh();
      await h.settle(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('community-sharing-hangar')),
            )
            .value,
        isTrue,
      );
      expect(p.reads, 0);
      expect(p.writes, 0);
      expect(
        find.text('默认共享以下信息，可取消不想共享的项目。状态共享可稍后在“共享与隐私”中修改。'),
        findsOneWidget,
      );
      expect(find.text('组织成员可查看你的舰船清单，可在组织“舰船”页修改。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.settings.communities!.last.fields, 15);
      expect(p.selected, {'A', 'B'});
      expect(p.writes, 1);
      expect(find.text('Organization C'), findsOneWidget);
      await h.dispose(tester);
    },
  );
  testWidgets('opting out of hangar leaves default status sharing intact', (
    tester,
  ) async {
    final p = JoinHangarFixture();
    addTearDown(p.events.close);
    final h = await Harness.create(tester, hangar: p);
    await h.controller.refresh();
    await h.settle(tester);
    await tester.tap(find.byKey(const Key('community-sharing-hangar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('community-sharing-confirm')));
    await h.settle(tester);
    expect(h.port.settings.communities!.last.fields, 15);
    expect(p.selected, {'A'});
    expect(p.writes, 0);
    await h.dispose(tester);
  });
  testWidgets(
    'do not share rejects both categories without changing other audiences',
    (tester) async {
      final p = JoinHangarFixture()..selected.add('B');
      addTearDown(p.events.close);
      final h = await Harness.create(tester, hangar: p);
      await h.controller.refresh();
      await h.settle(tester);
      await tester.tap(find.byKey(const Key('community-sharing-none')));
      await h.settle(tester);
      expect(h.port.settings.communities!.last.fields, 0);
      expect(p.selected, {'A'});
      await h.dispose(tester);
    },
  );
  testWidgets(
    'hangar uncertainty remains visible and retry does not resave status or replay accepted hangar',
    (tester) async {
      final p = JoinHangarFixture()
        ..outcome = const CommunityHangarSharingOutcome('unknown');
      addTearDown(p.events.close);
      final h = await Harness.create(tester, hangar: p);
      await h.controller.refresh();
      await h.settle(tester);
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(find.text('机库设置未能确认，选择已保留。请重试。'), findsOneWidget);
      expect(find.text('Organization B'), findsOneWidget);
      expect(h.port.writes, 0);
      expect(
        h.controller.unconfirmedCommunities.map((t) => t.code),
        contains('B'),
      );
      expect(p.writes, 1);
      p.selected.add('B');
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.writes, 1);
      expect(p.writes, 1);
      expect(p.reads, 2);
      expect(find.text('Organization C'), findsOneWidget);
      await h.dispose(tester);
    },
  );
  testWidgets(
    'master status sharing off does not silently override the independent hangar choice',
    (tester) async {
      final p = JoinHangarFixture();
      addTearDown(p.events.close);
      final h = await Harness.create(tester, enabled: false, hangar: p);
      h.port.publicationState = 'withdrawn';
      await h.controller.refresh();
      await h.settle(tester);
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.settings.publicationEnabled, isFalse);
      expect(h.port.settings.communities!.last.fields, 15);
      expect(h.port.applies, 0);
      expect(p.selected, {'A', 'B'});
      await h.dispose(tester);
    },
  );
  testWidgets(
    'all four fields are preselected but nothing is saved until confirmation',
    (tester) async {
      final h = await Harness.create(tester);
      await h.controller.refresh();
      await h.settle(tester);
      for (final bit in [1, 2, 4, 8]) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(Key('community-sharing-$bit')),
              )
              .value,
          isTrue,
        );
      }
      expect(h.port.writes, 0);
      expect(h.port.settings.communities!.any((s) => s.code == 'B'), isFalse);
      expect(find.text('确认共享'), findsOneWidget);
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.settings.communities!.last.fields, 15);
      expect(h.port.writes, 1);
      expect(h.port.applies, 0);
      expect(find.text('Organization C'), findsOneWidget);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'legacy scopes still prompt and no organization is granted by discovery',
    (tester) async {
      final h = await Harness.create(tester, legacy: true);
      await h.controller.refresh();
      await h.settle(tester);
      expect(find.byKey(const Key('community-sharing-dialog')), findsOneWidget);
      expect(find.text('Organization A'), findsOneWidget);
      expect(h.port.writes, 0);
      expect(h.port.settings.communities, isNull);
      await tester.tap(find.byKey(const Key('community-sharing-none')));
      await h.settle(tester);
      expect(h.port.settings.communities!.single.fields, 0);
      expect(find.text('Organization B'), findsOneWidget);
      expect(
        h.port.settings.communities!.any((row) => row.code == 'B'),
        isFalse,
      );
      expect(h.port.applies, 0);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'membership choices remain discoverable while master sharing is off',
    (tester) async {
      final h = await Harness.create(tester, enabled: false);
      h.port.publicationState = 'withdrawn';
      await h.controller.refresh();
      await h.settle(tester);
      expect(find.text('Organization B'), findsOneWidget);
      expect(find.text('保存选择'), findsOneWidget);
      for (final bit in [2, 4, 8]) {
        await tester.tap(find.byKey(Key('community-sharing-$bit')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.settings.communities!.last.fields, 1);
      expect(h.port.settings.publicationEnabled, isFalse);
      expect(h.port.applies, 0);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'explicit legacy choice preserves other associated scopes without granting unseen audiences',
    (tester) async {
      final h = await Harness.create(tester, legacy: true);
      h.port.settings = h.port.settings.copyWith(fleetFields: 1);
      h.port.targets = CommunitySharingTargets(
        primaryFleetCode: 'A',
        communities: [target('B'), target('A'), target('C')],
      );
      await h.controller.refresh();
      await h.settle(tester);
      expect(find.text('Organization B'), findsOneWidget);
      expect(find.text('其他组织的状态共享设置不会改变。'), findsOneWidget);
      expect(h.port.writes, 0);
      await tester.tap(find.byKey(const Key('community-sharing-none')));
      await h.settle(tester);
      expect(
        h.port.settings.communities!.where((s) => s.code == 'A').single.fields,
        1,
      );
      expect(
        h.port.settings.communities!.where((s) => s.code == 'B').single.fields,
        0,
      );
      expect(h.port.settings.communities!.any((s) => s.code == 'C'), isFalse);
      expect(find.text('Organization C'), findsOneWidget);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'confirmed membership event discovers new scope without waiting for periodic polling',
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
      h.memberships.value++;
      await tester.pump(const Duration(milliseconds: 100));
      await h.settle(tester);
      expect(find.text('Organization B'), findsOneWidget);
      expect(h.port.writes, 0);
      await h.dispose(tester);
    },
  );

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
      for (final bit in [1, 4, 8]) {
        await tester.tap(find.byKey(Key('community-sharing-$bit')));
        await tester.pump();
      }
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
      await tester.tap(find.byKey(const Key('community-sharing-8')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(find.text('未能保存，选择已保留。请重试。'), findsOneWidget);
      for (final bit in [1, 2, 4, 8]) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(Key('community-sharing-$bit')),
              )
              .value,
          bit != 8,
        );
      }
      h.port.failSave = false;
      await tester.tap(find.byKey(const Key('community-sharing-confirm')));
      await h.settle(tester);
      expect(h.port.writes, 1);
      expect(h.port.settings.communities!.last.fields, 7);
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
        isTrue,
      );
      await h.dispose(tester);
    },
  );
}

class Harness {
  Harness(
    this.port,
    this.controller,
    this.queue,
    this.key, [
    CommunityHangarSharingPort? hangar,
    BridgeClientSession? eventSession,
  ]) {
    flow = CommunitySharingFlow(
      privacy: controller,
      queue: queue,
      ready: () => ready,
      membershipChanges: memberships,
      hangarSharing: hangar,
      eventSession: eventSession,
    );
  }
  final SharingFixture port;
  final LocalPrivacyController controller;
  final StartupPromptQueue queue;
  final GlobalKey<NavigatorState> key;
  late final CommunitySharingFlow flow;
  final memberships = ValueNotifier<int>(0);
  bool ready = true;
  static Future<Harness> create(
    WidgetTester tester, {
    bool legacy = false,
    bool enabled = true,
    CommunityHangarSharingPort? hangar,
    BridgeClientSession? eventSession,
    Locale locale = const Locale('zh', 'CN'),
  }) async {
    final port = SharingFixture()
      ..settings = LocalPrivacySettings.editorDefaults.copyWith(
        publicationEnabled: enabled,
        communities: legacy ? null : [target('A').choice(fields: 1)],
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
        locale: locale,
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
    return Harness(port, controller, queue, key, hangar, eventSession);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    flow.dispose();
    memberships.dispose();
    queue.dispose();
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
}
