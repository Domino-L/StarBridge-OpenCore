import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart' hide LocalHistoryEntry;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_port.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_sources_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart';
import 'package:starbridge_flutter/features/settings/local_event_history_dialog.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_page.dart';

import 'interaction_batch3ac_test.dart' show Live, LiveState;
import 'interaction_batch3aa_test.dart' show open, select;
import '../../features/friends/social_layout_test.dart' show size, loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/settings/player_activity_test.dart' show data;
import '../../features/settings/notification_sources_test.dart' as sources;
import '../../features/tools/exec_hangar_test.dart' show Port;

Future<LiveState> mount(
  WidgetTester t,
  Widget child,
  InteractionSuite suite, {
  double width = 760,
  double scale = 1,
  GlobalKey? capture,
}) async {
  size(t, const Size(1280, 1100));
  final key = GlobalKey<LiveState>();
  final app = Live(
    Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, height: 1060, child: child),
    ),
    suite,
    key: key,
    scale: scale,
  );
  await t.pumpWidget(
    capture == null ? app : RepaintBoundary(key: capture, child: app),
  );
  await settleCommunityImages(t);
  return key.currentState!;
}

Finder byControl<T>(Key key) => find.byWidgetPredicate(
  (w) => w is StarBridgeSelectFormField<T> && w.controlKey == key,
);

Future<void> pick<T>(
  WidgetTester t,
  Finder finder,
  T value,
  String source, {
  bool settle = true,
}) async {
  final config = t.widget<StarBridgeSelectFormField<T>>(finder);
  if (source == 'reader') {
    final target = find.byKey(config.controlKey!);
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await t.pump();
    await t.pump();
  } else {
    await open(t, config.controlKey!, source);
  }
  await t.pumpAndSettle();
  final row = find.byKey(ValueKey<Object>((config.identity, value)));
  await t.ensureVisible(row);
  await t.pumpAndSettle();
  if (source == 'reader') {
    final node = t.getSemantics(row);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await t.pump();
    await t.pump();
  } else {
    await select(t, config.identity, value as Object, source);
  }
  if (settle) await settleCommunityImages(t);
}

Future<void> press(WidgetTester t, Key key) async {
  final target = find.byKey(key);
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pump();
  await t.pump();
}

class AccountHeld implements AccountPort {
  final delegate = InMemoryAccountAdapter.forReview(
    AccountReviewState.signedIn,
  );
  final saves = <SaveAccountPreferences>[];
  Completer<AccountPortResult>? hold;
  @override
  Stream<AccountInvalidation> get invalidations => delegate.invalidations;
  @override
  Future<AccountPortResult> read() => delegate.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) {
    if (command is SaveAccountPreferences) {
      saves.add(command);
      if (hold != null) return hold!.future;
    }
    return delegate.execute(command);
  }

  @override
  Future<void> close() => delegate.close();
}

class NotificationPort implements NotificationSettingsPort {
  final delegate = InMemoryNotificationSettingsAdapter.forReview();
  final writes = <(NotificationSettingsValue, int)>[];
  @override
  Stream<void> get invalidations => delegate.invalidations;
  @override
  Future<NotificationSettingsSnapshot> read() => delegate.read();
  @override
  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue value, {
    required int expectedRevision,
  }) {
    writes.add((value, expectedRevision));
    return delegate.update(value, expectedRevision: expectedRevision);
  }

  @override
  Future<void> close() => delegate.close();
}

class PlayPort implements ContinuousPlayPort {
  ContinuousPlayValue current = const ContinuousPlayValue(
    enabled: true,
    firstMinutes: 120,
    repeatMinutes: 120,
    revision: 4,
  );
  final writes = <ContinuousPlayValue>[];
  Completer<ContinuousPlayValue>? hold;
  @override
  Future<ContinuousPlayValue> read() async => current;
  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async {
    writes.add(desired);
    if (hold != null) return hold!.future;
    return current = ContinuousPlayValue(
      enabled: desired.enabled,
      firstMinutes: desired.firstMinutes,
      repeatMinutes: desired.repeatMinutes,
      revision: current.revision + 1,
    );
  }
}

