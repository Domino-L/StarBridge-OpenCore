import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/common/organization_settings_layout.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_organization_controls.dart';
import 'package:starbridge_flutter/features/settings/notification_organization_options.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_sources_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/organization_notification_pane.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show app, loadFonts, size;

final _community = 'organization:${'a' * 64}';
final _official = 'officialFleet:${'b' * 64}';
NotificationSourceRule _rule(String key, {bool official = false}) =>
    NotificationSourceRule(
      sourceRef: key,
      kind: official
          ? NotificationSourceKind.officialFleet
          : NotificationSourceKind.community,
      displayName: 'Synthetic',
      contextLabel: '',
      mode: NotificationSourceMode.normal,
      organizationCode: official ? null : 'SYNTHETIC',
    );

class _Port implements OrganizationNotificationSourcesPort {
  NotificationSourcesValue value = NotificationSourcesValue(0, [
    _rule(_community),
    _rule(_official, official: true),
  ], supportsOrganizationOptions: true);
  final events = StreamController<void>.broadcast();
  final writes = <Map<String, NotificationOrganizationOptions>>[];
  Object? readFailure, saveFailure;
  int reads = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<NotificationSourcesValue> read() async {
    reads++;
    if (readFailure case final error?) throw error;
    return value;
  }

  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) => saveOrganizationOptions(original, modes, const {});
  @override
  Future<NotificationSourcesValue> saveOrganizationOptions(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
    Map<String, NotificationOrganizationOptions> options,
  ) async {
    writes.add(Map.of(options));
    if (saveFailure case final error?) throw error;
    return value = NotificationSourcesValue(original.revision + 1, [
      for (final source in original.sources)
        source.copyWith(
          mode: modes[source.sourceRef],
          organizationOptions: options[source.sourceRef],
        ),
    ], supportsOrganizationOptions: true);
  }

  @override
  void dispose() {}
}

Map<String, Object?> _wire(
  int version, {
  NotificationChatMode chat = NotificationChatMode.inherit,
  NotificationChatMode announcement = NotificationChatMode.disabled,
}) => {
  'schemaVersion': version,
  'revision': 0,
  'roomMode': 'normal',
  'friendMode': 'normal',
  'directMessageMode': 'normal',
  'sources': [
    {
      'sourceRef': _community,
      'kind': 'community',
      'displayName': 'Synthetic',
      'organizationCode': 'SYNTHETIC',
      'mode': 'normal',
      if (version == 3)
        ...NotificationOrganizationOptions(
          chat: chat,
          announcement: announcement,
          quietEnabled: true,
        ).toWire(),
    },
  ],
};

