import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:starbridge_flutter/features/account/legacy_password_login.dart';
import 'package:starbridge_flutter/features/account/legacy_profile_migration.dart';
import 'package:starbridge_flutter/features/account/legacy_profile_migration_card.dart';
import 'package:starbridge_flutter/features/account/account_compatibility_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/brand/scm_brand_mark.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/styles/probe_style.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/password_recovery.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  testWidgets(
    'compatibility remains available without exposing profile import',
    (tester) async {
      final port = _MigrationAvailablePort();
      await _pumpAccount(tester, port);
      expect(find.byType(AccountCompatibilityCard), findsOneWidget);
      expect(find.byType(LegacyProfileMigrationCard), findsNothing);
      expect(port.migrationReads, 0);
    },
  );
  testWidgets(
    'SCM loading transitions in place and reduced motion stays static',
    (tester) async {
      await _pumpAccount(
        tester,
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await tester.runAsync(ScmSuccessMotion.verifyArtwork);
      final theme = Theme.of(
        tester.element(find.byKey(const Key('scm-account-brand'))),
      );
      Future<void> show({required bool loading, bool reduced = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.copyWith(
              extensions: [
                theme.extension<StarBridgeTokens>()!.copyWith(
                  motion: FutureRestraintStyle.motion,
                ),
              ],
            ),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: ScmSuccessMotion(
                  key: const Key('motion-test'),
                  play: !loading,
                  loading: loading,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      await show(loading: true);
      final original = tester.state(find.byKey(const Key('motion-test')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await show(loading: false);
      expect(
        identical(original, tester.state(find.byKey(const Key('motion-test')))),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await show(loading: true, reduced: true);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await show(loading: false, reduced: true);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account entry replays brief motion but refresh preserves its state',
    (tester) async {
      final port = InMemoryAccountAdapter.forReview(
        AccountReviewState.signedIn,
      );
      await _pumpAccount(tester, port);
      final brand = find.byKey(const Key('scm-account-brand'));
      final first = tester.state(brand);
      expect(tester.widget<ScmSuccessMotion>(brand).brief, isTrue);
      expect(tester.widget<ScmSuccessMotion>(brand).play, isTrue);
      expect(
        find.byWidgetPredicate(
          (w) => w is StarBridgeTooltip && w.message == '刷新账号资料',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('account-refresh')));
      await tester.pumpAndSettle();
      expect(identical(tester.state(brand), first), isTrue);
      await tester.tap(find.byKey(const Key('settings-section-generalData')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings-section-accountIdentity')),
      );
      await tester.pumpAndSettle();
      expect(identical(tester.state(brand), first), isFalse);
      expect(tester.widget<ScmSuccessMotion>(brand).brief, isTrue);
      expect(tester.widget<ScmSuccessMotion>(brand).play, isTrue);
    },
  );
  testWidgets('SCM V3 native artwork decodes and aligns without a fallback', (
    tester,
  ) async {
    await tester.runAsync(ScmSuccessMotion.verifyArtwork);
    expect(scmV3Alignment(0, .25, 1.26, -18), -18);
    expect(scmV3Alignment(1.26, .25, 1.26, -18), 0);
    expect(scmV3Alignment(1.30, .36, 1.30, 15), 0);
  });
  for (final size in [const Size(1600, 1000), const Size(1024, 768)]) {
    testWidgets('account layout keeps legacy access prominent at $size', (
      tester,
    ) async {
      await _pumpAccount(
        tester,
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
        size: size,
      );
      final legacy = find.byKey(const Key('account-compatibility-refresh'));
      final preferences = find.byKey(const Key('account-locale-field'));
      expect(
        tester.getTopLeft(legacy).dy,
        lessThan(tester.getTopLeft(preferences).dy),
      );
      expect(tester.getTopLeft(legacy).dy, lessThan(size.height));
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<ScmSuccessMotion>(
              find.byKey(const Key('scm-account-brand')),
            )
            .play,
        isTrue,
      );
      if (const bool.fromEnvironment('SB_ACCOUNT_QA')) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('account-qa-root')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('../.artifacts/account-layout-qa')
            ..createSync(recursive: true);
          File('${folder.path}/account-${size.width.toInt()}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'account safety entry opens its connected panel rather than the planned placeholder',
    (tester) async {
      await _pumpAccount(
        tester,
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      final entry = find.byKey(const Key('settings-capability-account-safety'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-safety-dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('settings-entry-account-safety')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'preference draft survives switching settings pages without saving',
    (tester) async {
      final port = InMemoryAccountAdapter.forReview(
        AccountReviewState.signedIn,
      );
      await _pumpAccount(tester, port);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('account-locale-field')),
          )
          .onChanged!('en-US');
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings-section-generalData')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings-section-accountIdentity')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('account-locale-field')),
            )
            .initialValue,
        'en-US',
      );
      expect(
        find.byKey(const Key('account-preferences-unsaved')),
        findsOneWidget,
      );
      expect(port.commands, isEmpty);
      await tester.ensureVisible(
        find.byKey(const Key('account-preferences-discard')),
      );
      await tester.tap(find.byKey(const Key('account-preferences-discard')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('account-preferences-unsaved')),
        findsNothing,
      );
      expect(port.commands, isEmpty);
    },
  );
  for (final legacySignedIn in [false, true]) {
    testWidgets(
      'current game remains visible without SCM session: legacy=$legacySignedIn',
      (tester) async {
        final port = _LegacyLoginPort()..legacySignedIn = legacySignedIn;
        await _pumpAccount(tester, port);
        expect(find.byKey(const Key('game-session-overview')), findsOneWidget);
        expect(port.scmCommands, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'optional SCM failure leaves legacy account usable without global alarm',
    (tester) async {
      final port = _LegacyLoginPort()..legacySignedIn = true;
      port.failScmLogin = true;
      await _pumpAccount(tester, port);
      await tester.tap(find.byKey(const Key('account-login')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-legacy-session')), findsOneWidget);
      expect(find.byKey(const Key('account-login-retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-cancel-login')));
      await tester.pumpAndSettle();
      expect(find.textContaining('SCM 授权未完成，旧账号仍保持登录'), findsOneWidget);
      expect(find.text('账号操作需要处理'), findsNothing);
      expect(find.text('退出 SCM 账号'), findsNothing);
      expect(find.text('退出账号'), findsWidgets);
      expect(port.legacySignedIn, isTrue);
    },
  );
  testWidgets(
    'avatar menu login navigates to account settings without authorization',
    (tester) async {
      final port = _LegacyLoginPort();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final composition = AppComposition.forTest(
        windowChrome: InMemoryWindowChrome(),
        accountPort: port,
      );
      await tester.pumpWidget(StarBridgeApp(composition: composition));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-menu-login')));
      await tester.pumpAndSettle();
      expect(port.scmCommands, 0);
      expect(port.calls, 0);
      expect(find.byKey(const Key('account-login')), findsOneWidget);
      expect(find.byKey(const Key('account-legacy-login')), findsOneWidget);
      expect(find.byKey(const Key('account-cancel-login')), findsNothing);
    },
  );
  testWidgets(
    'bound legacy login explains SCM sign-in instead of wrong password',
    (tester) async {
      final port = _LegacyLoginPort()
        ..result = const LegacyPasswordLoginResult('scmRequired');
      await _pumpAccount(tester, port);
      await tester.tap(find.byKey(const Key('account-legacy-login')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('legacy-login-email')),
        'old@example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('legacy-login-password')),
        'short',
      );
      await tester.tap(find.byKey(const Key('legacy-login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('此旧账号已绑定，请使用 SCM 账号登录。原有数据会继续沿用。'), findsOneWidget);
      expect(find.text('邮箱或密码不正确，请检查后重试。'), findsNothing);
      expect(port.legacySignedIn, isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('legacy-login-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('legacy sign-in verifies without SCM state and clears password', (
    tester,
  ) async {
    final port = _LegacyLoginPort();
    await _pumpAccount(tester, port);
    await tester.tap(find.byKey(const Key('account-legacy-login')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('legacy-login-email')),
      'old@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('legacy-login-password')),
      ' short ',
    );
    await tester.tap(find.byKey(const Key('legacy-login-submit')));
    await tester.pumpAndSettle();
    expect(port.calls, 1);
    expect(port.password, ' short ');
    expect(find.byKey(const Key('legacy-login-password')), findsNothing);
    expect(find.byKey(const Key('account-legacy-session')), findsOneWidget);
    expect(find.textContaining('已登录旧账号'), findsWidgets);
    expect(port.scmCommands, 0);
    await tester.tap(find.byKey(const Key('account-legacy-logout')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-login-email')), findsNothing);
    expect(find.byKey(const Key('account-login')), findsOneWidget);
  });
  testWidgets('skip legacy sign-in performs no authentication or logout', (
    tester,
  ) async {
    final port = _LegacyLoginPort();
    await _pumpAccount(tester, port);
    await tester.tap(find.byKey(const Key('account-legacy-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('legacy-login-skip')));
    await tester.pumpAndSettle();
    expect(port.calls, 0);
    expect(port.scmCommands, 0);
  });
  testWidgets('closing pending legacy login ignores late completion', (
    tester,
  ) async {
    final port = _LegacyLoginPort()
      ..pending = Completer<LegacyPasswordLoginResult>();
    await _pumpAccount(tester, port);
    await tester.tap(find.byKey(const Key('account-legacy-login')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('legacy-login-email')),
      'old@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('legacy-login-password')),
      'short',
    );
    await tester.tap(find.byKey(const Key('legacy-login-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('legacy-login-close')));
    await tester.pumpAndSettle();
    expect(port.cancels, 1);
    port.pending!.complete(const LegacyPasswordLoginResult('verified'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-login-result')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final entry in {
    const Locale('zh', 'CN'): '此旧账号已迁入 SCM，请使用 SCM 账号登录。',
    const Locale('zh', 'TW'): '此舊帳號已遷入 SCM，請使用 SCM 帳號登入。',
    const Locale('en', 'US'):
        'This legacy account has moved to SCM. Sign in with your SCM account.',
  }.entries) {
    testWidgets('retired legacy sign-in shows SCM hint in ${entry.key}', (
      tester,
    ) async {
      final port = _LegacyLoginPort()
        ..result = const LegacyPasswordLoginResult('retired');
      await _pumpAccount(
        tester,
        port,
        preferences: InMemoryAppPreferences(
          initial: AppPreferences.defaults.copyWith(locale: entry.key),
        ),
      );
      await tester.tap(find.byKey(const Key('account-legacy-login')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('legacy-login-email')),
        'old@example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('legacy-login-password')),
        'short',
      );
      await tester.tap(find.byKey(const Key('legacy-login-submit')));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byKey(const Key('legacy-login-result')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('legacy-login-close')));
      await tester.pumpAndSettle();
    });
  }
  for (final locale in [const Locale('zh', 'TW'), const Locale('en', 'US')]) {
    testWidgets(
      'legacy sign-in fits compact $locale and disables rate-limited submit',
      (tester) async {
        final port = _LegacyLoginPort()
          ..result = const LegacyPasswordLoginResult(
            'throttled',
            retryAfterSeconds: 90,
          );
        await _pumpAccount(
          tester,
          port,
          size: const Size(900, 620),
          preferences: InMemoryAppPreferences(
            initial: AppPreferences.defaults.copyWith(locale: locale),
          ),
        );
        await tester.tap(find.byKey(const Key('account-legacy-login')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('legacy-login-email')),
          'old@example.invalid',
        );
        await tester.enterText(
          find.byKey(const Key('legacy-login-password')),
          'short',
        );
        await tester.tap(find.byKey(const Key('legacy-login-submit')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('legacy-login-submit')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('legacy-login-close')));
        await tester.pumpAndSettle();
      },
    );
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('recovery server cooldown blocks both actions', (tester) async {
    final port = _RecoveryPort()
      ..sendResult = const PasswordRecoveryResult(
        'throttled',
        retryAfterSeconds: 120,
      );
    await _pumpAccount(tester, port);
    await tester.tap(find.byKey(const Key('account-password-recovery')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('recovery-email')),
      'old@example.invalid',
    );
    await tester.tap(find.byKey(const Key('recovery-send')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('recovery-send')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('recovery-submit')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('recovery-close')));
    await tester.pumpAndSettle();
  });

  for (final locale in [const Locale('zh', 'TW'), const Locale('en', 'US')]) {
    testWidgets('recovery fits a compact window in $locale', (tester) async {
      await _pumpAccount(
        tester,
        _RecoveryPort(),
        size: const Size(900, 620),
        preferences: InMemoryAppPreferences(
          initial: AppPreferences.defaults.copyWith(locale: locale),
        ),
      );
      await tester.tap(find.byKey(const Key('account-password-recovery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recovery-email')), findsOneWidget);
      final close = find.byKey(const Key('recovery-close'));
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('signed-out recovery sends once and never exposes registration', (
    tester,
  ) async {
    final port = _RecoveryPort();
    await _pumpAccount(tester, port);
    await tester.tap(find.byKey(const Key('account-password-recovery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不修改 SCM 密码'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('recovery-email')),
      'old@example.invalid',
    );
    await tester.tap(find.byKey(const Key('recovery-send')));
    await tester.pumpAndSettle();
    expect(port.sends, 1);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('recovery-send')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('请求已受理'), findsOneWidget);
    expect(port.delegate.commands, isEmpty);
    await tester.tap(find.byKey(const Key('recovery-close')));
    await tester.pumpAndSettle();
    expect(port.cancels, 1);
    expect(find.text('未登录'), findsOneWidget);
  });

  testWidgets(
    'recovery validates confirmation and clears secrets after success',
    (tester) async {
      final port = _RecoveryPort();
      await _pumpAccount(tester, port);
      await tester.tap(find.byKey(const Key('account-password-recovery')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recovery-email')),
        'old@example.invalid',
      );
      await tester.enterText(find.byKey(const Key('recovery-code')), '123456');
      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'synthetic-new-password',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm-password')),
        'different-password',
      );
      final submit = find.byKey(const Key('recovery-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(port.resets, 0);
      expect(find.text('两次输入的密码不一致。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('recovery-confirm-password')),
        'synthetic-new-password',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(port.resets, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('recovery-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('recovery-confirm-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('recovery-code')))
            .controller!
            .text,
        isEmpty,
      );
      expect(port.delegate.commands, isEmpty);
      await tester.tap(find.byKey(const Key('recovery-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing a pending recovery ignores its late result', (
    tester,
  ) async {
    final port = _RecoveryPort()..pending = Completer<PasswordRecoveryResult>();
    await _pumpAccount(tester, port);
    await tester.tap(find.byKey(const Key('account-password-recovery')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('recovery-email')),
      'old@example.invalid',
    );
    await tester.tap(find.byKey(const Key('recovery-send')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recovery-close')));
    await tester.pumpAndSettle();
    expect(port.cancels, 1);
    port.pending!.complete(const PasswordRecoveryResult('codeRequested'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-result')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported profile actions are disabled with an explanation', (
    tester,
  ) async {
    await _pumpAccount(
      tester,
      InMemoryAccountAdapter(initial: _storedCredentialSnapshot()),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('account-save-preferences')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('account-clear-cache')))
          .onPressed,
      isNull,
    );
    expect(find.text('当前版本仅支持查看资料偏好。'), findsOneWidget);
  });

  testWidgets(
    'preference authorization shows progress and cancellation preserves the draft',
    (tester) async {
      final port = _PendingProfilePort();
      await _pumpAccount(tester, port);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('account-locale-field')),
          )
          .onChanged!('en-US');
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('account-save-preferences')),
      );
      await tester.tap(find.byKey(const Key('account-save-preferences')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('account-save-preferences')),
          matching: find.byType(SuiteProgressBar),
        ),
        findsOneWidget,
      );
      expect(find.text('请在浏览器中完成授权，完成后将继续保存。'), findsOneWidget);
      final snapshot = (await port.delegate.read()).snapshot!;
      port.pending.complete(AccountPortResult.cancelled(snapshot));
      await tester.pumpAndSettle();
      expect(find.text('已取消保存，你的选择仍保留在此页面。'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('account-locale-field')),
            )
            .initialValue,
        'en-US',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('account-save-preferences')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('signed-out account route starts the real login intent', (
    tester,
  ) async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.signedOut,
    );
    await _pumpAccount(tester, adapter);

    expect(find.text('使用 SCM 账号继续'), findsOneWidget);
    expect(
      find.byKey(const Key('account-scm-brand-signed-out')),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<Image>(
            find.descendant(
              of: find.byKey(const Key('account-scm-brand-signed-out')),
              matching: find.byType(Image),
            ),
          )
          .map((image) => (image.image as AssetImage).assetName),
      [ScmBrandMark.markAssetPath, ScmBrandMark.wordmarkAssetPath],
    );
    await tester.tap(find.byKey(const Key('account-login')));
    await tester.pumpAndSettle();

    expect(adapter.commands.whereType<BeginAccountLogin>(), hasLength(1));
    expect(find.text('Aster Lin'), findsWidgets);
    expect(find.text('资料已同步'), findsOneWidget);
    expect(find.byKey(const Key('scm-account-brand')), findsOneWidget);
    expect(
      tester
          .widget<ScmSuccessMotion>(find.byKey(const Key('scm-account-brand')))
          .play,
      isFalse,
    );
    expect(find.byKey(const Key('account-login-dialog')), findsOneWidget);
    expect(find.byKey(const Key('account-login-motion')), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-cancel-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-login-dialog')), findsNothing);
    expect(adapter.commands.whereType<LogoutAccount>(), isEmpty);
  });

  testWidgets('pending browser login remains cancellable', (tester) async {
    final adapter = InMemoryAccountAdapter(
      initial: const AccountHostSnapshot.signedOut(generation: 0),
      holdLoginUntilCancelled: true,
    );
    await _pumpAccount(tester, adapter);

    expect(find.byKey(const Key('account-login-dialog')), findsNothing);
    expect(adapter.commands.whereType<BeginAccountLogin>(), isEmpty);

    await tester.tap(find.byKey(const Key('account-login')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('浏览器中完成授权'), findsOneWidget);
    expect(
      tester
          .widget<ScmSuccessMotion>(
            find.byKey(const Key('account-login-motion')),
          )
          .loading,
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('account-login-dialog')),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('account-cancel-login')));
    await tester.pumpAndSettle();
    expect(adapter.commands.whereType<CancelAccountLogin>(), hasLength(1));
    expect(find.text('使用 SCM 账号继续'), findsOneWidget);
    expect(find.byKey(const Key('account-login-dialog')), findsNothing);
    expect(adapter.commands.whereType<LogoutAccount>(), isEmpty);
  });

  testWidgets('Escape cancels modal authorization without logging out', (
    tester,
  ) async {
    final adapter = InMemoryAccountAdapter(
      initial: const AccountHostSnapshot.signedOut(generation: 0),
      holdLoginUntilCancelled: true,
    );
    await _pumpAccount(tester, adapter);
    await tester.tap(find.byKey(const Key('account-login')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-login-dialog')), findsNothing);
    expect(adapter.commands.whereType<CancelAccountLogin>(), hasLength(1));
    expect(adapter.commands.whereType<LogoutAccount>(), isEmpty);
  });

  testWidgets(
    'temporary credential outage keeps credentials and offers retry',
    (tester) async {
      final adapter = InMemoryAccountAdapter(
        initial: const AccountHostSnapshot(
          generation: 0,
          sessionState: AccountSessionState.credentialTemporarilyUnavailable,
          profileFreshness: AccountProfileFreshness.unavailable,
          identity: AccountIdentityProjection.unavailable(),
          compatibility: AccountCompatibilityProjection.unavailable(),
          localeOptions: [],
          timeZoneOptions: [],
        ),
      );
      await _pumpAccount(tester, adapter);

      expect(find.text('SCM 暂时不可用'), findsOneWidget);
      expect(find.textContaining('登录凭据仍安全保留'), findsOneWidget);
      expect(find.byKey(const Key('account-login')), findsNothing);
      expect(adapter.readCount, 1);

      await tester.tap(find.byKey(const Key('account-retry-session')));
      await tester.pumpAndSettle();

      expect(adapter.readCount, 2);
    },
  );

  testWidgets('expired credential offers an explicit reauthorization', (
    tester,
  ) async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.reauthorizationRequired,
    );
    await _pumpAccount(tester, adapter);

    expect(find.text('重新授权 SCM 账号'), findsWidgets);
    expect(find.textContaining('已停止使用无效凭据'), findsOneWidget);
    expect(
      find.byKey(const Key('account-scm-brand-signed-out')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('account-login')), findsNothing);

    await tester.tap(find.byKey(const Key('account-reauthorize')));
    await tester.pumpAndSettle();

    expect(adapter.commands.whereType<BeginAccountLogin>(), hasLength(1));
    expect(find.text('Aster Lin'), findsWidgets);
  });

  testWidgets('cached account remains readable and clearly read-only', (
    tester,
  ) async {
    final adapter = InMemoryAccountAdapter.forReview(AccountReviewState.cached);
    await _pumpAccount(tester, adapter);

    expect(find.text('Aster Lin'), findsWidgets);
    expect(find.text('离线缓存'), findsOneWidget);
    expect(find.textContaining('当前显示离线缓存'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('account-save-preferences')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('identity mismatch blocks only sensitive writes visibly', (
    tester,
  ) async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.mismatch,
    );
    await _pumpAccount(tester, adapter);

    expect(find.textContaining('当前游戏身份与 SCM 账号记录不一致'), findsOneWidget);
    expect(find.textContaining('需要确认游戏身份的操作已暂停'), findsWidgets);
    expect(find.byKey(const Key('account-save-preferences')), findsOneWidget);
  });

  testWidgets('logout updates the top-bar account summary', (tester) async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.signedIn,
    );
    await _pumpAccount(tester, adapter);

    expect(find.text('Aster Lin'), findsWidgets);
    final logout = find.byKey(const Key('account-logout'));
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pumpAndSettle();

    expect(adapter.commands.whereType<LogoutAccount>(), hasLength(1));
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('使用 SCM 账号继续'), findsOneWidget);
  });

  for (final storedCredential in [false, true]) {
    testWidgets(
      'S2 existing-account entry never offers provisioning, stored=$storedCredential',
      (tester) async {
        final adapter = storedCredential
            ? InMemoryAccountAdapter(initial: _storedCredentialSnapshot())
            : InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
        await _pumpAccount(tester, adapter);
        expect(
          find.byKey(const Key('account-compatibility-link')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('account-compatibility-link-manual')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('account-compatibility-create')),
          findsNothing,
        );
        expect(find.text('旧数据兼容'), findsOneWidget);
        expect(
          find.byKey(const Key('account-compatibility-refresh')),
          findsOneWidget,
        );
        expect(find.textContaining('新用户可创建'), findsNothing);
        expect(find.textContaining('发现本机已保存的迁移凭据'), findsNothing);
        expect(
          find.byKey(const Key('account-save-preferences')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('account-clear-cache')), findsOneWidget);
        expect(find.byKey(const Key('account-logout')), findsOneWidget);
        expect(adapter.commands, isEmpty);
        final previousReads = adapter.readCount;
        await tester.ensureVisible(
          find.byKey(const Key('account-compatibility-refresh')),
        );
        await tester.tap(
          find.byKey(const Key('account-compatibility-refresh')),
        );
        await tester.pumpAndSettle();
        expect(adapter.readCount, previousReads + 1);
        expect(adapter.commands, isEmpty);
        final link = find.byKey(const Key('account-compatibility-link'));
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        // Even if a stored credential exists, this entry asks for an explicit account.
        expect(
          find.byKey(const Key('account-legacy-dialog-close')),
          findsOneWidget,
        );
        expect(adapter.commands, isEmpty);
        await tester.tap(find.byKey(const Key('account-legacy-dialog-close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final localeCase in <({Locale locale, String heading})>[
    (locale: Locale('zh', 'TW'), heading: '資料偏好'),
    (locale: Locale('en', 'US'), heading: 'Profile preferences'),
  ]) {
    testWidgets('signed-in account route supports ${localeCase.locale}', (
      tester,
    ) async {
      final preferences = InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(locale: localeCase.locale),
      );
      await _pumpAccount(
        tester,
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
        preferences: preferences,
        size: const Size(900, 620),
      );

      expect(find.text(localeCase.heading), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final appearance in AppearanceMode.values) {
    testWidgets('probe style renders account route in ${appearance.name}', (
      tester,
    ) async {
      final preferences = InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(
          appearanceMode: appearance,
          designStyleId: ProbeStyle.id,
          locale: const Locale('ar', 'XB'),
        ),
      );
      await _pumpAccount(
        tester,
        InMemoryAccountAdapter.forReview(AccountReviewState.mismatch),
        preferences: preferences,
        size: const Size(900, 620),
      );

      expect(find.byKey(const Key('account-save-preferences')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('handle-mismatch-action')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

AccountHostSnapshot _storedCredentialSnapshot() {
  return const AccountHostSnapshot(
    generation: 2,
    sessionState: AccountSessionState.signedIn,
    route: AccountRoute(
      environment: 'synthetic',
      authority: 'scm-test',
      subject: 'synthetic-subject',
    ),
    profile: AccountProfile(
      displayName: 'Aster Lin',
      locale: 'zh-CN',
      timeZone: 'Asia/Shanghai',
    ),
    profileFreshness: AccountProfileFreshness.live,
    identity: AccountIdentityProjection(
      state: AccountIdentityState.match,
      sensitiveWritesAllowed: true,
      authoritativeHandle: 'Aster-Lin',
    ),
    compatibility: AccountCompatibilityProjection(
      identityState: AccountCompatibilityIdentityState.unlinked,
      relayState: AccountCompatibilityRelayState.notApplicable,
      storedLegacyCredentialAvailable: true,
      legacyFeaturesAvailable: false,
      availableActions: [
        AccountCompatibilityAction.linkExistingAccount,
        AccountCompatibilityAction.createCompatibilityIdentity,
      ],
    ),
    localeOptions: ['zh-CN', 'en-US'],
    timeZoneOptions: [
      AccountTimeZoneOption(
        value: 'Asia/Shanghai',
        label: 'Shanghai',
        offset: 'UTC+08:00',
      ),
    ],
  );
}

Future<void> _pumpAccount(
  WidgetTester tester,
  AccountPort adapter, {
  InMemoryAppPreferences? preferences,
  Size size = const Size(1280, 720),
}) async {
  if (const bool.fromEnvironment('SB_ACCOUNT_QA')) {
    await tester.runAsync(() async {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Saira': 'assets/fonts/Saira-VF.ttf',
        'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
        'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    });
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forTest(
    windowChrome: InMemoryWindowChrome(),
    accountPort: adapter,
    preferences: preferences,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('account-qa-root'),
      child: StarBridgeApp(composition: composition),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('account-command')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('account-menu-account-and-identity')));
  await tester.pumpAndSettle();
}

final class _MigrationAvailablePort
    implements AccountPort, LegacyProfileMigrationPort {
  final delegate = InMemoryAccountAdapter.forReview(
    AccountReviewState.signedIn,
  );
  int migrationReads = 0;
  @override
  Stream<AccountInvalidation> get invalidations => delegate.invalidations;
  @override
  Future<AccountPortResult> read() => delegate.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      delegate.execute(command);
  @override
  Future<void> close() => delegate.close();
  @override
  Future<LegacyProfileMigrationView> migrationStatus() async {
    migrationReads++;
    return const LegacyProfileMigrationView('credentialRequired');
  }

  @override
  Future<LegacyProfileMigrationView> previewMigration({
    LegacyAccountCredential? credential,
    LegacyProfileImportSelection? selection,
  }) => throw StateError('Import must not be exposed');
  @override
  Future<LegacyProfileMigrationView> confirmMigration(
    String previewId, {
    required bool replaceExisting,
  }) => throw StateError('Import must not be exposed');
}

final class _RecoveryPort implements AccountPort, PasswordRecoveryPort {
  final delegate = InMemoryAccountAdapter.forReview(
    AccountReviewState.signedOut,
  );
  int sends = 0, resets = 0, cancels = 0;
  PasswordRecoveryResult sendResult = const PasswordRecoveryResult(
    'codeRequested',
    retryAfterSeconds: 60,
  );
  Completer<PasswordRecoveryResult>? pending;
  @override
  bool get supportsPasswordRecovery => true;
  @override
  Future<PasswordRecoveryResult> sendPasswordResetCode(String email) {
    sends++;
    return pending?.future ?? Future.value(sendResult);
  }

  @override
  Future<PasswordRecoveryResult> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) async {
    resets++;
    return const PasswordRecoveryResult('reset');
  }

  @override
  Future<void> cancelPasswordRecovery() async {
    cancels++;
  }

  @override
  Stream<AccountInvalidation> get invalidations => delegate.invalidations;
  @override
  Future<AccountPortResult> read() => delegate.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      delegate.execute(command);
  @override
  Future<void> close() => delegate.close();
}

final class _LegacyLoginPort implements AccountPort, LegacyPasswordLoginPort {
  bool legacySignedIn = false;
  bool failScmLogin = false;
  final delegate = InMemoryAccountAdapter.forReview(
    AccountReviewState.signedOut,
  );
  int calls = 0, cancels = 0, scmCommands = 0;
  String? password;
  LegacyPasswordLoginResult result = const LegacyPasswordLoginResult(
    'verified',
  );
  Completer<LegacyPasswordLoginResult>? pending;
  @override
  bool get supportsLegacyPasswordLogin => true;
  @override
  Future<LegacyPasswordLoginResult> loginLegacy(
    String email,
    String password,
  ) async {
    calls++;
    this.password = password;
    final value = await (pending?.future ?? Future.value(result));
    if (value.outcome == 'verified') legacySignedIn = true;
    return value;
  }

  @override
  Future<void> cancelLegacyPasswordLogin() async {
    cancels++;
  }

  @override
  Stream<AccountInvalidation> get invalidations => delegate.invalidations;
  @override
  Future<AccountPortResult> read() async => legacySignedIn
      ? AccountPortResult.completed(
          const AccountHostSnapshot(
            generation: 0,
            sessionState: AccountSessionState.legacySignedIn,
            profile: AccountProfile(displayName: 'Old Commander'),
            profileFreshness: AccountProfileFreshness.live,
            identity: AccountIdentityProjection.unavailable(),
            compatibility: AccountCompatibilityProjection.unavailable(),
            localeOptions: [],
            timeZoneOptions: [],
          ),
        )
      : await delegate.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) {
    scmCommands++;
    if (command is BeginAccountLogin && failScmLogin) {
      return Future.value(
        const AccountPortResult.failed(
          AccountFailure(
            code: 'host.unavailable',
            messageKey: 'account.hostUnavailable',
            retryable: true,
          ),
        ),
      );
    }
    if (command is LogoutAccount) legacySignedIn = false;
    return delegate.execute(command);
  }

  @override
  Future<void> close() => delegate.close();
}

final class _PendingProfilePort implements AccountPort {
  final delegate = InMemoryAccountAdapter.forReview(
    AccountReviewState.signedIn,
  );
  final pending = Completer<AccountPortResult>();
  @override
  Stream<AccountInvalidation> get invalidations => delegate.invalidations;
  @override
  Future<AccountPortResult> read() => delegate.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      command is SaveAccountPreferences
      ? pending.future
      : delegate.execute(command);
  @override
  Future<void> close() => delegate.close();
}
