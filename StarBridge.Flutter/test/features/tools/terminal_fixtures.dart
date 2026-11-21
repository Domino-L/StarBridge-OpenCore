import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/tools/cached_exec_hangar.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_port.dart';
import 'package:starbridge_flutter/features/tools/tools_snapshot_cache.dart';

import 'catalog_samples.dart';

Widget terminalApp(
  Widget child, {
  bool light = false,
  Locale locale = const Locale('zh', 'CN'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(
      light ? AppearanceMode.light : AppearanceMode.dark,
    ),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

class TerminalHangarPort implements ExecHangarPort {
  final now = DateTime.utc(2026, 11, 9, 10);
  ExecHangarSnapshot get snapshot => ExecHangarSnapshot(
    revision: 1,
    reminders: const ExecHangarReminders(enabled: true),
    now: now,
    reliable: true,
    refreshFailed: false,
    deliveryState: 'ready',
    phases: [
      ExecHangarPhase(
        now.subtract(const Duration(minutes: 1)),
        now.add(const Duration(minutes: 10)),
        true,
        3,
        1,
      ),
    ],
    windows: [
      ExecHangarWindow(
        now.subtract(const Duration(minutes: 1)),
        now.add(const Duration(minutes: 10)),
      ),
    ],
  );
  @override
  Future<ExecHangarSnapshot> read({bool refresh = false}) async => snapshot;
  @override
  Future<ExecHangarSnapshot> save(
    ExecHangarReminders reminders,
    int revision,
  ) async => snapshot;
  @override
  Future<ExecHangarSnapshot> monitor(
    ExecHangarAction action,
    int revision, {
    int durationMinutes = 60,
    bool onlyNext = false,
  }) async => snapshot;
}

Future<CachedExecHangar> terminalHangar() async {
  final cache = CachedExecHangar(
    TerminalHangarPort(),
    elapsed: () => Duration.zero,
  );
  await cache.read();
  return cache;
}

ToolsSnapshotCache terminalCache() => ToolsSnapshotCache()
  ..accept(
    'blueprints.page',
    {'keyword': '', 'pageNo': 1},
    {
      'rows': [blueprintSample],
      'total': 1,
    },
    false,
  )
  ..accept('missions.detail', {}, missionSample, false)
  ..acceptKeys(
    const KeyBindingsSnapshot(
      state: 'ok',
      channel: 'LIVE',
      maps: [
        KeyBindingMap('player', [
          KeyBindingAction('sample', [
            KeyBindingEntry(
              device: 'keyboardMouse',
              instance: 1,
              input: 'w',
              customized: false,
            ),
            KeyBindingEntry(
              device: 'keyboardMouse',
              instance: 1,
              input: 'mouse1',
              customized: false,
            ),
            KeyBindingEntry(
              device: 'gamepad',
              instance: 1,
              input: 'button1',
              customized: false,
            ),
            KeyBindingEntry(
              device: 'keyboardMouse',
              instance: 1,
              input: '',
              customized: true,
            ),
          ]),
        ]),
      ],
    ),
  );
