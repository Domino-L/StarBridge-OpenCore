import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_logs_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_logs_port.dart';
import 'package:starbridge_flutter/features/communities/community_logs_copy.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_logs_test.dart';
import 'community_workspace_view_test.dart' show host;
import 'community_workspace_test.dart' show workspacePayload;
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> openLogs(
  WidgetTester tester,
  CommunityLogsPort port, {
  Locale locale = const Locale('zh', 'CN'),
  double width = 1000,
  String target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('logs-capture'),
                child: CommunityLogsDialog(port: port, targetRef: target),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  test(
    'workspace log access is explicit and absent legacy flags stay denied',
    () {
      final payload = workspacePayload();
      expect(CommunityWorkspace.parse(payload).access['canViewLogs'], false);
      (payload['access'] as Map)['canViewLogs'] = true;
      expect(CommunityWorkspace.parse(payload).access['canViewLogs'], true);
      payload['access'] = <String, Object?>{
        ...payload['access'] as Map<String, bool>,
        'canViewLogs': 'true',
      };
      expect(() => CommunityWorkspace.parse(payload), throwsFormatException);
    },
  );
  testWidgets('ordinary member workspace does not expose log entry', (
    tester,
  ) async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        port,
        const Locale('zh', 'CN'),
        target: '00000000000000000000000000000001',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('组织日志'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final (locale, width, index) in [
    (const Locale('zh', 'CN'), 420.0, 0),
    (const Locale('zh', 'TW'), 800.0, 1),
    (const Locale('en'), 1000.0, 2),
  ]) {
    testWidgets('logs and inline confirmation fit $locale at $width', (
      tester,
    ) async {
      final port = LogsFake();
      addTearDown(port.changes.close);
      await openLogs(tester, port, locale: locale, width: width);
      String copy(String key) {
        final v = communityLogsCopy[key]!;
        return [v.$1, v.$2, v.$3][index];
      }

      expect(find.text(copy('unknownTime')), findsOneWidget);
      expect(
        find.text(copy('repeated').replaceAll('{count}', '3')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(copy('delete')));
      await tester.pumpAndSettle();
      expect(find.text(copy('confirm')), findsOneWidget);
      expect(port.writes, 0);
      expect(find.text(copy('consequence')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(copy('keep')));
      await tester.pumpAndSettle();
      expect(port.writes, 0);
      await tester.tap(find.text(copy('delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(copy('delete')));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(find.text(copy('deleted')), findsOneWidget);
      expect(find.text(copy('empty')), findsOneWidget);
    });
  }
  testWidgets(
    'account invalidation removes selected private record and search',
    (tester) async {
      final port = LogsFake();
      addTearDown(port.changes.close);
      await openLogs(tester, port);
      await tester.enterText(find.byType(TextField), 'private search');
      await tester.tap(find.text('删除日志'));
      await tester.pumpAndSettle();
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Visible detail'), findsNothing);
      expect(find.text('Organization'), findsNothing);
      expect(find.text('private search'), findsNothing);
      expect(find.text('删除日志'), findsNothing);
      expect(port.writes, 0);
    },
  );
  testWidgets('unknown outcome offers reload and does not auto-delete', (
    tester,
  ) async {
    final port = LogsFake()
      ..outcome = const CommunityLogOutcome('unknown', error: 'outcomeUnknown');
    addTearDown(port.changes.close);
    await openLogs(tester, port);
    await tester.tap(find.text('删除日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除日志'));
    await tester.pumpAndSettle();
    expect(find.text(communityLogsCopy['outcomeUnknown']!.$1), findsOneWidget);
    expect(port.writes, 1);
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(port.writes, 1);
    expect(find.text('删除日志'), findsOneWidget);
  });
  testWidgets(
    'example workspace exposes authorized log entry and paged history',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = ExampleCommunities();
      addTearDown(port.close);
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          target: '00000000000000000000000000000002',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await tester.pumpAndSettle();
      expect(find.text('数据与日志'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-nav-logs')));
      await tester.pumpAndSettle();
      expect(find.text('1–20 / 26 条'), findsOneWidget);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('21–26 / 26 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('example logs preserve read-only permissions, filtering and consumed references', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    await expectLater(
      port.readLogs('00000000000000000000000000000001', 'All', '', 0),
      throwsA(isA<CommunityFailure>()),
    );
    final first = await port.readLogs(
      '00000000000000000000000000000002',
      'All',
      '',
      0,
    );
    expect(first.items.length, 20);
    expect(first.next, 20);
    final filtered = await port.readLogs(
      '00000000000000000000000000000002',
      '公告',
      '更新',
      0,
    );
    expect(filtered.items.length, 13);
    expect(filtered.items.every((e) => e.type == '公告'), isTrue);
    final id = first.items.first.logRef;
    expect(
      (await port.deleteLog('00000000000000000000000000000002', id)).status,
      'accepted',
    );
    expect(
      (await port.deleteLog('00000000000000000000000000000002', id)).status,
      'rejected',
    );
    expect(
      (await port.readLogs(
        '00000000000000000000000000000002',
        'All',
        '',
        0,
      )).items.first.title,
      '示例 · 删除日志记录',
    );
  });
  testWidgets('render actual log widgets for visual review', (tester) async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    await openLogs(tester, port, target: '00000000000000000000000000000002');
    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text('示例 · 成员加入').first);
    expect(title.style?.fontFamilyFallback, contains('Source Han Sans CN'));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('logs-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('build/community-logs.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  });
}
