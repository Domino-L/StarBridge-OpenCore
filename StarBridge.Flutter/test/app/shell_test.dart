import 'dart:async';

import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';

import '../features/communities/community_visitor_profile_test.dart'
    show VisitorPort;
import '../features/friends/social_layout_test.dart' show capture, loadFonts;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'visitor wallpaper fills the shell workspace behind navigation at QHD',
    (tester) async {
      await loadFonts();
      final boundary = GlobalKey();
      tester.view.physicalSize = const Size(2560, 1392);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = VisitorPort();
      addTearDown(port.changes.close);
      final composition = AppComposition.forShellReview(
        windowChrome: InMemoryWindowChrome(),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: StarBridgeApp(composition: composition),
        ),
      );
      await tester.pumpAndSettle();
      final source = tester.element(find.byType(StarBridgeShell));
      final nav = UserInteractionScope.maybeOf(source)!.navigation;
      unawaited(
        nav.open!(
          source,
          (_) => UserProfilePage(
            port: port,
            target: const UserTarget.community('organization', 'member'),
          ),
          'navigation.profile',
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byType(UserProfilePage));
      final background = tester.getRect(
        find.byKey(const Key('profile-page-wallpaper-stack')),
      );
      expect(background, page);
      final toolbar = tester.getRect(
        find.byKey(const Key('visitor-profile-toolbar')),
      );
      expect(background.contains(toolbar.topLeft), isTrue);
      expect(background.contains(toolbar.bottomRight), isTrue);
      expect(find.byType(BackButton), findsOneWidget);
      // The wallpaper starts directly under shell chrome, not after two extra rows.
      expect(page, tester.getRect(find.byType(Navigator).last));
      expect((page.width / page.height - 16 / 9).abs(), lessThan(0.06));
      await capture(tester, boundary, 'visitor-profile-full-background-qhd');
      final before = port.reads;
      await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
      await tester.pumpAndSettle();
      expect(port.reads, greaterThan(before));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PersonalProfilePage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'avatar page stays inside shell and returns to the same source state',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = ValueNotifier<OpenDestinationIntent?>(null);
      final composition = AppComposition.forShellReview(
        windowChrome: InMemoryWindowChrome(),
      );
      await tester.pumpWidget(
        StarBridgeApp(composition: composition, navigationRequests: requests),
      );
      await tester.pumpAndSettle();
      requests.value = const OpenDestinationIntent('/friends');
      await tester.pumpAndSettle();
      final original = tester.state(find.byType(FriendsPage));
      final source = tester.element(find.byType(FriendsPage));
      final nav = UserInteractionScope.maybeOf(source)!.navigation;
      unawaited(
        nav.open!(
          source,
          (_) => const Text('Visitor full page'),
          'navigation.profile',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Visitor full page'), findsOneWidget);
      expect(find.byType(StarBridgeShell), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(FriendsPage), findsNothing);
      final visitorContext = tester.element(find.text('Visitor full page'));
      final leave = UserPageLeaveScope.maybeOf(visitorContext)!;
      var allowLeave = false;
      leave.confirm = () async => allowLeave;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Visitor full page'), findsOneWidget);
      requests.value = const OpenDestinationIntent('/settings/privacy');
      await tester.pumpAndSettle();
      expect(find.text('Visitor full page'), findsOneWidget);
      requests.value = null;
      allowLeave = true;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(FriendsPage)), original),
        isTrue,
      );
      unawaited(
        nav.open!(
          source,
          (_) => const Text('Visitor full page'),
          'navigation.profile',
        ),
      );
      await tester.pumpAndSettle();
      requests.value = const OpenDestinationIntent('/settings/privacy');
      await tester.pumpAndSettle();
      expect(find.text('Visitor full page'), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      requests.dispose();
    },
  );
  testWidgets(
    'privacy shortcut opens the existing settings workspace without a modal',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = ValueNotifier<OpenDestinationIntent?>(null);
      final composition = AppComposition.forShellReview(
        windowChrome: InMemoryWindowChrome(),
      );
      await tester.pumpWidget(
        StarBridgeApp(composition: composition, navigationRequests: requests),
      );
      await tester.pumpAndSettle();
      requests.value = const OpenDestinationIntent('/settings/privacy');
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingsPage>(find.byType(SettingsPage)).initialSection,
        SettingsSection.syncPrivacy,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      requests.dispose();
    },
  );

  testWidgets('native window intents stay behind the window port', (
    tester,
  ) async {
    final windowChrome = InMemoryWindowChrome();
    await _pumpShell(tester, windowChrome: windowChrome);

    await tester.tap(find.byTooltip('最小化'));
    await tester.tap(find.byTooltip('最大化'));
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();

    expect(windowChrome.commands, ['minimize', 'toggleMaximize', 'close']);
  });

  testWidgets('maximize control changes to restore while maximized', (
    tester,
  ) async {
    final windowChrome = InMemoryWindowChrome();
    await _pumpShell(tester, windowChrome: windowChrome);

    await tester.tap(find.byKey(const Key('window-maximize-control')));
    await tester.pump();

    expect(find.byTooltip('还原'), findsOneWidget);

    windowChrome.setMaximizedForTest(false);
    await tester.pump();
    expect(find.byTooltip('最大化'), findsOneWidget);
  });

  testWidgets('registry navigation changes the empty workspace destination', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(find.text('首页'), findsOneWidget);
    await tester.tap(find.text('行动'));
    await tester.pumpAndSettle();

    expect(find.text('行动'), findsWidgets);
    expect(find.text('组织与舰队的目标性协作'), findsOneWidget);
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('operations placeholder'),
    );
    expect(semantics.label, 'operations placeholder');
  });

  testWidgets('disconnected review state never presents a false online path', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(find.text('客户端连接中断'), findsOneWidget);
    expect(find.text('Native Host 暂时不可用，应用正在自动重连。'), findsOneWidget);
    expect(find.text('游戏 未运行'), findsNothing);
    expect(find.text('身份 待确认'), findsNothing);
    expect(find.text('网络 等待主机'), findsNothing);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.byKey(const Key('connection-status-notice')), findsOneWidget);
    expect(find.byTooltip('Native Host 未连接，暂时无法更改'), findsOneWidget);
  });

  testWidgets('healthy and expected idle state omits the status notice', (
    tester,
  ) async {
    final chrome = InMemoryShellChrome(
      initial: InMemoryShellChrome.connectedProjection,
    );
    await _pumpShell(tester, shellChrome: chrome);

    expect(find.byKey(const Key('connection-status-notice')), findsNothing);
    expect(find.text('主机 已连接'), findsNothing);
    expect(find.text('游戏 未运行'), findsNothing);
  });

  testWidgets(
    'account issue remains actionable in the status strip and top-right',
    (tester) async {
      await _pumpShell(
        tester,
        shellChrome: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        accountPort: InMemoryAccountAdapter.forReview(
          AccountReviewState.reauthorizationRequired,
        ),
      );

      expect(find.byKey(const Key('connection-status-notice')), findsOneWidget);
      expect(find.byKey(const Key('connection-status-retry')), findsOneWidget);
      expect(find.byKey(const Key('account-status-issue')), findsOneWidget);
      expect(find.text('SCM 登录需要更新'), findsWidgets);

      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      expect(find.text('请重新登录以继续同步账号与舰队资料。'), findsWidgets);

      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-status-retry')));
      await tester.pumpAndSettle();

      expect(find.text('Aster Lin'), findsWidgets);
      expect(find.byKey(const Key('account-status-issue')), findsNothing);
      expect(find.byKey(const Key('connection-status-notice')), findsNothing);
    },
  );

  testWidgets(
    'account initialization is presented as loading, not signed out',
    (tester) async {
      await _pumpShell(
        tester,
        accountPort: _PendingAccountPort(),
        settle: false,
      );

      expect(find.byKey(const Key('account-avatar-loading')), findsOneWidget);
      expect(find.text('正在读取账号状态…'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);
    },
  );

  testWidgets(
    'account status retry stays visibly busy until refresh finishes',
    (tester) async {
      final accountPort = _DelayedRetryAccountPort();
      await _pumpShell(
        tester,
        shellChrome: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        accountPort: accountPort,
      );

      expect(find.text('无法连接服务器'), findsWidgets);
      expect(find.text('无法连接 StarBridge 服务器'), findsNothing);

      await tester.tap(find.byKey(const Key('connection-status-retry')));
      await tester.pump();

      expect(
        find.byKey(const Key('connection-status-retry-loading')),
        findsOneWidget,
      );
      expect(find.text('正在重试…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('connection-status-retry')),
            )
            .onPressed,
        isNull,
      );

      accountPort.completeRetry();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('connection-status-retry-loading')),
        findsNothing,
      );
      expect(find.text('立即重试'), findsOneWidget);
    },
  );

  testWidgets('host status retry stays visibly busy until reconnect finishes', (
    tester,
  ) async {
    final retry = Completer<void>();
    await _pumpShell(tester, onRetryConnection: () => retry.future);

    await tester.tap(find.byKey(const Key('connection-status-retry')));
    await tester.pump();

    expect(
      find.byKey(const Key('connection-status-retry-loading')),
      findsOneWidget,
    );
    expect(find.text('正在重试…'), findsOneWidget);

    retry.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('connection-status-retry-loading')),
      findsNothing,
    );
    expect(find.text('立即重试'), findsOneWidget);
  });

  for (final testCase in const [
    (state: ConnectionVisualState.pending, label: 'pending'),
    (state: ConnectionVisualState.limited, label: 'limited'),
    (state: ConnectionVisualState.stale, label: 'stale'),
  ]) {
    testWidgets('${testCase.label} status uses its semantic surface color', (
      tester,
    ) async {
      final chrome = InMemoryShellChrome(
        initial: InMemoryShellChrome.connectedProjection.copyWith(
          connectionIssue: ConnectionIssueProjection(
            domain: ConnectionStatusDomain.network,
            titleKey: 'connection.account.unavailable.title',
            detailKey: 'connection.account.unavailable.detail',
            state: testCase.state,
          ),
        ),
      );
      await _pumpShell(tester, shellChrome: chrome);

      final notice = tester.widget<Container>(
        find.byKey(const Key('connection-status-notice')),
      );
      final decoration = notice.decoration! as BoxDecoration;
      final tokens = tester.element(find.byType(StarBridgeShell)).tokens;
      final expected = switch (testCase.state) {
        ConnectionVisualState.pending => tokens.colors.infoSoft,
        ConnectionVisualState.limited ||
        ConnectionVisualState.stale => tokens.colors.warningSoft,
        _ => throw StateError('Unexpected test state.'),
      };
      expect(decoration.color, expected);
    });
  }

  testWidgets(
    'overlay preference remains distinct from the actual host scene',
    (tester) async {
      final chrome = InMemoryShellChrome(
        initial: InMemoryShellChrome.connectedProjection,
      );
      await _pumpShell(tester, shellChrome: chrome);

      await tester.tap(find.byTooltip('浮层场景：默认场景'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('行动场景'));
      await tester.pumpAndSettle();

      expect(chrome.projection.value.overlay.preferredSceneId, 'operation');
      expect(chrome.projection.value.overlay.actualSceneId, 'default');
    },
  );

  testWidgets('top actions remain real route destinations', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byTooltip('好友'));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    for (final section in ['friends', 'incoming', 'outgoing', 'blocked']) {
      expect(find.byKey(ValueKey('friends-nav-$section')), findsOneWidget);
    }
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('好友、私信与最近玩过'), findsOneWidget);
  });

  testWidgets('deferred navigation entries are truthful destinations', (
    tester,
  ) async {
    await _pumpShell(tester);

    await tester.tap(find.text('交易大厅'));
    await tester.pumpAndSettle();
    expect(find.text('该入口尚未开放'), findsOneWidget);
    expect(
      find.byKey(const Key('marketplace-deferred-destination')),
      findsOneWidget,
    );

    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();
    expect(find.text('该入口尚未开放'), findsOneWidget);
    expect(find.byKey(const Key('tools-deferred-destination')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  InMemoryWindowChrome? windowChrome,
  InMemoryShellChrome? shellChrome,
  AccountPort? accountPort,
  Future<void> Function()? onRetryConnection,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forTest(
    windowChrome: windowChrome ?? InMemoryWindowChrome(),
    shellChrome: shellChrome,
    accountPort: accountPort,
  );
  await tester.pumpWidget(
    StarBridgeApp(
      composition: composition,
      onRetryConnection: onRetryConnection,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _PendingAccountPort implements AccountPort {
  final Completer<AccountPortResult> _readCompleter =
      Completer<AccountPortResult>();

  @override
  Stream<AccountInvalidation> get invalidations => const Stream.empty();

  @override
  Future<AccountPortResult> read() => _readCompleter.future;

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      throw UnsupportedError('No account command is expected while loading.');

  @override
  Future<void> close() async {}
}

final class _DelayedRetryAccountPort implements AccountPort {
  final Completer<AccountPortResult> _retry = Completer<AccountPortResult>();
  var _readCount = 0;

  @override
  Stream<AccountInvalidation> get invalidations => const Stream.empty();

  @override
  Future<AccountPortResult> read() {
    _readCount++;
    if (_readCount == 1) {
      return Future.value(AccountPortResult.completed(_snapshot(1)));
    }
    return _retry.future;
  }

  void completeRetry() {
    _retry.complete(AccountPortResult.completed(_snapshot(2)));
  }

  AccountHostSnapshot _snapshot(int generation) => AccountHostSnapshot(
    generation: generation,
    sessionState: AccountSessionState.credentialTemporarilyUnavailable,
    profileFreshness: AccountProfileFreshness.unavailable,
    identity: const AccountIdentityProjection.unavailable(),
    compatibility: const AccountCompatibilityProjection.retired(),
    localeOptions: const [],
    timeZoneOptions: const [],
  );

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      throw UnsupportedError('No account command is expected during refresh.');

  @override
  Future<void> close() async {}
}
