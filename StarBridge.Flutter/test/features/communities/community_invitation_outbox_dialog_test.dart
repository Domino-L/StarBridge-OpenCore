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
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_outbox_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';

import 'community_invitation_send_controller_test.dart'
    show InvitationSendTestPort;
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> open(
  WidgetTester tester,
  InvitationSendTestPort port, {
  Size size = const Size(1000, 720),
  Locale locale = const Locale('zh', 'CN'),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('outbox-capture'),
                child: CommunityInvitationOutboxDialog(port: port),
              ),
            ),
            child: const Text('Open'),
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
  final id = 'a' * 32;
  late InvitationSendTestPort port;
  CommunityInvitationOperation row(String phase, {String? operationId}) =>
      CommunityInvitationOperation(
        operationId ?? id,
        'private',
        phase,
        '测试组织 · 探索同行',
        '测试接收方',
        DateTime.utc(2026, 9, 8, 10),
        1,
      );
  setUpAll(loadFonts);
  setUp(() => port = InvitationSendTestPort());
  tearDown(() => port.events.close());
  testWidgets('empty page does not generate or send anything', (tester) async {
    await open(tester, port);
    expect(find.text('暂无邀请发送记录。'), findsOneWidget);
    expect(port.calls, ['read']);
    await tester.tap(find.text('刷新记录'));
    await tester.pumpAndSettle();
    expect(port.calls, ['read', 'read']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('actions stay in record; retry is explicit and cancellable', (
    tester,
  ) async {
    port.items = [row('sending')];
    await open(tester, port);
    expect(find.text('测试组织 · 探索同行'), findsOneWidget);
    await tester.tap(find.text('重试原邀请'));
    await tester.pumpAndSettle();
    expect(find.text('重试这条邀请？'), findsOneWidget);
    expect(port.calls, ['read']);
    await tester.tap(find.text('暂不重试'));
    await tester.pumpAndSettle();
    expect(port.calls, ['read']);
    await tester.tap(find.text('重试原邀请'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '重试原邀请'));
    await tester.pumpAndSettle();
    expect(port.calls, ['read', 'retryDelivery:$id', 'read']);
  });
  testWidgets(
    'checking result is read-only and sent record has no send action',
    (tester) async {
      port.items = [row('sending')];
      port.status = 'sent';
      await open(tester, port);
      await tester.tap(find.text('查看发送结果'));
      await tester.pumpAndSettle();
      expect(port.calls, ['read', 'check:$id', 'read']);
      expect(find.text('重试原邀请'), findsNothing);
      expect(find.text('已发送'), findsWidgets);
    },
  );
  testWidgets(
    'account change clears names and disables open retry confirmation',
    (tester) async {
      port.items = [row('sending')];
      await open(tester, port);
      await tester.tap(find.text('重试原邀请'));
      await tester.pumpAndSettle();
      port.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('测试组织 · 探索同行'), findsNothing);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '重试原邀请'),
      );
      expect(button.onPressed, isNull);
      expect(port.calls, ['read']);
    },
  );
  testWidgets('storage failure is not shown as an empty outbox', (
    tester,
  ) async {
    port.readError = const CommunityFailure('localRecoveryUnavailable');
    await open(tester, port);
    expect(find.textContaining('无法读取或保存本机发送记录'), findsOneWidget);
    expect(find.text('暂无邀请发送记录。'), findsNothing);
    expect(find.text('继续发送'), findsNothing);
  });
  testWidgets('narrow English large text remains usable', (tester) async {
    port.items = [row('sending')];
    await open(
      tester,
      port,
      size: const Size(440, 760),
      locale: const Locale('en'),
      scale: 1.3,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Check delivery'));
    await tester.tap(find.text('Check delivery'));
    await tester.pumpAndSettle();
    expect(port.calls, ['read', 'check:$id', 'read']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('real themed card screenshot renders', (tester) async {
    port.items = [row('sending'), row('sent', operationId: 'b' * 32)];
    await open(tester, port);
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('outbox-capture')),
    );
    await tester.runAsync(() async {
      final capture = await boundary.toImage();
      final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/test-output/community-invitation-outbox.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      capture.dispose();
    });
  });
}
