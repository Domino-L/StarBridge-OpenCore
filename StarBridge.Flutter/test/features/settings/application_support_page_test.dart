import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_page.dart';
import 'package:starbridge_flutter/features/settings/application_support_port.dart';
import 'package:starbridge_flutter/features/settings/diagnostics_settings_page.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart'
    as history;
import 'package:starbridge_flutter/features/settings/runtime_status_controller.dart';

import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [390.0, 1100.0]) {
    testWidgets('diagnostics full page layout $width', (tester) async {
      tester.view.physicalSize = Size(width, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadFonts();
      final module = createApplicationSupportModule(_ApplicationSupportPort());
      addTearDown(module.dispose);
      final capture = GlobalKey();
      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: capture,
            child: DiagnosticsSettingsPage(
              support: module,
              historyPort: _ReviewHistory(),
              createRuntime: () => RuntimeStatusController(
                readInstallation: () async => const RuntimeInstallationFacts(
                  dataDirectory: r'C:\Example\StarBridge',
                  imageCacheDirectory: r'C:\Example\StarBridge\Images',
                  imageCacheExists: true,
                  applicationVersion: '1.0.0',
                ),
                readOverlay: () async => const RuntimeOverlayFacts(
                  windowState: 'closed',
                  hotkeyBinding: 'Alt+O',
                  hotkeyState: 'registered',
                  presetName: '默认预设',
                ),
                readStartup: () async => const RuntimeStartupFacts(
                  launchAtStartup: true,
                  startMinimized: false,
                  keepRunningInBackground: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('diagnostics-run')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width == 1100) {
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('build/diagnostics-review')
            ..createSync(recursive: true);
          await File('${folder.path}/page.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'diagnostics page embeds history and runs checks only on request',
    (tester) async {
      final port = _ApplicationSupportPort();
      final module = createApplicationSupportModule(port);
      addTearDown(module.dispose);
      await tester.pumpWidget(_app(DiagnosticsSettingsPage(support: module)));
      await tester.pumpAndSettle();
      expect(port.inspectCount, 0);
      expect(find.byKey(const Key('history-close')), findsNothing);
      await tester.tap(find.byKey(const Key('diagnostics-run')));
      await tester.pumpAndSettle();
      expect(port.inspectCount, 1);
      expect(
        find.byKey(const Key('application-support-ready')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open directory blocks repeated clicks while the Host is pending',
    (tester) async {
      final port = _ApplicationSupportPort()..pendingOpen = Completer<void>();
      final module = createApplicationSupportModule(port);
      addTearDown(module.dispose);
      await tester.pumpWidget(_app(ApplicationSupportPage(module: module)));
      await tester.pumpAndSettle();
      final button = find.byKey(
        const Key('application-support-open-data-directory'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      expect(port.openCount, 1);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      port.pendingOpen!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clipboard failure remains actionable without an unhandled exception',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'unavailable');
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
      final module = createApplicationSupportModule(_ApplicationSupportPort());
      addTearDown(module.dispose);
      await tester.pumpWidget(_app(ApplicationSupportPage(module: module)));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('application-support-copy'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('未能复制，请重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders all checks without overflowing at 390 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = createApplicationSupportModule(_ApplicationSupportPort());
    addTearDown(module.dispose);

    await tester.pumpWidget(_app(ApplicationSupportPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.text('诊断与维护'), findsOneWidget);
    expect(
      find.byKey(const Key('application-support-data-directory')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('application-support-game-log')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('application-support-startup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('application-support-installation')),
      findsOneWidget,
    );
    expect(find.textContaining('地点代码'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copies only the safe user-facing summary', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
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
    final module = createApplicationSupportModule(_ApplicationSupportPort());
    addTearDown(module.dispose);

    await tester.pumpWidget(_app(ApplicationSupportPage(module: module)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('application-support-copy')),
    );
    await tester.tap(find.byKey(const Key('application-support-copy')));
    await tester.pumpAndSettle();

    expect(copied, contains('本地数据：正常'));
    expect(copied, contains('安装状态：需要处理'));
    expect(copied, isNot(contains(r'C:\')));
    expect(copied, isNot(contains('token')));
    expect(copied, isNot(contains('subject')));
    expect(find.text('诊断摘要已复制'), findsOneWidget);
  });

  testWidgets('opens the Host-owned data directory from the ready page', (
    tester,
  ) async {
    final port = _ApplicationSupportPort();
    final module = createApplicationSupportModule(port);
    addTearDown(module.dispose);

    await tester.pumpWidget(_app(ApplicationSupportPage(module: module)));
    await tester.pumpAndSettle();
    final open = find.byKey(
      const Key('application-support-open-data-directory'),
    );
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();

    expect(port.openCount, 1);
    expect(find.text('已打开数据目录'), findsOneWidget);
  });
}

class _ReviewHistory implements history.LocalHistoryPort {
  @override
  Future<history.LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async => history.LocalHistoryPage(
    state: 'ready',
    totalCount: 5,
    filteredCount: 5,
    offset: 0,
    pageSize: 50,
    hasMore: false,
    revision: 'A' * 64,
    entries: [
      for (final row in [
        ('session', '检测到 Star Citizen 启动'),
        ('server', '已连接游戏服务器'),
        ('ship', '当前舰船已更新'),
        ('location', '已确认当前位置'),
        ('life', '检测到生命状态变化'),
      ])
        history.LocalHistoryEntry(
          id: row.$1,
          at: DateTime(2026, 9, 15, 12, 30),
          category: row.$1,
          eventType: row.$1,
          title: row.$2,
          detail: '本机识别事件 · 示例记录',
        ),
    ],
  );
}

Widget _app(Widget home) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
    home: Scaffold(body: home),
  );
}

final class _ApplicationSupportPort implements ApplicationSupportPort {
  int openCount = 0;
  int inspectCount = 0;
  Completer<void>? pendingOpen;

  @override
  Future<ApplicationSupportSnapshot> inspect() async {
    inspectCount++;
    return _snapshot;
  }

  @override
  Future<void> openDataDirectory() async {
    openCount++;
    await pendingOpen?.future;
  }

  @override
  Future<void> close() async {}
}

const _snapshot = ApplicationSupportSnapshot(
  hasIssues: true,
  hasUnavailableChecks: false,
  dataDirectory: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'writable',
  ),
  gameLog: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.actionRequired,
    detail: 'fileMissing',
  ),
  startup: ApplicationStartupCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'notEnabled',
    registered: false,
    targetExists: null,
    targetsCurrentExecutable: null,
  ),
  installation: ApplicationInstallationCheck(
    state: ApplicationSupportCheckState.actionRequired,
    detail: 'duplicateInstallations',
    mode: 'installed',
    currentInstallations: 1,
    otherInstallations: 1,
    orphanedRegistrations: 0,
    scanWarnings: 0,
  ),
);
