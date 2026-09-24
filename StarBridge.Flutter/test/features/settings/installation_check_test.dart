import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_port.dart';
import 'package:starbridge_flutter/features/settings/installation_check_dialog.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    _Port port, {
    Locale locale = const Locale('zh', 'CN'),
    AppearanceMode mode = AppearanceMode.dark,
  }) async {
    final module = createApplicationSupportModule(port);
    addTearDown(module.dispose);
    final tokens = StyleRegistry()
        .resolve(AppPreferences.defaults.designStyleId, mode)
        .tokens;
    await tester.pumpWidget(
      MaterialApp(
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInstallationCheckDialog(context, module),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> scan(WidgetTester tester) async {
    final button = find.byKey(const Key('installation-check-scan'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  for (final detail in ['portable', 'installed', 'unknown-future-detail']) {
    testWidgets('recognizes $detail without leaking protocol labels', (
      tester,
    ) async {
      final port = _Port()
        ..check = _check(ApplicationSupportCheckState.healthy, detail);
      await mount(tester, port);
      await scan(tester);
      expect(find.text('正常'), findsOneWidget);
      expect(find.textContaining('detail.'), findsNothing);
      expect(find.textContaining('unknown-future-detail'), findsNothing);
      expect(
        find.textContaining(
          detail == 'portable'
              ? '便携运行'
              : detail == 'installed'
              ? '正式安装状态正常'
              : '无法读取',
        ),
        findsOneWidget,
      );
    });
  }
  testWidgets('failed refresh clears prior result', (tester) async {
    final port = _Port();
    await mount(tester, port);
    await scan(tester);
    expect(find.text('当前安装记录：1'), findsOneWidget);
    port.failure = ApplicationSupportFailure.timeout;
    await scan(tester);
    expect(find.textContaining('当前安装记录：'), findsNothing);
    expect(find.text('检查等待超时，请重试。'), findsOneWidget);
  });

  testWidgets('opening does not inspect; maintenance actions remain disabled', (
    tester,
  ) async {
    final port = _Port();
    await mount(tester, port);
    expect(port.calls, 0);
    for (final key in ['repair', 'uninstall', 'clean']) {
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(Key('installation-check-$key')))
            .onPressed,
        isNull,
      );
    }
    await scan(tester);
    expect(port.calls, 1);
    expect(find.text('当前安装记录：1'), findsOneWidget);
    expect(find.text('其他安装：2'), findsOneWidget);
    expect(find.text('失效记录：3'), findsOneWidget);
    expect(find.text('未完成检查：0'), findsOneWidget);
    expect(port.opens, 0);
  });

  testWidgets('unavailable scan never displays zero as a known count', (
    tester,
  ) async {
    final port = _Port()
      ..check = _check(
        ApplicationSupportCheckState.unavailable,
        'scanPartial',
        warnings: 1,
      );
    await mount(tester, port);
    await scan(tester);
    expect(find.textContaining('以下数量可能不完整'), findsOneWidget);
    expect(find.textContaining('当前安装记录：'), findsNothing);
    expect(find.text('暂时无法检查'), findsOneWidget);
  });

  testWidgets('partial scan retains observed counts with warning', (
    tester,
  ) async {
    final port = _Port()
      ..check = _check(
        ApplicationSupportCheckState.actionRequired,
        'duplicateInstallations',
        warnings: 2,
      );
    await mount(tester, port);
    await scan(tester);
    expect(find.textContaining('以下数量可能不完整'), findsOneWidget);
    expect(find.text('其他安装：2'), findsOneWidget);
    expect(find.text('未完成检查：2'), findsOneWidget);
  });

  for (final failure in ApplicationSupportFailure.values) {
    testWidgets('failure $failure can retry without retaining old counts', (
      tester,
    ) async {
      final port = _Port()..failure = failure;
      await mount(tester, port);
      await scan(tester);
      expect(find.textContaining('当前安装记录：'), findsNothing);
      port.failure = null;
      await scan(tester);
      expect(find.text('当前安装记录：1'), findsOneWidget);
      expect(port.calls, 2);
    });
  }

  testWidgets(
    'pending check blocks repeats and close does not dispose shared module',
    (tester) async {
      final port = _Port()..pending = Completer<ApplicationSupportSnapshot>();
      await mount(tester, port);
      await scan(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('installation-check-scan')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(port.closed, false);
      port.pending!.complete(_snapshot(port.check));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(port.calls, 1);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前安装记录：'), findsNothing);
      expect(port.calls, 1);
    },
  );

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('small window $locale $mode scrolls without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, _Port(), locale: locale, mode: mode);
        await scan(tester);
        await tester.ensureVisible(
          find.byKey(const Key('installation-check-clean')),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

ApplicationInstallationCheck _check(
  ApplicationSupportCheckState state,
  String detail, {
  int warnings = 0,
}) => ApplicationInstallationCheck(
  state: state,
  detail: detail,
  mode: 'ambiguous',
  currentInstallations: 1,
  otherInstallations: 2,
  orphanedRegistrations: 3,
  scanWarnings: warnings,
);

ApplicationSupportSnapshot _snapshot(ApplicationInstallationCheck check) =>
    ApplicationSupportSnapshot(
      hasIssues: true,
      hasUnavailableChecks: false,
      dataDirectory: const ApplicationSupportCheck(
        state: ApplicationSupportCheckState.healthy,
        detail: 'writable',
      ),
      gameLog: const ApplicationSupportCheck(
        state: ApplicationSupportCheckState.healthy,
        detail: 'readable',
      ),
      startup: const ApplicationStartupCheck(
        state: ApplicationSupportCheckState.healthy,
        detail: 'notEnabled',
        registered: false,
        targetExists: null,
        targetsCurrentExecutable: null,
      ),
      installation: check,
    );

class _Port implements ApplicationSupportPort {
  int calls = 0;
  int opens = 0;
  bool closed = false;
  ApplicationSupportFailure? failure;
  Completer<ApplicationSupportSnapshot>? pending;
  ApplicationInstallationCheck check = _check(
    ApplicationSupportCheckState.actionRequired,
    'duplicateInstallations',
  );
  @override
  Future<ApplicationSupportSnapshot> inspect() async {
    calls++;
    if (failure case final value?) throw ApplicationSupportException(value);
    return pending == null ? _snapshot(check) : await pending!.future;
  }

  @override
  Future<void> openDataDirectory() async {
    opens++;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
