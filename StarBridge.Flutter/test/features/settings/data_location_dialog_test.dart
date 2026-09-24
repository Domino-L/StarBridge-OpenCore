import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/data_location_dialog.dart';
import 'package:starbridge_flutter/features/settings/data_location_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

void main() {
  testWidgets('failed location read recovers without a manual refresh', (
    tester,
  ) async {
    final port = _Port()..failRead = true;
    await tester.pumpWidget(_app(DataLocationDialog(port: port)));
    await tester.pumpAndSettle();
    expect(find.textContaining('正在自动重试'), findsOneWidget);
    port.failRead = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(port.location.path), findsOneWidget);
    expect(find.text('重新读取'), findsNothing);
    expect(port.openCount, 0);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('long path fits 390px $locale $mode', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = _Port();
        await tester.pumpWidget(
          _app(DataLocationDialog(port: port), locale, mode),
        );
        await tester.pumpAndSettle();
        expect(find.text(port.location.path), findsOneWidget);
        expect(tester.takeException(), isNull);
        final move = tester.widget<OutlinedButton>(
          find.byKey(const Key('data-location-move')),
        );
        expect(move.onPressed, isNull);
        expect(port.openCount, 0);
      });
    }
  }

  testWidgets('copy uses exact path and never opens the folder', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final port = _Port();
    await tester.pumpWidget(_app(DataLocationDialog(port: port)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('data-location-copy')));
    await tester.pumpAndSettle();
    expect(copied, port.location.path);
    expect(port.openCount, 0);
    expect(find.text('路径已复制'), findsOneWidget);
  });

  testWidgets('missing folder can be copied but not opened', (tester) async {
    final port = _Port()
      ..location = const DataLocation(path: r'G:\missing', exists: false);
    await tester.pumpWidget(_app(DataLocationDialog(port: port)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('data-location-open')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('data-location-copy')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('open coalesces clicks and reports failure without raw details', (
    tester,
  ) async {
    final port = _Port()..opening = Completer<void>();
    await tester.pumpWidget(_app(DataLocationDialog(port: port)));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('data-location-open'));
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(port.openCount, 1);
    port.opening!.completeError(StateError('private file details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法打开文件夹'), findsOneWidget);
    expect(find.textContaining('private file'), findsNothing);
  });

  testWidgets('failed read can retry without creating default data', (
    tester,
  ) async {
    final port = _Port()..failRead = true;
    await tester.pumpWidget(_app(DataLocationDialog(port: port)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('data-location-path')), findsNothing);
    port.failRead = false;
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(find.text(port.location.path), findsOneWidget);
    expect(port.openCount, 0);
  });

  testWidgets('discard old path when the connected port changes', (
    tester,
  ) async {
    final old = _Port()..reading = Completer<DataLocation>();
    await tester.pumpWidget(_app(DataLocationDialog(port: old)));
    final next = _Port()
      ..location = const DataLocation(path: r'G:\next', exists: true);
    await tester.pumpWidget(_app(DataLocationDialog(port: next)));
    await tester.pumpAndSettle();
    old.reading!.complete(old.location);
    await tester.pumpAndSettle();
    expect(find.text(r'G:\next'), findsOneWidget);
    expect(find.text(old.location.path), findsNothing);
  });

  for (final wpfRunning in [false, true]) {
    testWidgets('migration guarded exit identifies WPF occupancy $wpfRunning', (
      tester,
    ) async {
      final port = _MigrationPort();
      port.wpfRunning = wpfRunning;
      ExitApplicationIntent? intent;
      await tester.pumpWidget(
        _app(
          Actions(
            actions: {
              ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
                onInvoke: (value) {
                  intent = value;
                  return null;
                },
              ),
            },
            child: Builder(
              builder: (context) => FilledButton(
                key: const Key('show-data-location'),
                onPressed: () => showDataLocationDialog(context, port),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('show-data-location')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('data-location-move')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('data-location-move')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('data-location-confirm-dialog')),
        findsOneWidget,
      );
      expect(find.text(port.choice.source), findsOneWidget);
      expect(find.text(port.choice.destination), findsOneWidget);
      expect(port.confirmed, isEmpty);
      await tester.tap(find.byKey(const Key('data-location-confirm')));
      await tester.pumpAndSettle();
      expect(intent, isNotNull);
      expect(port.confirmed, isEmpty);
      expect(await intent!.beforeExit!(), !wpfRunning);
      await tester.pumpAndSettle();
      if (wpfRunning) {
        expect(find.textContaining('请先从托盘完全退出旧版星海舰桥'), findsOneWidget);
      }
      expect(port.confirmed, [port.choice.ticket]);
    });
  }
}

Widget _app(
  Widget home, [
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
]) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, mode)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(body: home),
  );
}

class _Port implements DataLocationPort {
  DataLocation location = DataLocation(
    path:
        'G:\\StarBridge\\${List.filled(12, 'long-directory').join('-')}\\data',
    exists: true,
  );
  bool failRead = false;
  int openCount = 0;
  Completer<void>? opening;
  Completer<DataLocation>? reading;
  @override
  Future<DataLocation> read() async {
    if (failRead) throw StateError('private detail');
    return reading?.future ?? location;
  }

  @override
  Future<void> open() async {
    openCount++;
    await opening?.future;
  }
}

final class _MigrationPort extends _Port implements DataLocationMigrationPort {
  bool wpfRunning = false;
  final choice = const DataLocationMigrationChoice(
    ticket: '0123456789abcdef0123456789abcdef',
    source: r'G:\StarBridge\data',
    destination: r'D:\StarBridge\data',
  );
  final List<String> confirmed = [];
  @override
  bool get migrationAvailable => true;
  @override
  Future<DataLocationMigrationChoice?> chooseMigration() async => choice;
  @override
  Future<void> confirmMigration(String ticket) async {
    confirmed.add(ticket);
    if (wpfRunning) {
      throw const BridgeRemoteException('dataLocation.wpf_running');
    }
  }
}
