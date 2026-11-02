import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/tools/tools_feature.dart';
import 'package:starbridge_flutter/features/tools/tools_page.dart';
import 'package:starbridge_flutter/features/tools/cached_exec_hangar.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_page.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_controller.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_monitor_panel.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_schedule.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_overview.dart';

import '../friends/social_layout_test.dart' show size, loadFonts, capture;
import 'exec_hangar_presets.dart';

final origin = DateTime.utc(2026, 10, 9);

Future<void> captureHangar(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_EXEC'] != '1') return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/reviews').create(recursive: true);
    await File('build/reviews/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

ExecHangarSnapshot sample({
  bool reliable = true,
  bool refreshFailed = false,
  ExecHangarReminders reminders = const ExecHangarReminders(),
  int revision = 0,
  ExecHangarPlan? plan,
  DateTime? at,
  List<ExecHangarPhase>? phases,
  String deliveryState = 'idle',
  String monitoringSource = 'none',
  String gameMonitoringState = 'disabled',
}) => ExecHangarSnapshot(
  revision: revision,
  plan: plan,
  monitoringSource: monitoringSource,
  gameMonitoringState: gameMonitoringState,
  reminders: reminders,
  now: at ?? origin,
  reliable: reliable,
  refreshFailed: refreshFailed,
  deliveryState: deliveryState,
  version: 'fixture',
  lastModified: 'fixture',
  fetchedAt: origin,
  sourceUrl: 'https://example.org/calibration',
  phases:
      phases ??
      [
        ExecHangarPhase(
          origin,
          origin.add(const Duration(minutes: 12)),
          true,
          5,
          0,
        ),
      ],
  windows: List.generate(
    6,
    (i) => ExecHangarWindow(
      origin.add(Duration(minutes: i * 185)),
      origin.add(Duration(minutes: i * 185 + 65)),
    ),
  ),
);

class Port implements ExecHangarPort {
  ExecHangarSnapshot snapshot = sample();
  int reads = 0, saves = 0;
  bool fail = false;
  int starts = 0, duration = 0;
  bool onlyNext = false;
  @override
  Future<ExecHangarSnapshot> monitor(
    ExecHangarAction action,
    int revision, {
    int durationMinutes = 60,
    bool onlyNext = false,
  }) async {
    if (fail || revision != snapshot.revision) throw StateError('monitor');
    starts++;
    duration = durationMinutes;
    this.onlyNext = onlyNext;
    final old = snapshot.reminders;
    snapshot = sample(
      reminders: ExecHangarReminders(
        enabled: action != ExecHangarAction.stop,
        onOpen: old.onOpen,
        beforeOpen: old.beforeOpen,
        beforeOpenMinutes: old.beforeOpenMinutes,
        beforeChange: false,
        beforeClose: old.beforeClose,
        beforeCloseMinutes: old.beforeCloseMinutes,
        onClose: old.onClose,
        autoDuringGame: old.autoDuringGame,
      ),
      revision: revision + 1,
      plan: ExecHangarPlan(
        active: action != ExecHangarAction.stop,
        state: action == ExecHangarAction.stop ? 'stopped' : 'watching',
        onlyNext: onlyNext,
        endsAt: action == ExecHangarAction.continuous
            ? null
            : origin.add(Duration(minutes: durationMinutes)),
      ),
    );
    return snapshot;
  }

  @override
  Future<ExecHangarSnapshot> read({bool refresh = false}) async {
    reads++;
    if (fail) throw StateError('offline');
    return snapshot;
  }

  @override
  Future<ExecHangarSnapshot> save(
    ExecHangarReminders reminders,
    int revision,
  ) async {
    saves++;
    if (fail) throw StateError('write');
    if (revision != snapshot.revision) throw StateError('conflict');
    snapshot = sample(reminders: reminders, revision: revision + 1);
    return snapshot;
  }
}

final class DelayedPort extends Port {
  Completer<ExecHangarSnapshot>? pending;
  @override
  Future<ExecHangarSnapshot> read({bool refresh = false}) {
    if (pending case final value?) {
      reads++;
      return value.future;
    }
    return super.read(refresh: refresh);
  }
}

class ExperiencePort extends Port implements ExecHangarExperiencePort {
  int previews = 0, tests = 0;
  String testDeliveryState = 'idle';
  Completer<ExecHangarSnapshot>? delayedPreview;
  @override
  Future<ExecHangarSnapshot> preview(
    ExecHangarReminders reminders,
    int minutes,
    bool onlyNext,
  ) async {
    previews++;
    if (delayedPreview != null) return delayedPreview!.future;
    return sample(
      reminders: reminders,
      plan: ExecHangarPlan(
        active: true,
        state: 'watching',
        onlyNext: onlyNext,
        endsAt: minutes == -1 ? null : origin.add(Duration(minutes: minutes)),
        next: ExecHangarNotice(
          origin.add(const Duration(minutes: 10)),
          origin.add(const Duration(minutes: 15)),
          false,
          kind: 'leave',
        ),
      ),
    );
  }

  @override
  Future<ExecHangarSnapshot> testReminder() async {
    tests++;
    return sample(deliveryState: testDeliveryState);
  }
}

Widget app(Widget child, Locale locale, AppearanceMode mode) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(FutureRestraintStyle.resolve(mode), locale),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'continuous mode starts without a finite end or only-next restriction',
    (tester) async {
      final port = ExperiencePort();
      size(tester, const Size(1440, 1000));
      await tester.pumpWidget(
        app(
          ExecHangarPage(port: port),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exec-monitor-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一直监测').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exec-only-next')), findsNothing);
      await tester.tap(find.byKey(const Key('exec-start')));
      await tester.pumpAndSettle();
      expect(port.duration, -1);
      expect(port.onlyNext, isFalse);
      expect(port.snapshot.plan?.endsAt, isNull);
      expect(find.text('正在持续监测'), findsOneWidget);
      expect(find.byKey(const Key('exec-add-hour')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'automatic game preference saves without starting a manual timer',
    (tester) async {
      final port = Port();
      size(tester, const Size(1440, 1000));
      await tester.pumpWidget(
        app(
          ExecHangarPage(port: port),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('exec-auto-game'));
      await tester.ensureVisible(toggle);
      expect(tester.widget<StarBridgeSwitch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(port.snapshot.reminders.autoDuringGame, isFalse);
      await tester.tap(find.byKey(const Key('exec-save')));
      await tester.pumpAndSettle();
      expect(port.snapshot.reminders.autoDuringGame, isTrue);
      expect(port.starts, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(
          ExecHangarPage(port: port),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StarBridgeSwitch>(find.byKey(const Key('exec-auto-game')))
            .value,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'game watch has no artificial end time and stops for this session',
    (tester) async {
      size(tester, const Size(900, 800));
      ExecHangarAction? command;
      await tester.pumpWidget(
        app(
          ExecHangarMonitorPanel(
            snapshot: sample(
              reminders: const ExecHangarReminders(autoDuringGame: true),
              monitoringSource: 'game',
              gameMonitoringState: 'watching',
              plan: ExecHangarPlan(
                active: true,
                state: 'watching',
                onlyNext: false,
                startedAt: origin,
              ),
            ),
            now: origin,
            busy: false,
            canStart: true,
            onCommand: (action, _, _) => command = action,
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('正在随游戏监测 · 游戏退出后停止'), findsOneWidget);
      expect(find.byKey(const Key('exec-add-hour')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('exec-stop')));
      expect(command, ExecHangarAction.stop);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'game monitoring wire accepts new state and preserves older default',
    () {
      final body = <String, Object?>{
        'schemaVersion': 1,
        'revision': 1,
        'reminders': const ExecHangarReminders(autoDuringGame: true).wire,
        'config': null,
        'fetchedAt': null,
        'now': origin.toIso8601String(),
        'reliable': false,
        'refreshFailed': false,
        'deliveryState': 'idle',
        'phases': <Object>[],
        'windows': <Object>[],
        'monitoringSource': 'none',
        'gameMonitoringState': 'waiting',
      };
      expect(BridgeExecHangar.parse(body).reminders.autoDuringGame, isTrue);
      expect(BridgeExecHangar.parse(body).gameMonitoringState, 'waiting');
      (body['reminders'] as Map<String, Object>).remove('autoDuringGame');
      body.remove('gameMonitoringState');
      body.remove('monitoringSource');
      expect(BridgeExecHangar.parse(body).reminders.autoDuringGame, isFalse);
      body['gameMonitoringState'] = 'invented';
      expect(
        () => BridgeExecHangar.parse(body),
        throwsA(isA<BridgeFormatException>()),
      );
    },
  );
  test('new local hangar actions cross the real client session without account context', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    session.acceptHostCapabilities([
      'execHangar.preview',
      'execHangar.test',
      'execHangar.addHour',
      'execHangar.restore',
      'execHangar.continuous',
    ]);
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: {
            'schemaVersion': 1,
            'revision': 0,
            'reminders': const ExecHangarReminders().wire,
            'config': null,
            'fetchedAt': null,
            'now': origin.toIso8601String(),
            'reliable': false,
            'refreshFailed': false,
            'deliveryState': 'doNotDisturb',
            'phases': <Object>[],
            'windows': <Object>[],
          },
        ),
      );
    });
    addTearDown(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
    final port = BridgeExecHangar(session);
    await port.preview(const ExecHangarReminders(), 60, false);
    expect((await port.testReminder()).deliveryState, 'doNotDisturb');
    await port.monitor(ExecHangarAction.addHour, 0);
    await port.monitor(ExecHangarAction.restore, 0);
    await port.monitor(ExecHangarAction.continuous, 0);
    expect(requests.map((r) => r.name), [
      'execHangar.preview',
      'execHangar.test',
      'execHangar.addHour',
      'execHangar.restore',
      'execHangar.continuous',
    ]);
    expect(
      requests.every(
        (r) => r.accountContext == null && r.sessionGeneration == 7,
      ),
      isTrue,
    );
  });
  testWidgets(
    'legacy continuous monitoring has no invalid finite extension action',
    (tester) async {
      await tester.pumpWidget(
        app(
          ExecHangarMonitorPanel(
            snapshot: sample(
              reminders: const ExecHangarReminders(enabled: true),
              plan: ExecHangarPlan(
                active: true,
                state: 'muted',
                onlyNext: false,
                mutedBoundary: origin.add(const Duration(minutes: 65)),
              ),
            ),
            now: origin,
            busy: false,
            canStart: true,
            onCommand: (_, _, _) {},
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exec-add-hour')), findsNothing);
      expect(find.byKey(const Key('exec-restore')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'monitoring status is separate from restart draft and stop stays available',
    (tester) async {
      size(tester, const Size(900, 1000));
      ExecHangarAction? command;
      await tester.pumpWidget(
        app(
          ExecHangarMonitorPanel(
            snapshot: sample(
              reminders: const ExecHangarReminders(enabled: true),
              plan: ExecHangarPlan(
                active: true,
                state: 'muted',
                onlyNext: false,
                startedAt: origin,
                endsAt: origin.add(const Duration(hours: 2)),
                mutedBoundary: origin.add(const Duration(minutes: 65)),
              ),
            ),
            now: origin,
            busy: false,
            canStart: true,
            onCommand: (action, _, _) => command = action,
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('监测至'), findsOneWidget);
      expect(find.textContaining('execHangar.'), findsNothing);
      expect(find.byKey(const Key('exec-start')), findsNothing);
      expect(find.byKey(const Key('exec-stop')), findsOneWidget);
      await tester.tap(find.byKey(const Key('exec-restore')));
      expect(command, ExecHangarAction.restore);
      await tester.tap(find.byKey(const Key('exec-add-hour')));
      expect(command, ExecHangarAction.addHour);
      await tester.tap(find.byKey(const Key('exec-adjust')));
      await tester.pumpAndSettle();
      expect(find.textContaining('从现在重新计时'), findsOneWidget);
      expect(find.byKey(const Key('exec-start')), findsOneWidget);
      await tester.tap(find.byKey(const Key('exec-stop')));
      expect(command, ExecHangarAction.stop);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'draft preview and notification test do not start or save monitoring',
    (tester) async {
      size(tester, const Size(1000, 1100));
      final port = ExperiencePort();
      await tester.pumpWidget(
        app(
          ExecHangarMonitorPanel(
            snapshot: port.snapshot,
            now: origin,
            busy: false,
            canStart: true,
            previewRules: const ExecHangarReminders(leaveWarning: true),
            experience: port,
            onCommand: (_, _, _) {},
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(port.previews, 1);
      expect(find.textContaining('离场提醒'), findsOneWidget);
      expect(port.starts, 0);
      expect(port.saves, 0);
      await tester.tap(find.byKey(const Key('exec-test')));
      await tester.pumpAndSettle();
      expect(port.tests, 1);
      expect(port.starts, 0);
      expect(port.saves, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final state in [
    'paused',
    'doNotDisturb',
    'fullScreen',
    'inactiveDesktop',
    'quietTime',
    'systemBusy',
    'queueFull',
    'expired',
    'environmentUnknown',
    'desktopUnavailable',
  ]) {
    testWidgets('test feedback identifies $state without saving or starting', (
      tester,
    ) async {
      size(tester, const Size(1000, 1100));
      final port = ExperiencePort()..testDeliveryState = state;
      await tester.pumpWidget(
        app(
          ExecHangarMonitorPanel(
            snapshot: port.snapshot,
            now: origin,
            busy: false,
            canStart: true,
            experience: port,
            onCommand: (_, _, _) {},
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exec-test')));
      await tester.pumpAndSettle();
      final expected = {
        'paused': '当前计时配置不可用',
        'doNotDisturb': 'Windows 勿扰已阻止测试卡片',
        'fullScreen': '当前全屏应用阻止了测试卡片',
        'inactiveDesktop': '当前桌面不可接收提醒',
        'quietTime': 'Windows 当前处于静默时段',
        'systemBusy': 'Windows 当前暂缓显示提醒',
        'queueFull': '待显示的提醒较多',
        'expired': '本次测试已失效',
        'environmentUnknown': '暂时无法确认当前桌面状态',
        'desktopUnavailable': '桌面提醒暂时不可用',
      }[state]!;
      expect(find.textContaining(expected), findsOneWidget);
      expect(find.textContaining('本次测试未送出'), findsNothing);
      expect(port.starts, 0);
      expect(port.saves, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('late draft preview cannot survive page disposal', (
    tester,
  ) async {
    final port = ExperiencePort()
      ..delayedPreview = Completer<ExecHangarSnapshot>();
    await tester.pumpWidget(
      app(
        ExecHangarMonitorPanel(
          snapshot: port.snapshot,
          now: origin,
          busy: false,
          canStart: true,
          previewRules: const ExecHangarReminders(),
          experience: port,
          onCommand: (_, _, _) {},
        ),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(port.previews, 1);
    await tester.pumpWidget(const SizedBox());
    port.delayedPreview!.complete(sample());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'leave rule saves independently while monitoring remains stopped',
    (tester) async {
      size(tester, const Size(1000, 1100));
      final port = Port();
      await tester.pumpWidget(
        app(
          ExecHangarPage(port: port),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('exec-leave-rule')));
      await tester.tap(find.byKey(const Key('exec-leave-rule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exec-save')));
      await tester.pumpAndSettle();
      expect(port.snapshot.reminders.leaveWarning, true);
      expect(port.snapshot.reminders.enabled, false);
      expect(port.starts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('late preview cannot overwrite a newer draft selection', (
    tester,
  ) async {
    final first = Completer<ExecHangarSnapshot>(),
        second = Completer<ExecHangarSnapshot>();
    final port = ExperiencePort()..delayedPreview = first;
    Widget panel(bool leave) => app(
      ExecHangarMonitorPanel(
        snapshot: port.snapshot,
        now: origin,
        busy: false,
        canStart: true,
        previewRules: ExecHangarReminders(leaveWarning: leave),
        experience: port,
        onCommand: (_, _, _) {},
      ),
      const Locale('zh', 'CN'),
      AppearanceMode.dark,
    );
    await tester.pumpWidget(panel(false));
    await tester.pump();
    expect(port.previews, 1);
    port.delayedPreview = second;
    await tester.pumpWidget(panel(true));
    await tester.pump();
    expect(port.previews, 2);
    second.complete(
      sample(
        plan: ExecHangarPlan(
          active: true,
          state: 'watching',
          onlyNext: false,
          endsAt: origin.add(const Duration(hours: 1)),
          next: ExecHangarNotice(
            origin.add(const Duration(minutes: 10)),
            origin.add(const Duration(minutes: 15)),
            false,
            kind: 'leave',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('离场提醒'), findsOneWidget);
    first.complete(
      sample(
        plan: ExecHangarPlan(
          active: true,
          state: 'watching',
          onlyNext: false,
          endsAt: origin.add(const Duration(hours: 1)),
          next: ExecHangarNotice(
            origin.add(const Duration(minutes: 11)),
            origin.add(const Duration(minutes: 16)),
            true,
            kind: 'beforeOpen',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('离场提醒'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('preview and test do not poison accepted monitoring cache', () async {
    final source = ExperiencePort();
    final cache = CachedExecHangar(source);
    final accepted = await cache.read();
    await cache.preview(
      const ExecHangarReminders(leaveWarning: true),
      120,
      true,
    );
    await cache.testReminder();
    expect(identical(cache.snapshot, accepted), true);
    expect(cache.snapshot!.reminders.leaveWarning, false);
  });
  for (final locale in AppStrings.supportedLocales) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets(
        'all-off warning ${locale.toLanguageTag()} ${mode.name} is localized and narrow safe',
        (tester) async {
          size(tester, const Size(520, 500));
          await tester.pumpWidget(
            app(
              Padding(
                padding: const EdgeInsets.all(24),
                child: ExecHangarOverview(
                  phase: ExecHangarPhase(
                    origin,
                    origin.add(const Duration(minutes: 5)),
                    true,
                    0,
                    0,
                  ),
                  nextChange: origin.add(const Duration(minutes: 5)),
                  now: origin,
                ),
              ),
              locale,
              mode,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('exec-leave-warning')), findsOneWidget);
          expect(find.textContaining('execHangar.'), findsNothing);
          expect(find.text('00:05:00'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(
            app(
              ExecHangarOverview(
                phase: ExecHangarPhase(
                  origin,
                  origin.add(const Duration(minutes: 24)),
                  false,
                  0,
                  5,
                ),
                nextChange: origin.add(const Duration(hours: 2)),
                now: origin,
              ),
              locale,
              mode,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('exec-leave-warning')), findsNothing);
        },
      );
    }
  }
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets(
      'leave warning full page ${mode.name} preserves live status and dirty actions',
      (tester) async {
        size(tester, const Size(1440, 1120));
        final key = GlobalKey();
        final port = Port()
          ..snapshot = sample(
            at: origin.add(const Duration(minutes: 62)),
            phases: [
              ExecHangarPhase(
                origin.add(const Duration(minutes: 60)),
                origin.add(const Duration(minutes: 65)),
                true,
                0,
                0,
              ),
            ],
            reminders: const ExecHangarReminders(
              enabled: true,
              leaveWarning: true,
            ),
            plan: ExecHangarPlan(
              active: true,
              state: 'watching',
              onlyNext: false,
              startedAt: origin.add(const Duration(minutes: 59)),
              endsAt: origin.add(const Duration(minutes: 119)),
              next: ExecHangarNotice(
                origin.add(const Duration(minutes: 65)),
                origin.add(const Duration(minutes: 65)),
                false,
                kind: 'close',
              ),
            ),
          );
        await tester.pumpWidget(
          app(
            RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: mode == AppearanceMode.dark
                    ? const Color(0xff080e12)
                    : const Color(0xfff0f5f7),
                child: ExecHangarPage(port: port),
              ),
            ),
            const Locale('zh', 'CN'),
            mode,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('exec-leave-warning')), findsOneWidget);
        expect(find.byKey(const Key('exec-start')), findsNothing);
        expect(find.byKey(const Key('exec-stop')), findsOneWidget);
        await captureHangar(tester, key, 'exec-hangar-leave-${mode.name}');
        await tester.ensureVisible(find.byKey(const Key('exec-leave-rule')));
        await tester.tap(find.byKey(const Key('exec-leave-rule')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('exec-save')).hitTestable(),
          findsOneWidget,
        );
        expect(port.starts, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  setUpAll(loadFonts);
  test('late cached read cannot overwrite monitoring start', () async {
    final port = DelayedPort();
    final cache = CachedExecHangar(port);
    await cache.read();
    port.pending = Completer();
    final oldRead = cache.read();
    await cache.monitor(
      ExecHangarAction.start,
      0,
      durationMinutes: 61,
      onlyNext: true,
    );
    port.pending!.complete(sample());
    await oldRead;
    expect(cache.snapshot?.revision, 1);
    expect(cache.snapshot?.plan?.active, true);
    expect(port.duration, 61);
    expect(port.onlyNext, true);
  });
  testWidgets(
    'event queue orders upcoming boundaries and drops a completed event',
    (tester) async {
      size(tester, const Size(520, 1000));
      final snapshot = sample();
      Widget queue(DateTime now) => app(
        SingleChildScrollView(
          child: ExecHangarSchedule(snapshot: snapshot, now: now),
        ),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      );
      await tester.pumpWidget(queue(origin));
      await tester.pumpAndSettle();
      Finder event(DateTime time, bool opening) => find.byKey(
        ValueKey('exec-event-${time.millisecondsSinceEpoch}-$opening'),
      );
      expect(
        event(origin, true),
        findsNothing,
        reason: 'completed openings do not lead the upcoming queue',
      );
      final close = event(origin.add(const Duration(minutes: 65)), false);
      final opening = event(origin.add(const Duration(minutes: 185)), true);
      expect(
        tester.getTopLeft(close).dy,
        lessThan(tester.getTopLeft(opening).dy),
      );
      expect(find.text('下一次'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('exec-expand-schedule')));
      await tester.tap(find.byKey(const Key('exec-expand-schedule')));
      await tester.pumpAndSettle();
      expect(
        event(origin.add(const Duration(minutes: 990)), false),
        findsOneWidget,
      );
      await tester.pumpWidget(queue(origin.add(const Duration(minutes: 66))));
      await tester.pumpAndSettle();
      expect(close, findsNothing);
      expect(opening, findsOneWidget);
      expect(find.text('下一次'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'custom monitoring validates duration, saves rules and starts finite session',
    (tester) async {
      size(tester, const Size(1440, 1100));
      final port = Port();
      await tester.pumpWidget(
        app(
          ExecHangarPage(port: port),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('exec-on-close')));
      await tester.tap(find.byKey(const Key('exec-on-close')));
      await tester.ensureVisible(
        find.byKey(const Key('exec-monitor-mode-control')),
      );
      await tester.tap(find.byKey(const Key('exec-monitor-mode-control')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义时长').last);
      await tester.pumpAndSettle();
      await pickExecPreset(tester, 'exec-watch-hours', 0);
      await pickExecPreset(tester, 'exec-watch-minutes', 0);
      await tester.ensureVisible(find.byKey(const Key('exec-start')));
      await tester.tap(find.byKey(const Key('exec-start')));
      await tester.pumpAndSettle();
      expect(port.starts, 0);
      expect(port.saves, 0);
      await pickExecPreset(tester, 'exec-watch-hours', 1);
      await pickExecPreset(tester, 'exec-watch-minutes', 10);
      await tester.ensureVisible(find.byKey(const Key('exec-only-next')));
      await tester.tap(find.byKey(const Key('exec-only-next')));
      await tester.ensureVisible(find.byKey(const Key('exec-start')));
      await tester.tap(find.byKey(const Key('exec-start')));
      await tester.pumpAndSettle();
      expect(port.saves, 1);
      expect(port.starts, 1);
      expect(port.duration, 70);
      expect(port.onlyNext, true);
      expect(port.snapshot.reminders.onClose, true);
      expect(port.snapshot.reminders.beforeChange, false);
      await tester.ensureVisible(find.byKey(const Key('exec-stop')));
      await tester.tap(find.byKey(const Key('exec-stop')));
      await tester.pumpAndSettle();
      expect(port.starts, 2);
      expect(port.snapshot.reminders.enabled, false);
      expect(port.snapshot.reminders.onClose, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'no-event monitor explains selected closure and provides extension',
    (tester) async {
      ExecHangarAction? command;
      final snapshot = sample(
        reminders: const ExecHangarReminders(enabled: true),
        plan: ExecHangarPlan(
          active: true,
          state: 'noEvent',
          onlyNext: true,
          endsAt: origin.add(const Duration(minutes: 1)),
          outside: ExecHangarNotice(
            origin.add(const Duration(minutes: 60)),
            origin.add(const Duration(minutes: 65)),
            false,
          ),
        ),
      );
      await tester.pumpWidget(
        app(
          ExecHangarMonitorPanel(
            snapshot: snapshot,
            now: origin,
            busy: false,
            canStart: true,
            onCommand: (action, minutes, once) => command = action,
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('本次监测结束前没有所选事件'), findsOneWidget);
      expect(find.text('延长至这次关闭'), findsOneWidget);
      await tester.tap(find.byKey(const Key('exec-extend')));
      expect(command, ExecHangarAction.extend);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'tools cards open a separate detail route without loading the hub',
    (tester) async {
      final port = Port();
      final features = createToolsFeatures(createPort: () => port);
      String? selected;
      await tester.pumpWidget(
        app(
          Actions(
            actions: {
              OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                onInvoke: (intent) {
                  selected = intent.route;
                  return null;
                },
              ),
            },
            child: Builder(builder: features.first.buildDestination),
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ToolsPage), findsOneWidget);
      expect(find.byKey(const Key('exec-countdown')), findsNothing);
      expect(port.reads, 0);
      await tester.tap(find.byKey(const Key('tool-exec-hangar')));
      expect(selected, '/tools/exec-hangar');
      expect(features.last.navigationParentId, 'tools');
      expect(features.first.ownsNavigationSelection(features.last), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'cached time continues while away; expiry and clock jumps require a read',
    () async {
      var elapsed = Duration.zero;
      var wall = origin;
      final cache = CachedExecHangar(
        Port(),
        elapsed: () => elapsed,
        wallNow: () => wall,
      );
      await cache.read();
      elapsed = const Duration(seconds: 40);
      wall = origin.add(elapsed);
      expect(cache.fresh, true);
      expect(cache.age.inSeconds, 40);
      elapsed = const Duration(seconds: 61);
      wall = origin.add(elapsed);
      expect(cache.fresh, false);
      await cache.read();
      expect(cache.fresh, true);
      wall = wall.add(const Duration(minutes: 5));
      expect(cache.fresh, false);
    },
  );
  test('late cached read cannot overwrite a saved reminder revision', () async {
    final port = DelayedPort();
    final cache = CachedExecHangar(port);
    await cache.read();
    final old = port.snapshot;
    port.pending = Completer<ExecHangarSnapshot>();
    final delayed = cache.read();
    await cache.save(const ExecHangarReminders(enabled: true), 0);
    port.pending!.complete(old);
    await delayed;
    expect(cache.snapshot!.revision, 1);
    expect(cache.snapshot!.reminders.enabled, true);
  });
  testWidgets('reentering tools keeps the accepted countdown without loading', (
    tester,
  ) async {
    final port = DelayedPort();
    final feature = createToolsFeatures(createPort: () => port).last;
    Widget destination() => app(
      Builder(builder: feature.buildDestination),
      const Locale('zh', 'CN'),
      AppearanceMode.dark,
    );
    await tester.pumpWidget(destination());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exec-countdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    port.pending = Completer<ExecHangarSnapshot>();
    await tester.pumpWidget(destination());
    await tester.pump();
    final retained = find
        .byKey(const Key('exec-countdown'))
        .evaluate()
        .isNotEmpty;
    final reads = port.reads;
    port.pending!.complete(port.snapshot);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(
      retained,
      isTrue,
      reason: 'accepted data must render immediately on return',
    );
    expect(reads, 1, reason: 'fresh cached data needs no new entry read');
  });
  test(
    'failed save retains the accepted snapshot; disposed reads cannot publish',
    () async {
      final port = Port();
      final controller = ExecHangarController(port);
      await controller.read();
      port.fail = true;
      expect(
        await controller.save(const ExecHangarReminders(enabled: true)),
        false,
      );
      expect(controller.value.failed, true);
      expect(controller.value.snapshot!.reminders.enabled, false);
      controller.dispose();
      expect(await controller.read(), false);
    },
  );
  testWidgets(
    'tools is available and missing Host reports an actionable unavailable state',
    (tester) async {
      final feature = createToolsFeatures().last;
      expect(feature.availability, FeatureAvailability.available);
      await tester.pumpWidget(
        app(
          Builder(builder: feature.buildDestination),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('未连接倒计时服务'), findsOneWidget);
      expect(find.byKey(const Key('exec-countdown')), findsNothing);
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      for (final width in [520.0, 1440.0]) {
        testWidgets(
          'tools cards ${locale.toLanguageTag()} ${mode.name} $width',
          (tester) async {
            size(tester, Size(width, 1000));
            final key = GlobalKey();
            await tester.pumpWidget(
              app(
                RepaintBoundary(
                  key: key,
                  child: Builder(
                    builder: (context) => ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const ToolsPage(),
                    ),
                  ),
                ),
                locale,
                mode,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('tool-exec-hangar')), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (locale.countryCode == 'CN' && width == 1440) {
              await capture(tester, key, 'tools-cards-${mode.name}');
            }
            await tester.pumpWidget(const SizedBox());
          },
        );
        testWidgets('hangar ${locale.toLanguageTag()} ${mode.name} $width', (
          tester,
        ) async {
          size(tester, Size(width, 1000));
          final key = GlobalKey();
          final port = Port();
          await tester.pumpWidget(
            app(
              RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: ExecHangarPage(port: port),
                  ),
                ),
              ),
              locale,
              mode,
            ),
          );
          await tester.pumpAndSettle();
          final copy = AppStrings.resolve(locale);
          expect(find.text(copy.text('execHangar.title')), findsOneWidget);
          expect(find.text('01:05:00'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (locale.countryCode == 'CN' || locale.languageCode == 'en') {
            final suffix = width == 1440 && locale.countryCode == 'CN'
                ? ''
                : '-${locale.toLanguageTag()}-${width.toInt()}';
            await captureHangar(tester, key, 'exec-hangar-${mode.name}$suffix');
          }
          await tester.pump(const Duration(seconds: 5));
          expect(
            port.reads,
            1,
            reason: 'seconds are presentation, not bridge/network polling',
          );
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('desktop monitor and save remain reachable without scrolling', (
    tester,
  ) async {
    size(tester, const Size(1100, 760));
    final port = Port();
    await tester.pumpWidget(
      app(
        ExecHangarPage(port: port),
        const Locale('en', 'US'),
        AppearanceMode.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exec-start')).hitTestable(), findsOneWidget);
    await pickExecPreset(tester, execBeforeOpen, 10);
    expect(find.byKey(const Key('exec-save')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('exec-save')));
    await tester.pumpAndSettle();
    expect(port.saves, 1);
    expect(port.snapshot.reminders.beforeOpenMinutes, 10);
    expect(port.starts, 0, reason: 'saving does not start monitoring');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow dirty draft can be saved with keyboard while scrolled', (
    tester,
  ) async {
    size(tester, const Size(520, 760));
    final key = GlobalKey(), port = Port();
    await tester.pumpWidget(
      app(
        RepaintBoundary(
          key: key,
          child: ExecHangarPage(port: port),
        ),
        const Locale('en', 'US'),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await pickExecPreset(tester, execBeforeClose, 15);
    expect(find.byKey(const Key('exec-save')).hitTestable(), findsOneWidget);
    await captureHangar(tester, key, 'exec-hangar-narrow-dirty');
    bool saveFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilledButton>()
            ?.key ==
        const Key('exec-save');
    for (var i = 0; i < 20 && !saveFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(
      saveFocused(),
      true,
      reason: 'fixed save actions remain in keyboard traversal',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(port.saves, 1);
    expect(port.snapshot.reminders.beforeCloseMinutes, 15);
    expect(port.starts, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'preset minutes, protected draft, persisted only after Save',
    (tester) async {
      size(tester, const Size(1440, 1100));
      final port = Port();
      final feature = createToolsFeatures(createPort: () => port).last;
      late BuildContext pageContext;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              pageContext = context;
              return feature.buildDestination(context);
            },
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('exec-on-close')));
      await tester.tap(find.byKey(const Key('exec-on-close')));
      await tester.pumpAndSettle();
      expect(port.saves, 0);
      // Lead minutes are presets now, so only the dirty draft is guarded.
      final leave = feature.confirmLeave!(pageContext);
      await tester.pumpAndSettle();
      expect(find.text('提醒设置尚未保存'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(await leave, false);
      await pickExecPreset(tester, execBeforeOpen, 10);
      await tester.ensureVisible(find.byKey(const Key('exec-save')));
      await tester.tap(find.byKey(const Key('exec-save')));
      await tester.pumpAndSettle();
      expect(port.saves, 1);
      expect(port.snapshot.reminders.onClose, true);
      expect(port.snapshot.reminders.beforeOpenMinutes, 10);
      expect(await feature.confirmLeave!(pageContext), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'stale offline calibration remains visible and explicitly pauses reminders',
    (tester) async {
      final port = Port()
        ..snapshot = sample(reliable: false, refreshFailed: true);
      await tester.pumpWidget(
        app(
          ExecHangarPage(port: port),
          const Locale('zh', 'CN'),
          AppearanceMode.light,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('提醒已暂停'), findsOneWidget);
      expect(find.textContaining('最近一次成功获取'), findsOneWidget);
      expect(find.byKey(const Key('exec-countdown')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('a refresh cannot silently rebase an unsaved reminder draft', (
    tester,
  ) async {
    size(tester, const Size(1440, 1100));
    final port = Port();
    await tester.pumpWidget(
      app(
        ExecHangarPage(port: port),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('exec-on-close')));
    await tester.tap(find.byKey(const Key('exec-on-close')));
    await tester.pumpAndSettle();
    port.snapshot = sample(revision: 2);
    await tester.ensureVisible(find.byKey(const Key('exec-refresh')));
    await tester.tap(find.byKey(const Key('exec-refresh')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('exec-save'))).onPressed,
      isNull,
    );
    expect(find.text('提醒设置已更新。点「撤销修改」载入最新设置，再重新编辑。'), findsOneWidget);
    expect(port.saves, 0);
    await tester.ensureVisible(find.text('撤销修改'));
    await tester.tap(find.text('撤销修改'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('exec-on-close')));
    await tester.tap(find.byKey(const Key('exec-on-close')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('exec-save')));
    await tester.tap(find.byKey(const Key('exec-save')));
    await tester.pumpAndSettle();
    expect(port.snapshot.revision, 3);
    expect(port.snapshot.reminders.onClose, true);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'bridge snapshot rejects malformed boundaries and out-of-range settings',
    () {
      Map<String, Object?> body() => {
        'schemaVersion': 1,
        'revision': 0,
        'reminders': const ExecHangarReminders().wire,
        'config': null,
        'fetchedAt': null,
        'now': origin.toIso8601String(),
        'reliable': false,
        'refreshFailed': false,
        'deliveryState': 'idle',
        'phases': <Object>[],
        'windows': <Object>[],
      };
      expect(BridgeExecHangar.parse(body()).version, null);
      for (final state in [
        'doNotDisturb',
        'fullScreen',
        'inactiveDesktop',
        'quietTime',
        'systemBusy',
        'queueFull',
        'expired',
        'environmentUnknown',
        'desktopUnavailable',
      ]) {
        expect(
          BridgeExecHangar.parse(body()..['deliveryState'] = state)
              .deliveryState,
          state,
        );
      }
      expect(
        () => BridgeExecHangar.parse(
          body()..['deliveryState'] = 'unknown-reason',
        ),
        throwsException,
      );
      expect(
        () => BridgeExecHangar.parse(body()..['reliable'] = true),
        throwsException,
      );
      expect(
        () => BridgeExecHangar.parse(
          body()
            ..['reminders'] = {
              ...const ExecHangarReminders().wire,
              'beforeOpenMinutes': 121,
            },
        ),
        throwsException,
      );
      expect(
        () => BridgeExecHangar.parse(
          body()
            ..['phases'] = [
              {
                'start': origin.toIso8601String(),
                'end': origin.toIso8601String(),
                'open': true,
                'greenLights': 5,
                'redLights': 1,
              },
            ],
        ),
        throwsException,
      );
    },
  );
}