class HistoryPort implements LocalHistoryPort {
  final requests = <(String, int, int, String?)>[];
  Completer<LocalHistoryPage>? hold;
  LocalHistoryPage page(String category, int offset, int limit) =>
      LocalHistoryPage(
        state: 'ready',
        totalCount: 2,
        filteredCount: 1,
        offset: offset,
        pageSize: limit,
        hasMore: false,
        revision: 'A' * 64,
        entries: [
          LocalHistoryEntry(
            id: 'entry',
            at: DateTime.utc(2026, 10, 9),
            category: category == 'all' ? 'ship' : category,
            eventType: 'Synthetic',
            title: 'Event',
            detail: 'Details',
          ),
        ],
      );
  @override
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async {
    requests.add((category, offset, pageSize, revision));
    return hold == null ? page(category, offset, pageSize) : hold!.future;
  }
}

class SourceHeld extends sources.Fake {
  final hold = Completer<NotificationSourcesValue>();
  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) {
    writes++;
    return hold.future;
  }
}

const first = Key('settings.notification.play.first.title-control');
const repeat = Key('settings.notification.play.repeat.title-control');

SettingsPage navigation({Future<bool> Function(BuildContext)? guard}) =>
    SettingsPage(
      initialSection: SettingsSection.accountIdentity,
      accountAndIdentityBuilder: (_) => const Text('Account content'),
      generalDataBuilder: (_) => const Text('General content'),
      syncPrivacyBuilder: (_) => const Text('Privacy content'),
      notificationsBuilder: (_) => const Text('Notification content'),
      confirmNotificationsLeave: guard,
    );

