import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/legacy_profile_migration.dart';
import 'package:starbridge_flutter/features/account/legacy_profile_migration_card.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';

void main() {
  testWidgets(
    'preview is manual, both consents gate replacement, retry keeps the same ticket',
    (tester) async {
      final port = _Port();
      await _pump(tester, port);
      expect(port.previews, 0);
      expect(port.confirmations, isEmpty);
      await tester.tap(find.byKey(const Key('migration-preview')));
      await tester.pumpAndSettle();
      expect(port.previews, 0);
      await tester.enterText(
        find.byKey(const Key('account-legacy-name')),
        'synthetic-old',
      );
      await tester.enterText(
        find.byKey(const Key('account-legacy-password')),
        'synthetic-only',
      );
      await tester.tap(find.byKey(const Key('account-legacy-submit')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('migration-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const Key('migration-owner')));
      await tester.tap(find.byKey(const Key('migration-owner')));
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const Key('migration-replace')));
      await tester.tap(find.byKey(const Key('migration-replace')));
      await tester.pump();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(port.confirmations, ['synthetic-preview:true']);
      port.pending.complete(
        const LegacyProfileMigrationView('sourceUnavailable'),
      );
      await tester.pumpAndSettle();
      port.pending = Completer<LegacyProfileMigrationView>();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(port.confirmations, [
        'synthetic-preview:true',
        'synthetic-preview:true',
      ]);
      port.pending.complete(const LegacyProfileMigrationView('completed'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('migration-confirm')), findsNothing);
      expect(find.textContaining('个人主页和游戏统计已迁移'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reopening a completed migration never requests another import', (
    tester,
  ) async {
    final port = _Port()..initialState = 'completed';
    await _pump(tester, port);
    expect(find.text('个人资料已迁入当前账号，之后直接使用当前账号即可。'), findsOneWidget);
    expect(find.textContaining('旧组织将迁为社区组织'), findsOneWidget);
    expect(find.byKey(const Key('migration-preview')), findsNothing);
    expect(find.byKey(const Key('migration-confirm')), findsNothing);
    expect(find.byKey(const Key('account-legacy-password')), findsNothing);
    expect(port.previews, 0);
    expect(port.confirmations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual verification works without the legacy compatibility service',
    (tester) async {
      final port = _Port()..initialState = 'credentialRequired';
      await _pump(tester, port);
      await tester.tap(find.byKey(const Key('migration-preview')));
      await tester.pumpAndSettle();
      expect(find.text('验证旧账号'), findsOneWidget);
      expect(port.previews, 0);
      await tester.tap(find.byKey(const Key('account-legacy-dialog-close')));
      await tester.pumpAndSettle();
      expect(port.previews, 0);
      await tester.tap(find.byKey(const Key('migration-preview')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-legacy-name')),
        'synthetic-old',
      );
      await tester.enterText(
        find.byKey(const Key('account-legacy-password')),
        'synthetic-only',
      );
      await tester.tap(find.byKey(const Key('account-legacy-submit')));
      await tester.pumpAndSettle();
      expect(port.previews, 1);
      expect(find.byKey(const Key('account-legacy-password')), findsNothing);
      expect(port.confirmations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in {
    'sourceUnavailable': '暂时无法读取旧资料，请稍后重试。',
    'credentialRejected': '账号或密码不正确，请重新输入。',
  }.entries) {
    testWidgets(
      'verification shows pending feedback and a retry after ${outcome.key}',
      (tester) async {
        final response = Completer<LegacyProfileMigrationView>();
        final port = _Port()
          ..initialState = 'credentialRequired'
          ..pendingPreview = response;
        await _pump(tester, port);
        await tester.tap(find.byKey(const Key('migration-preview')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('account-legacy-name')),
          'synthetic-old',
        );
        await tester.enterText(
          find.byKey(const Key('account-legacy-password')),
          'synthetic-only',
        );
        await tester.tap(find.byKey(const Key('account-legacy-submit')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(port.previews, 1);
        expect(find.byKey(const Key('account-legacy-password')), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('正在验证并读取旧资料…'), findsOneWidget);
        expect(find.byKey(const Key('migration-preview')), findsNothing);
        expect(find.byKey(const Key('migration-confirm')), findsNothing);
        expect(port.confirmations, isEmpty);

        response.complete(LegacyProfileMigrationView(outcome.key));
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text(outcome.value), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('migration-preview')))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const Key('migration-preview')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const Key('account-legacy-password')),
              )
              .controller!
              .text,
          isEmpty,
        );
        await tester.tap(find.byKey(const Key('account-legacy-dialog-close')));
        await tester.pumpAndSettle();
        expect(port.previews, 1);
        expect(port.confirmations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unavailable migration cannot send a preview request', (
    tester,
  ) async {
    final port = _Port()..initialState = 'sourceNotConfigured';
    await _pump(tester, port);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('migration-preview')))
          .onPressed,
      isNull,
    );
    expect(find.text('资料迁移暂未开放。'), findsOneWidget);
    expect(port.previews, 0);
  });

  test('incomplete or unknown migration previews fail closed', () {
    expect(
      () => LegacyProfileMigrationView.fromJson({'state': 'previewed'}),
      throwsFormatException,
    );
    expect(
      () => LegacyProfileMigrationView.fromJson({'state': 'pretendSuccess'}),
      throwsFormatException,
    );
  });
}

Future<void> _pump(WidgetTester tester, _Port port) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LegacyProfileMigrationCard(port: port),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Port implements LegacyProfileMigrationPort {
  String initialState = 'notStarted';
  int previews = 0;
  final confirmations = <String>[];
  Completer<LegacyProfileMigrationView> pending = Completer();
  Completer<LegacyProfileMigrationView>? pendingPreview;
  @override
  Future<LegacyProfileMigrationView> migrationStatus() async =>
      LegacyProfileMigrationView(initialState);
  @override
  Future<LegacyProfileMigrationView> previewMigration({
    LegacyAccountCredential? credential,
  }) async {
    expect(credential?.accountName, 'synthetic-old');
    expect(credential?.password, 'synthetic-only');
    previews++;
    if (pendingPreview != null) return pendingPreview!.future;
    return LegacyProfileMigrationView(
      'previewed',
      previewId: 'synthetic-preview',
      sourceGameId: 'Synthetic-Handle',
      conflict: true,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      source: const LegacyProfileMigrationSummary(
        callSign: '旧呼号',
        introduction: '旧简介',
        modules: 3,
        favorites: 2,
        playTimeSeconds: 7200,
      ),
      target: const LegacyProfileMigrationSummary(
        callSign: '新呼号',
        introduction: '新简介',
        modules: 1,
        favorites: 0,
        playTimeSeconds: 3600,
      ),
    );
  }

  @override
  Future<LegacyProfileMigrationView> confirmMigration(
    String previewId, {
    required bool replaceExisting,
  }) {
    confirmations.add('$previewId:$replaceExisting');
    return pending.future;
  }
}
