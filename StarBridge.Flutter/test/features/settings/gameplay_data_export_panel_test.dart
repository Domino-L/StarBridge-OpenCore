import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_panel.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_port.dart';

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('export is explicit and fits 390px $locale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _Port();
      await tester.pumpWidget(_app(port, locale));
      await tester.pumpAndSettle();
      expect(port.calls, 0);
      await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
      await tester.pumpAndSettle();
      expect(port.calls, 1);
      expect(
        port.locale,
        locale.languageCode == 'en'
            ? 'en'
            : locale.countryCode == 'TW'
            ? 'zh-TW'
            : 'zh-CN',
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('pending button is disabled and closing cancels', (tester) async {
    final port = _Port()..pending = Completer<GameplayExportOutcome>();
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('gameplay-data-export-start')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    expect(port.cancels, 1);
    port.pending!.complete(GameplayExportOutcome.saved);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancelled result is not success', (tester) async {
    final port = _Port()..result = GameplayExportOutcome.cancelled;
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
    await tester.pumpAndSettle();
    expect(find.text('已取消导出。'), findsOneWidget);
    expect(find.text('游玩数据已导出。'), findsNothing);
  });
  testWidgets('old account result is discarded on port replacement', (
    tester,
  ) async {
    final old = _Port()..pending = Completer<GameplayExportOutcome>();
    await tester.pumpWidget(_app(old));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
    await tester.pump();
    await tester.pumpWidget(_app(_Port()));
    old.pending!.complete(GameplayExportOutcome.saved);
    await tester.pumpAndSettle();
    expect(old.cancels, 1);
    expect(find.text('游玩数据已导出。'), findsNothing);
  });
  testWidgets('unknown result suggests checking the destination, not success', (
    tester,
  ) async {
    final port = _Port()..result = GameplayExportOutcome.unknown;
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
    await tester.pumpAndSettle();
    expect(find.text('未能确认导出结果，请检查所选文件夹。'), findsOneWidget);
  });
}

Widget _app(
  GameplayDataExportPort port, [
  Locale locale = const Locale('zh', 'CN'),
]) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
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
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GameplayDataExportPanel(port: port),
      ),
    ),
  );
}

final class _Port implements GameplayDataExportPort {
  int calls = 0;
  int cancels = 0;
  String? locale;
  GameplayExportOutcome result = GameplayExportOutcome.saved;
  Completer<GameplayExportOutcome>? pending;
  @override
  Future<GameplayExportOutcome> export(String locale) async {
    calls++;
    this.locale = locale;
    return pending?.future ?? result;
  }

  @override
  void cancel() {
    cancels++;
  }
}