void main() {
  setUpAll(loadFonts);
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'account preference choices retain draft until explicit save $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = AccountHeld();
            final module = createAccountModule(port);
            addTearDown(module.dispose);
            await module.initialize();
            final live = await mount(t, AccountPage(module: module), suite);
            final locale = byControl<String>(
              const Key('account-locale-control'),
            );
            final zone = byControl<String>(
              const Key('account-time-zone-control'),
            );
            final state = t.state<FormFieldState<String>>(locale);
            await pick(t, locale, 'en-US', source);
            final zoneValue = t
                .widget<StarBridgeSelectFormField<String>>(zone)
                .items!
                .firstWhere(
                  (e) =>
                      e.value!.isNotEmpty &&
                      e.value != module.preferencesDraft.timeZone,
                )
                .value!;
            await pick(t, zone, zoneValue, source);
            expect(port.saves, isEmpty);
            expect(module.preferencesDraft.hasChanges, isTrue);
            live.change(() {
              live.reduce = true;
              live.light = true;
              live.suite = InteractionSuite.glow;
            });
            await settleCommunityImages(t);
            expect(t.state<FormFieldState<String>>(locale), same(state));
            expect(module.preferencesDraft.locale, 'en-US');
            expect(module.preferencesDraft.timeZone, zoneValue);
            await press(t, const Key('account-save-preferences'));
            await settleCommunityImages(t);
            expect(port.saves, hasLength(1));
            expect(port.saves.single.patch.locale, 'en-US');
            expect(port.saves.single.patch.timeZone, zoneValue);
            expect(module.preferencesDraft.hasChanges, isFalse);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'notification positions source and intervals stage then save $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = NotificationPort();
            final module = createNotificationSettingsModule(port);
            addTearDown(module.dispose);
            await module.initialize();
            await mount(
              t,
              NotificationSettingsPage(module: module),
              suite,
              width: 390,
            );
            await pick(
              t,
              byControl<DesktopNotificationPosition>(
                const Key('notification-desktop-position-control'),
              ),
              DesktopNotificationPosition.topLeft,
              source,
            );
            await pick(t, byControl<int>(first), 90, source);
            await pick(t, byControl<int>(repeat), 60, source);
            const sourceRef = 'official-fleet:aster';
            await pick(
              t,
              byControl<NotificationSourceMode>(
                const ValueKey('notification-source-mode-$sourceRef-control'),
              ),
              NotificationSourceMode.doNotDisturb,
              source,
            );
            expect(port.writes, isEmpty);
            expect(port.delegate.current.revision, 11);
            await press(t, const Key('notification-save'));
            await t.pumpAndSettle();
            expect(port.writes, hasLength(1));
            expect(port.writes.single.$2, 11);
            final payload = port.writes.single.$1;
            expect(
              payload.channels.desktopPosition,
              DesktopNotificationPosition.topLeft,
            );
            expect(payload.continuousPlay.firstReminderMinutes, 90);
            expect(payload.continuousPlay.repeatReminderMinutes, 60);
            expect(
              payload.sourceRules
                  .singleWhere((r) => r.sourceRef == sourceRef)
                  .mode,
              NotificationSourceMode.doNotDisturb,
            );
            expect(port.delegate.current.revision, 12);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'standalone play intervals save through their current owner $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = PlayPort();
            final controller = ContinuousPlayController(port);
            addTearDown(controller.dispose);
            final live = await mount(
              t,
              ContinuousPlayConnectedPanel(controller: controller),
              suite,
            );
            await pick(t, byControl<int>(first), 90, source);
            await pick(t, byControl<int>(repeat), 60, source);
            expect(port.writes, hasLength(2));
            expect(port.writes.first.revision, 4);
            expect(port.writes.last.revision, 5);
            expect(controller.value.settings!.firstMinutes, 90);
            expect(controller.value.settings!.repeatMinutes, 60);
            live.change(() {
              live.reduce = true;
              live.light = true;
            });
            await t.pumpAndSettle();
            expect(
              t.state<FormFieldState<int>>(byControl<int>(first)).value,
              90,
            );
            expect(
              t.state<FormFieldState<int>>(byControl<int>(repeat)).value,
              60,
            );
            expect(port.writes, hasLength(2));
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'player activity position preserves exact flags and revision $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            var value = data();
            final writes = <Map<String, Object?>>[];
            final controller = PlayerActivityController((name, payload) async {
              if (name == 'playerActivity.save') {
                writes.add(payload);
                value = {
                  ...value,
                  'position': payload['position'],
                  'revision': 'A' * 64,
                };
              }
              return value;
            }, generation: () => 1);
            addTearDown(controller.dispose);
            await mount(
              t,
              PlayerActivityConnectedPanel(
                controller: controller,
                showClose: false,
              ),
              suite,
            );
            await pick(
              t,
              byControl<int>(const Key('activity-position-control')),
              0,
              source,
            );
            expect(writes, hasLength(1));
            expect(writes.single['position'], 0);
            expect(writes.single['expectedRevision'], 'missing');
            expect(writes.single['scope'], 2);
            expect(writes.single['online'], isTrue);
            expect(writes.single['offline'], isFalse);
            expect(controller.current!.position, 0);
            expect(
              t
                  .state<FormFieldState<int>>(
                    byControl<int>(const Key('activity-position-control')),
                  )
                  .value,
              0,
            );
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'history category starts original bounded read with no clear/export $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = HistoryPort();
            final controller = LocalHistoryController(port);
            addTearDown(controller.dispose);
            await mount(
              t,
              LocalEventHistoryDialog(controller: controller, embedded: true),
              suite,
            );
            await pick(
              t,
              byControl<String>(const Key('history-category-control')),
              'ship',
              source,
            );
            expect(port.requests, hasLength(2));
            expect(port.requests.last, ('ship', 0, 50, null));
            expect(controller.value.category, 'ship');
            expect(controller.value.page!.entries.single.title, 'Event');
            expect(t.takeException(), isNull);
            controller.dispose();
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'monitor duration validates and reaches original finite command $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = Port();
            await mount(t, ExecHangarPage(port: port), suite, width: 1000);
            await press(t, const Key('exec-on-close'));
            await t.pumpAndSettle();
            await pick(
              t,
              byControl<int>(const Key('exec-monitor-mode-control')),
              0,
              source,
            );
            await pick(t, byControl<int>(const Key('exec-watch-hours')), 0, source);
            await pick(
              t,
              byControl<int>(const Key('exec-watch-minutes')),
              0,
              source,
            );
            await press(t, const Key('exec-start'));
            await t.pumpAndSettle();
            expect(port.starts, 0);
            expect(port.saves, 0);
            await pick(
              t,
              byControl<int>(const Key('exec-watch-minutes')),
              5,
              source,
            );
            await press(t, const Key('exec-start'));
            await t.pumpAndSettle();
            expect(port.starts, 1);
            expect(port.duration, 5);
            expect(port.onlyNext, isFalse);
            expect(port.saves, 1);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'compact settings navigation uses original selected owner $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            await mount(t, navigation(), suite, width: 390);
            final finder = byControl<SettingsSection>(
              const Key('settings-section-control'),
            );
            await pick(t, finder, SettingsSection.generalData, source);
            expect(find.text('General content'), findsOneWidget);
            expect(find.text('Account content'), findsNothing);
            await pick(t, finder, SettingsSection.notifications, source);
            expect(find.text('Notification content'), findsOneWidget);
            expect(
              t.state<FormFieldState<SettingsSection>>(finder).value,
              SettingsSection.notifications,
            );
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      'cached account preferences keep both selectors read-only $suite',
      (t) async {
        final port = InMemoryAccountAdapter.forReview(
          AccountReviewState.cached,
        );
        final module = createAccountModule(port);
        addTearDown(module.dispose);
        await module.initialize();
        await mount(t, AccountPage(module: module), suite);
        for (final key in [
          const Key('account-locale-control'),
          const Key('account-time-zone-control'),
        ]) {
          expect(byControl<String>(key), findsOneWidget);
          expect(
            t
                .widget<StarBridgeSelectFormField<String>>(
                  byControl<String>(key),
                )
                .onChanged,
            isNull,
          );
        }
        expect(port.commands, isEmpty);
        expect(module.preferencesDraft.hasChanges, isFalse);
        await t.pumpWidget(const SizedBox());
        module.dispose(); // Release the cached-profile recovery timer before invariants.
      },
    );

    testWidgets('disabled reminder keeps both interval controls inert $suite', (
      t,
    ) async {
      final port = PlayPort()
        ..current = const ContinuousPlayValue(
          enabled: false,
          firstMinutes: 120,
          repeatMinutes: 120,
          revision: 4,
        );
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      await mount(
        t,
        ContinuousPlayConnectedPanel(controller: controller),
        suite,
      );
      for (final key in [first, repeat]) {
        expect(
          t
              .widget<StarBridgeSelectFormField<int>>(byControl<int>(key))
              .onChanged,
          isNull,
        );
      }
      expect(port.writes, isEmpty);
      expect(controller.value.settings!.enabled, isFalse);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
      'notification refused save keeps staged choice distinct from saved value $suite',
      (t) async {
        final port = NotificationPort();
        final module = createNotificationSettingsModule(port);
        addTearDown(module.dispose);
        await module.initialize();
        final original =
            port.delegate.current.settings!.channels.desktopPosition;
        await mount(
          t,
          NotificationSettingsPage(module: module),
          suite,
          width: 390,
        );
        final finder = byControl<DesktopNotificationPosition>(
          const Key('notification-desktop-position-control'),
        );
        final next = original == DesktopNotificationPosition.topLeft
            ? DesktopNotificationPosition.bottomRight
            : DesktopNotificationPosition.topLeft;
        await pick(t, finder, next, 'keyboard');
        port.delegate.failNextUpdate = true;
        await press(t, const Key('notification-save'));
        await t.pumpAndSettle();
        expect(port.writes, hasLength(1));
        expect(
          port.delegate.current.settings!.channels.desktopPosition,
          original,
        );
        expect(
          t.state<FormFieldState<DesktopNotificationPosition>>(finder).value,
          next,
        );
        await t.pump(const Duration(seconds: 1));
        expect(port.writes, hasLength(1));
        await press(t, const Key('notification-save'));
        await t.pumpAndSettle();
        expect(port.writes, hasLength(2));
        expect(port.writes.last.$2, 11);
        expect(port.delegate.current.settings!.channels.desktopPosition, next);
        await t.pumpWidget(const SizedBox());
      },
    );

    for (final answer in [true, false]) {
      testWidgets(
        'navigation departure ignores late leave answer $suite $answer',
        (t) async {
          final held = Completer<bool>();
          var guards = 0;
          final live = await mount(
            t,
            navigation(
              guard: (_) {
                guards++;
                return held.future;
              },
            ),
            suite,
            width: 390,
          );
          final finder = byControl<SettingsSection>(
            const Key('settings-section-control'),
          );
          await pick(t, finder, SettingsSection.notifications, 'keyboard');
          await pick(
            t,
            finder,
            SettingsSection.generalData,
            'keyboard',
            settle: false,
          );
          live.change(() => live.visible = false);
          await t.pump();
          await t.pump();
          held.complete(answer);
          await t.pumpAndSettle();
          expect(guards, 1);
          expect(find.byType(SettingsPage), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'account pending preference refusal retains editable draft $suite',
      (t) async {
        final port = AccountHeld()..hold = Completer<AccountPortResult>();
        final module = createAccountModule(port);
        addTearDown(module.dispose);
        await module.initialize();
        await mount(t, AccountPage(module: module), suite);
        final finder = byControl<String>(const Key('account-locale-control'));
        await pick(t, finder, 'en-US', 'keyboard');
        await press(t, const Key('account-save-preferences'));
        expect(port.saves, hasLength(1));
        expect(
          t.widget<StarBridgeSelectFormField<String>>(finder).onChanged,
          isNull,
        );
        port.hold!.complete(
          const AccountPortResult.failed(
            AccountFailure(
              code: 'profile.write_failed',
              messageKey: 'account.error.writeFailed',
              retryable: true,
            ),
          ),
        );
        await settleCommunityImages(t);
        expect(module.preferencesDraft.locale, 'en-US');
        expect(module.preferencesDraft.hasChanges, isTrue);
        expect(t.state<FormFieldState<String>>(finder).value, 'en-US');
        expect(port.saves, hasLength(1));
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'play pending write disables choices and refusal restores native form $suite',
      (t) async {
        final port = PlayPort()..hold = Completer<ContinuousPlayValue>();
        final controller = ContinuousPlayController(port);
        addTearDown(controller.dispose);
        final live = await mount(
          t,
          ContinuousPlayConnectedPanel(controller: controller),
          suite,
        );
        final finder = byControl<int>(first);
        await pick(t, finder, 90, 'keyboard', settle: false);
        expect(port.writes, hasLength(1));
        expect(
          t.widget<StarBridgeSelectFormField<int>>(finder).onChanged,
          isNull,
        );
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        port.hold!.completeError(StateError('refused'));
        await t.pumpAndSettle();
        expect(controller.value.settings!.firstMinutes, 120);
        expect(t.state<FormFieldState<int>>(finder).value, 120);
        expect(port.writes, hasLength(1));
        expect(controller.value.failed, isTrue);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'player position failure preserves verified settings and blocks replay $suite',
      (t) async {
        final held = Completer<Map<String, Object?>>();
        final writes = <Map<String, Object?>>[];
        final controller = PlayerActivityController((name, payload) async {
          if (name == 'playerActivity.save') {
            writes.add(payload);
            return held.future;
          }
          return data();
        }, generation: () => 1);
        addTearDown(controller.dispose);
        await mount(
          t,
          PlayerActivityConnectedPanel(
            controller: controller,
            showClose: false,
          ),
          suite,
        );
        final finder = byControl<int>(const Key('activity-position-control'));
        await pick(t, finder, 0, 'keyboard', settle: false);
        expect(
          t.widget<StarBridgeSelectFormField<int>>(finder).onChanged,
          isNull,
        );
        held.completeError(StateError('write rejected'));
        await t.pumpAndSettle();
        expect(controller.current!.position, 3);
        expect(t.state<FormFieldState<int>>(finder).value, 3);
        expect(writes, hasLength(1));
        expect(controller.canEdit, isFalse);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'history departure ignores pending category read without fallback $suite',
      (t) async {
        final port = HistoryPort();
        final controller = LocalHistoryController(port);
        addTearDown(controller.dispose);
        final live = await mount(
          t,
          LocalEventHistoryDialog(controller: controller, embedded: true),
          suite,
        );
        port.hold = Completer<LocalHistoryPage>();
        await pick(
          t,
          byControl<String>(const Key('history-category-control')),
          'ship',
          'keyboard',
          settle: false,
        );
        expect(
          t
              .widget<StarBridgeSelectFormField<String>>(
                byControl<String>(const Key('history-category-control')),
              )
              .onChanged,
          isNull,
        );
        live.change(() => live.visible = false);
        await t.pump();
        await t.pump();
        controller.dispose();
        port.hold!.complete(port.page('ship', 0, 50));
        await t.pumpAndSettle();
        expect(port.requests, hasLength(2));
        expect(find.byType(LocalEventHistoryDialog), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'narrow sources pending refusal does not publish or replay $suite',
      (t) async {
        final port = SourceHeld();
        await mount(
          t,
          NotificationEditorFrame(
            owner: Object(),
            child: SingleChildScrollView(
              child: NotificationSourcesConnectedPanel(port: port),
            ),
          ),
          suite,
          width: 390,
        );
        final finder = byControl<NotificationSourceMode>(
          const ValueKey('notification-source-mode-room-control'),
        );
        await pick(t, finder, NotificationSourceMode.doNotDisturb, 'keyboard');
        expect(port.writes, 0);
        await press(t, const Key('notification-save'));
        expect(port.writes, 1);
        expect(
          t
              .widget<StarBridgeSelectFormField<NotificationSourceMode>>(finder)
              .onChanged,
          isNull,
        );
        port.hold.completeError(StateError('unconfirmed'));
        await t.pumpAndSettle();
        expect(port.value.modes['room'], NotificationSourceMode.normal);
        expect(
          t.state<FormFieldState<NotificationSourceMode>>(finder).value,
          NotificationSourceMode.doNotDisturb,
        );
        expect(
          t
              .widget<StarBridgeSelectFormField<NotificationSourceMode>>(finder)
              .onChanged,
          isNull,
        );
        expect(port.writes, 1);
        await t.pumpWidget(const SizedBox());
        port.dispose();
      },
    );

    testWidgets(
      'compact navigation refusal repairs original FormState and source $suite',
      (t) async {
        final held = Completer<bool>();
        var guards = 0;
        InteractionSource? source;
        await mount(
          t,
          navigation(
            guard: (_) {
              guards++;
              source = currentStarBridgeActivationSource;
              return held.future;
            },
          ),
          suite,
          width: 390,
        );
        final finder = byControl<SettingsSection>(
          const Key('settings-section-control'),
        );
        await pick(t, finder, SettingsSection.notifications, 'keyboard');
        final before = t.state<FormFieldState<SettingsSection>>(finder);
        await pick(
          t,
          finder,
          SettingsSection.generalData,
          'keyboard',
          settle: false,
        );
        expect(find.text('Notification content'), findsOneWidget);
        expect(guards, 1);
        expect(source, InteractionSource.keyboard);
        held.complete(false);
        await t.pumpAndSettle();
        expect(find.text('Notification content'), findsOneWidget);
        expect(t.state<FormFieldState<SettingsSection>>(finder), same(before));
        expect(before.value, SettingsSection.notifications);
        expect(guards, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('review compact settings picker at200 percent $suite', (
      t,
    ) async {
      final capture = GlobalKey();
      await mount(
        t,
        navigation(),
        suite,
        width: 390,
        scale: 2,
        capture: capture,
      );
      await open(t, const Key('settings-section-control'), 'pointer');
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 500));
      for (final section in visibleSettingsSections) {
        expect(
          find.byKey(ValueKey<Object>(('settings-section', section))),
          findsOneWidget,
        );
      }
      final rectangles = [
        for (final section in visibleSettingsSections)
          t.getRect(
            find.byKey(ValueKey<Object>(('settings-section', section))),
          ),
      ];
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        final counts = <int>[];
        for (final rect in rectangles) {
          var count = 0;
          for (var y = rect.top.ceil() + 4; y < rect.bottom.floor() - 4; y++) {
            for (
              var x = rect.left.ceil() + 10;
              x < rect.right.floor() - 10;
              x++
            ) {
              final n = (y * image.width + x) * 4;
              if (raw[n] >= 125 &&
                  raw[n] <= 175 &&
                  raw[n + 1] >= 145 &&
                  raw[n + 1] <= 190 &&
                  raw[n + 2] >= 150 &&
                  raw[n + 2] <= 200 &&
                  raw[n + 3] >= 240) {
                count++;
              }
            }
          }
          counts.add(count);
        }
        expect(
          counts,
          everyElement(greaterThan(5)),
          reason: 'Each settings option paints foreground text, not just geometry or semantics.',
        );
        Directory('build/reviews/interaction-batch3ad')
            .createSync(recursive: true);
        File(
          'build/reviews/interaction-batch3ad/${suite.name}-navigation-200.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