void main() {
  setUpAll(loadFonts);
  test('announcement guidance explains startup summary and quiet suppression in three locales', () {
    const key = 'settings.notification.organization.announcementHint';
    final cn = AppStrings.resolve(const Locale('zh', 'CN')).text(key);
    final tw = AppStrings.resolve(const Locale('zh', 'TW')).text(key);
    final en = AppStrings.resolve(const Locale('en', 'US')).text(key);
    expect(cn, startsWith('默认跟随上方提醒模式。'));
    expect(tw, startsWith('預設跟隨上方提醒模式。'));
    expect(en, startsWith('Follows the alert mode above by default.'));
    expect(cn, contains('按组织汇总为一条提醒'));
    expect(cn, contains('首次使用不汇总'));
    expect(cn, contains('跳过的提醒不补发'));
    expect(tw, contains('依組織彙總為一則提醒'));
    expect(tw, contains('首次使用不彙總'));
    expect(tw, contains('略過的提醒不補發'));
    expect(en, contains('one alert per organization'));
    expect(en, contains('except on first use'));
    expect(en, contains('not replayed'));
    expect(cn, contains('仍受来源模式和设备渠道限制'));
    expect(tw, contains('仍受來源模式和裝置管道限制'));
    expect(en, contains('Source mode and device channels still apply'));
    for (final hint in [cn, tw, en]) {
      expect(hint, isNot(contains('默认不提醒')));
      expect(hint, isNot(contains('預設不提醒')));
      expect(hint, isNot(contains('Off by default')));
    }
  });
  testWidgets(
    'announcement selector updates its draft through the real control',
    (tester) async {
      size(tester, const Size(1100, 1500));
      var draft = const NotificationOrganizationOptions();
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: NotificationOrganizationControls(
                sourceRef: _community,
                official: false,
                value: draft,
                enabled: true,
                onChanged: (next) => setState(() => draft = next),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(
        ValueKey('organization-announcement-$_community'),
      );
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('提醒').last);
      await tester.pumpAndSettle();
      expect(draft.announcement, NotificationChatMode.enabled);
      expect(
        NotificationOrganizationOptions.parse(draft.toWire()).announcement,
        NotificationChatMode.enabled,
      );
      expect(find.textContaining('当前没有独立活动提醒'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('announcement missing follows source mode and all explicit choices round trip', () {
    final defaults = const NotificationOrganizationOptions();
    expect(defaults.announcement, NotificationChatMode.inherit);
    expect(defaults.chat, NotificationChatMode.disabled);
    expect(defaults.activity, NotificationChatMode.disabled);
    final missing = NotificationOrganizationOptions.parse({
      ...defaults.toWire(),
      'typeRules': <Object>[],
    });
    expect(missing.announcement, NotificationChatMode.inherit);
    expect(
      (missing.toWire()['typeRules'] as List)
          .where((t) => t['type'] == 'announcement')
          .single['mode'],
      'inherit',
    );
    for (final mode in NotificationChatMode.values) {
      final draft = defaults.copyWith(announcement: mode);
      expect(NotificationOrganizationOptions.parse(draft.toWire()), draft);
      expect(draft == defaults, mode == NotificationChatMode.inherit);
      expect(
        BridgeNotificationSources.parse(
          _wire(3, announcement: mode),
          schemaVersion: 3,
        ).sources.last.organizationOptions.announcement,
        mode,
      );
    }
  });
  testWidgets('global read failure offers reload without editable sources', (
    tester,
  ) async {
    size(tester, const Size(1100, 1500));
    final port = _Port()..readFailure = StateError('synthetic read failure');
    addTearDown(port.events.close);
    await tester.pumpWidget(
      app(
        NotificationEditorFrame(
          owner: port,
          child: SingleChildScrollView(
            child: NotificationSourcesConnectedPanel(port: port),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notification-sources-reload')),
      findsOneWidget,
    );
    expect(find.byType(NotificationOrganizationControls), findsNothing);
    port.readFailure = null;
    await tester.tap(find.byKey(const Key('notification-sources-reload')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationOrganizationControls), findsNWidgets(2));
    expect(port.reads, 2);
    expect(tester.takeException(), isNull);
  });
  for (final official in [false, true]) {
    for (final modeSave in [false, true]) {
      testWidgets(
        'save failure retains editable organization draft official=$official mode=$modeSave',
        (tester) async {
          size(tester, const Size(1100, 1500));
          final port = _Port();
          addTearDown(port.events.close);
          await tester.pumpWidget(
            app(
              SingleChildScrollView(
                child: OrganizationNotificationPane(
                  create: () => port,
                  communityCode: official ? null : 'SYNTHETIC',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final source = official ? _official : _community;
          const draft = NotificationOrganizationOptions(
            chat: NotificationChatMode.enabled,
            announcement: NotificationChatMode.disabled,
            quietEnabled: true,
            startMinute: 123,
            endMinute: 456,
          );
          tester
              .widget<NotificationOrganizationControls>(
                find.byType(NotificationOrganizationControls),
              )
              .onChanged(draft);
          await tester.pumpAndSettle();
          Future<void> save() async {
            if (modeSave) {
              await tester
                  .widget<NotificationSourceRuleRow>(
                    find.byType(NotificationSourceRuleRow),
                  )
                  .onChanged(NotificationSourceMode.importantOnly);
            } else {
              final button = find.byKey(
                const Key('organization-notification-save-options'),
              );
              await tester.ensureVisible(button);
              await tester.tap(button);
            }
            await tester.pumpAndSettle();
          }

          for (final error in [
            const BridgeRemoteException('notificationPolicies.save_failed'),
          ]) {
            port.saveFailure = error;
            await save();
            expect(
              find.byKey(const Key('organization-notification-pane')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('organization-notification-retry')),
              findsNothing,
            );
            expect(
              find.text(
                AppStrings.resolve(const Locale('zh', 'CN'))
                    .text('settings.notification.error.writeFailed'),
              ),
              findsOneWidget,
            );
            final controls = tester.widget<NotificationOrganizationControls>(
              find.byType(NotificationOrganizationControls),
            );
            expect(controls.enabled, isTrue);
            expect(controls.value, draft);
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(ValueKey('organization-quiet-start-$source')),
                  )
                  .controller!
                  .text,
              '02:03',
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(ValueKey('organization-quiet-end-$source')),
                  )
                  .controller!
                  .text,
              '07:36',
            );
          }
          port.saveFailure = null;
          await save();
          expect(
            find.text(
              AppStrings.resolve(const Locale('zh', 'CN'))
                  .text('settings.notification.error.writeFailed'),
            ),
            findsNothing,
          );
          expect(port.reads, 1);
          expect(
            tester
                .widget<NotificationOrganizationControls>(
                  find.byType(NotificationOrganizationControls),
                )
                .value,
            draft,
          );
          if (modeSave) {
            expect(
              port.value.modes[source],
              NotificationSourceMode.importantOnly,
            );
          } else {
            expect(port.writes.last[source], draft);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('read failure offers retry official=$official', (tester) async {
      size(tester, const Size(1100, 1500));
      final port = _Port()..readFailure = StateError('synthetic read failure');
      addTearDown(port.events.close);
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: OrganizationNotificationPane(
              create: () => port,
              communityCode: official ? null : 'SYNTHETIC',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('organization-notification-retry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('organization-notification-pane')),
        findsNothing,
      );
      port.readFailure = null;
      await tester.tap(
        find.byKey(const Key('organization-notification-retry')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('organization-notification-pane')),
        findsOneWidget,
      );
      expect(port.reads, 2);
    });
  }
  testWidgets(
    'global save_failed retains editable draft until successful retry',
    (tester) async {
      size(tester, const Size(1100, 1500));
      final port = _Port()
        ..saveFailure = const BridgeRemoteException(
          'notificationPolicies.save_failed',
        );
      addTearDown(port.events.close);
      await tester.pumpWidget(
        app(
          NotificationEditorFrame(
            owner: port,
            child: SingleChildScrollView(
              child: NotificationSourcesConnectedPanel(port: port),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var controls = tester.widget<NotificationOrganizationControls>(
        find.byType(NotificationOrganizationControls).first,
      );
      final draft = controls.value.copyWith(
        chat: NotificationChatMode.disabled,
        quietEnabled: true,
        startMinute: 123,
      );
      controls.onChanged(draft);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-save')));
      await tester.pumpAndSettle();
      controls = tester.widget<NotificationOrganizationControls>(
        find.byType(NotificationOrganizationControls).first,
      );
      expect(controls.enabled, isTrue);
      expect(controls.value, draft);
      expect(
        find.text(
          AppStrings.resolve(const Locale('zh', 'CN'))
              .text('settings.notification.error.writeFailed'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notification-sources-reload')),
        findsNothing,
      );
      controls.onChanged(draft.copyWith(endMinute: 456));
      await tester.pumpAndSettle();
      port.saveFailure = null;
      await tester.tap(find.byKey(const Key('notification-save')));
      await tester.pumpAndSettle();
      expect(port.writes, hasLength(2));
      expect(port.writes.last[_community], draft.copyWith(endMinute: 456));
      expect(port.reads, 1);
      expect(
        find.text(
          AppStrings.resolve(const Locale('zh', 'CN'))
              .text('settings.notification.error.writeFailed'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final failure in [
    StateError('unconfirmed'),
    const BridgeRemoteException('notificationPolicies.unconfirmed'),
  ]) {
    testWidgets('global uncertain write freezes options: $failure', (
      tester,
    ) async {
      size(tester, const Size(1100, 1500));
      final port = _Port()..saveFailure = failure;
      addTearDown(port.events.close);
      await tester.pumpWidget(
        app(
          NotificationEditorFrame(
            owner: port,
            child: SingleChildScrollView(
              child: NotificationSourcesConnectedPanel(port: port),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      NotificationOrganizationControls controls() =>
          tester.widget<NotificationOrganizationControls>(
            find.byType(NotificationOrganizationControls).first,
          );
      final staleChange = controls().onChanged;
      final draft = controls().value.copyWith(
        chat: NotificationChatMode.disabled,
        quietEnabled: true,
        startMinute: 123,
      );
      staleChange(draft);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-save')));
      await tester.pumpAndSettle();
      expect(controls().enabled, isFalse);
      expect(controls().value, draft);
      expect(port.writes, hasLength(1));
      staleChange(draft.copyWith(endMinute: 456));
      await tester.pumpAndSettle();
      expect(controls().value, draft);
      expect(port.writes, hasLength(1));
      expect(port.reads, 1);
      expect(
        find.byKey(const Key('notification-sources-reload')),
        findsNothing,
      );
      port.saveFailure = null;
      await tester.tap(find.byKey(const Key('notification-save')));
      await tester.pumpAndSettle();
      expect(port.writes, hasLength(2));
      expect(port.writes.last, port.writes.first);
      expect(controls().enabled, isTrue);
      expect(controls().value, draft);
      expect(port.reads, 1);
      expect(tester.takeException(), isNull);
    });
  }
  for (final mode in NotificationChatMode.values) {
    test('v3 reads and writes chat option ${mode.name}', () {
      final options = BridgeNotificationSources.parse(
        _wire(3, chat: mode),
        schemaVersion: 3,
      ).sources.last.organizationOptions;
      expect(options.chat, mode);
      expect(options.quietEnabled, isTrue);
      expect(NotificationOrganizationOptions.parse(options.toWire()), options);
      expect(options.copyWith(chat: mode), options);
    });
  }
  for (final version in [1, 2]) {
    test(
      'old bridge v$version retains inherit and disabled schedule defaults',
      () {
        final value = BridgeNotificationSources.parse(
          _wire(version),
          schemaVersion: version,
        );
        expect(value.supportsOrganizationOptions, isFalse);
        expect(
          value.sources.last.organizationOptions,
          const NotificationOrganizationOptions(),
        );
      },
    );
  }
  test('invalid time and duplicate or unknown types fail closed', () {
    for (final options in [
      const NotificationOrganizationOptions(startMinute: 480, endMinute: 480),
      const NotificationOrganizationOptions(startMinute: -1),
      const NotificationOrganizationOptions(endMinute: 1440),
    ]) {
      expect(options.valid, isFalse);
      expect(
        () => NotificationOrganizationOptions.parse(options.toWire()),
        throwsFormatException,
      );
    }
    for (final types in [
      [
        {'type': 'chat', 'mode': 'inherit'},
        {'type': 'chat', 'mode': 'disabled'},
      ],
      [
        {'type': 'unknown', 'mode': 'disabled'},
      ],
      [
        {'type': 'chat', 'mode': 'unknown'},
      ],
    ]) {
      expect(
        () => NotificationOrganizationOptions.parse({
          ...const NotificationOrganizationOptions().toWire(),
          'typeRules': types,
        }),
        throwsFormatException,
      );
    }
  });
  test(
    'all new copy is present in three languages with correct activity source',
    () {
      for (final locale in AppStrings.supportedLocales) {
        final strings = AppStrings.resolve(locale);
        for (final key in [
          'summary',
          'chat',
          'announcement',
          'announcementHint',
          'inheritFleet',
          'inheritOrganization',
          'enabled',
          'disabled',
          'quiet',
          'start',
          'end',
          'localClock',
          'quietHint',
          'invalidTime',
          'rallyIndependent',
          'upgrade',
          'save',
          'unavailableEvents',
        ]) {
          final full = 'settings.notification.organization.$key';
          expect(strings.text(full), isNot(full));
          expect(strings.text(full), isNot(contains('待确认')));
        }
        final label = strings.text(
          'settings.notification.activity.audience.officialFleet',
        );
        expect(label, isNot(contains('RSI')));
        expect(label, isNot(contains('主舰队')));
      }
    },
  );
  for (final official in [false, true]) {
    testWidgets(
      'expanded organization controls and scoped save official=$official',
      (tester) async {
        size(tester, const Size(1000, 1200));
        final port = _Port();
        addTearDown(port.events.close);
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OrganizationNotificationPane(
                create: () => port,
                communityCode: official ? null : 'SYNTHETIC',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controls = tester.widget<NotificationOrganizationControls>(
          find.byType(NotificationOrganizationControls),
        );
        expect(controls.official, official);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.text('每天定时免打扰'), findsOneWidget);
        expect(
          find.byKey(
            ValueKey('organization-announcement-${controls.sourceRef}'),
          ),
          findsOneWidget,
        );
        expect(controls.value.announcement, NotificationChatMode.inherit);
        final announcementField = find.byKey(
          ValueKey((
            'announcement',
            controls.sourceRef,
            NotificationChatMode.inherit,
          )),
        );
        expect(
          tester
              .state<FormFieldState<NotificationChatMode>>(announcementField)
              .value,
          NotificationChatMode.inherit,
        );
        expect(
          find.descendant(
            of: announcementField,
            matching: find.text('跟随上方提醒模式'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('当前没有独立活动提醒'), findsOneWidget);
        expect(
          find.textContaining('Ctrl+Alt+Y'),
          official ? findsOneWidget : findsNothing,
        );
        expect(find.byType(ExpansionTile), findsNothing);
        controls.onChanged(
          controls.value.copyWith(
            chat: NotificationChatMode.enabled,
            announcement: NotificationChatMode.disabled,
            quietEnabled: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('organization-notification-save-options')),
        );
        await tester.tap(
          find.byKey(const Key('organization-notification-save-options')),
        );
        await tester.pumpAndSettle();
        final key = official ? _official : _community;
        expect(port.writes.single.keys, [key]);
        expect(port.writes.single[key]!.chat, NotificationChatMode.enabled);
        expect(
          port.writes.single[key]!.announcement,
          NotificationChatMode.disabled,
        );
        expect(
          port.value.sources
              .singleWhere((s) => s.sourceRef != key)
              .organizationOptions,
          const NotificationOrganizationOptions(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'global editor saves source mode and organization options in one revision',
    (tester) async {
      size(tester, const Size(1100, 1500));
      final port = _Port();
      addTearDown(port.events.close);
      await tester.pumpWidget(
        app(
          NotificationEditorFrame(
            owner: port,
            child: SingleChildScrollView(
              child: NotificationSourcesConnectedPanel(port: port),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var controls = tester
          .widgetList<NotificationOrganizationControls>(
            find.byType(NotificationOrganizationControls),
          )
          .first;
      controls.onChanged(
        controls.value.copyWith(
          chat: NotificationChatMode.enabled,
          announcement: NotificationChatMode.inherit,
        ),
      );
      await tester.pumpAndSettle();
      controls = tester
          .widgetList<NotificationOrganizationControls>(
            find.byType(NotificationOrganizationControls),
          )
          .last;
      controls.onChanged(
        controls.value.copyWith(
          quietEnabled: true,
          startMinute: 120,
          endMinute: 240,
        ),
      );
      await tester.pumpAndSettle();
      expect(port.writes, isEmpty);
      final element = tester.element(
        find.byType(NotificationOrganizationControls).first,
      );
      expect(await NotificationDraftScope.of(element)!.save(), isTrue);
      await tester.pumpAndSettle();
      expect(port.writes, hasLength(1));
      expect(
        port.writes.single[_community]!.chat,
        NotificationChatMode.enabled,
      );
      expect(port.writes.single[_official]!.startMinute, 120);
      expect(
        port.writes.single[_community]!.announcement,
        NotificationChatMode.inherit,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('invalid time remains editable and blocks organization save', (
    tester,
  ) async {
    size(tester, const Size(1000, 1200));
    final port = _Port();
    addTearDown(port.events.close);
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: OrganizationNotificationPane(
            create: () => port,
            communityCode: 'SYNTHETIC',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ValueKey('organization-quiet-start-$_community')),
      '25:00',
    );
    await tester.pumpAndSettle();
    expect(find.text('请填写 00:00–23:59 的时间，开始和结束不能相同。'), findsOneWidget);
    expect(port.writes, isEmpty);
    await tester.enterText(
      find.byKey(ValueKey('organization-quiet-start-$_community')),
      '23:59',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NotificationOrganizationControls>(
            find.byType(NotificationOrganizationControls),
          )
          .value
          .startMinute,
      1439,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid global draft stays editable without sending a write', (
    tester,
  ) async {
    size(tester, const Size(1100, 1500));
    final port = _Port();
    addTearDown(port.events.close);
    await tester.pumpWidget(
      app(
        NotificationEditorFrame(
          owner: port,
          child: SingleChildScrollView(
            child: NotificationSourcesConnectedPanel(port: port),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var controls = tester
        .widgetList<NotificationOrganizationControls>(
          find.byType(NotificationOrganizationControls),
        )
        .first;
    controls.onChanged(controls.value.copyWith(startMinute: -1));
    await tester.pumpAndSettle();
    final scope = NotificationDraftScope.of(
      tester.element(find.byType(NotificationOrganizationControls).first),
    )!;
    expect(await scope.save(), isFalse);
    await tester.pumpAndSettle();
    expect(port.writes, isEmpty);
    controls = tester
        .widgetList<NotificationOrganizationControls>(
          find.byType(NotificationOrganizationControls),
        )
        .first;
    expect(controls.enabled, isTrue);
    controls.onChanged(controls.value.copyWith(startMinute: 120));
    await tester.pumpAndSettle();
    expect(await scope.save(), isTrue);
    await tester.pumpAndSettle();
    expect(port.writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('myself summary retains existing section navigation', (
    tester,
  ) async {
    size(tester, const Size(1000, 1000));
    await tester.pumpWidget(
      app(
        OrganizationSettingsLayout(
          sections: [
            (
              id: 'privacy',
              icon: StandardIconSemantic.verifiedUser,
              group: 'mineGroup',
            ),
          ],
          label: (key) => key,
          selected: 'privacy',
          onSelected: (_) async {},
          content: const Text('existing-fields'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('organization-personal-result')),
      findsOneWidget,
    );
    expect(find.text('existing-fields'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-nav-privacy')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'v3 negotiates both capabilities and keeps the extended receipt',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities([
        'notificationPolicies.readV3',
        'notificationPolicies.saveV3',
      ]);
      const owner = BridgeAccountContext(
        environment: 'fixture',
        authority: 'fixture',
        subject: 'synthetic',
      );
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        final saving = request.name == 'notificationPolicies.saveV3';
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 1,
              accountContext: owner,
              status: 'ok',
              payload: request.name == 'account.getCurrent'
                  ? {'schemaVersion': 1, 'state': 'signedIn'}
                  : {
                      ..._wire(
                        3,
                        chat: saving
                            ? NotificationChatMode.disabled
                            : NotificationChatMode.inherit,
                        announcement: saving
                            ? NotificationChatMode.enabled
                            : NotificationChatMode.disabled,
                      ),
                      if (saving) 'revision': 1,
                      if (saving) 'operationId': request.payload['operationId'],
                    },
            ),
          ),
        );
      });
      final port = BridgeNotificationSources(session);
      addTearDown(() async {
        port.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
      final original = await port.read();
      expect(requests.last.name, 'notificationPolicies.readV3');
      final next = await port.saveOrganizationOptions(
        original,
        original.modes,
        {
          _community: original.sources.last.organizationOptions.copyWith(
            chat: NotificationChatMode.disabled,
            announcement: NotificationChatMode.enabled,
          ),
        },
      );
      expect(requests.last.name, 'notificationPolicies.saveV3');
      expect(
        next.sources.last.organizationOptions.chat,
        NotificationChatMode.disabled,
      );
      expect(next.supportsOrganizationOptions, isTrue);
      expect(
        next.sources.last.organizationOptions.announcement,
        NotificationChatMode.enabled,
      );
      session.acceptHostCapabilities(['notificationPolicies.readV3']);
      final before = requests.length;
      await expectLater(
        port.save(next, next.modes),
        throwsA(isA<BridgeClientException>()),
      );
      expect(requests.length, before);
    },
  );
}
