import 'dart:async';

import '../../features/settings/notification_editor_frame.dart';

import '../routing/exit_application_intent.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/account/in_memory_account_adapter.dart';
import '../../features/account/account_module.dart';
import '../../features/overlay_settings/overlay_settings_feature.dart';
import '../../features/personal_profile/in_memory_personal_profile_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import '../../platform/host/native_host_connector.dart';
import '../../platform/host/native_host_session_connector.dart';
import '../../platform/host/windows_native_host_platform.dart';
import '../../platform/lifecycle/application_lifecycle_port.dart';
import '../../platform/lifecycle/method_channel_application_lifecycle.dart';
import '../../platform/window/method_channel_window_chrome.dart';
import '../../platform/window/window_chrome_port.dart';
import '../bootstrap/shell_review_configuration.dart';
import '../bootstrap/starbridge_app.dart';
import '../composition/app_composition.dart';
import '../localization/app_strings.dart';
import '../preferences/app_preferences_module.dart';
import '../preferences/app_preferences_projection.dart';
import '../preferences/bridge_app_preferences.dart';
import '../preferences/in_memory_app_preferences.dart';
import '../shell/chrome/in_memory_shell_chrome.dart';
import '../startup/startup_session.dart';
import 'application_lifecycle_prompts.dart';
import 'example_scene_control.dart';
import 'startup_prompt_queue.dart';
import 'first_use_privacy_flow.dart';
import 'test_build_notice_flow.dart';
import 'update_startup_receipt.dart';
import 'application_update_flow.dart';
import '../routing/open_destination_intent.dart';
import '../../features/settings/local_privacy_page.dart';
import '../../features/settings/bridge_data_location_result.dart';
import '../../features/settings/data_location_copy.dart';
import '../../platform/bridge/bridge_client_session.dart';

class StarBridgeRuntimeHost extends StatefulWidget {
  const StarBridgeRuntimeHost({
    required this.environment,
    this.windowChrome,
    this.nativeHostConnector,
    this.applicationLifecycle,
    this.reconnectDelay = const Duration(seconds: 2),
    super.key,
  });

  final Map<String, String> environment;
  final WindowChromePort? windowChrome;
  final NativeHostConnector? nativeHostConnector;
  final ApplicationLifecyclePort? applicationLifecycle;
  final Duration reconnectDelay;

  @override
  State<StarBridgeRuntimeHost> createState() => _StarBridgeRuntimeHostState();
}

class _StarBridgeRuntimeHostState extends State<StarBridgeRuntimeHost> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final StartupSession _startup = StartupSession();
  late final WindowChromePort _windowChrome;
  late final NativeHostConnector _nativeHostConnector;
  late final ApplicationLifecyclePort _applicationLifecycle;
  late final bool _ownsApplicationLifecycle;
  StreamSubscription<void>? _closeRequestSubscription;
  late final AppPreferencesModule _preferences;
  late AppComposition _composition;
  AccountModule? _startupAccount;
  bool _exampleScene = false;
  bool _disposed = false;
  bool _hasConnectedHost = false;
  int _hostRevision = 0;
  Future<void>? _connectionAttempt;
  Timer? _reconnectTimer;
  Timer? _storageResultRetry;
  bool _handlingCloseRequest = false;
  bool _startupChoiceVisible = false;
  late final StartupPromptQueue _prompts;
  FirstUsePrivacyFlow? _privacyFlow;
  TestBuildNoticeFlow? _noticeFlow;
  ApplicationUpdateFlow? _updateFlow;
  final _shownUpdateVersions = <String>{};
  final _navigationRequests = ValueNotifier<OpenDestinationIntent?>(null);

  bool get _promptReady =>
      !_disposed &&
      mounted &&
      _startup.complete &&
      !_handlingCloseRequest &&
      !_exampleScene &&
      _hasConnectedHost;

  void _bindPrivacyFlow() {
    _navigationRequests.value = null;
    _privacyFlow?.dispose();
    final privacy = _composition.localPrivacy;
    _privacyFlow = privacy == null
        ? null
        : FirstUsePrivacyFlow(
            account: _composition.account,
            privacy: privacy,
            queue: _prompts,
            ready: () => _promptReady && !(_noticeFlow?.blocksPrompts ?? false),
            onAdjust: () => _navigationRequests.value = OpenDestinationIntent(
              '/settings/privacy',
            ),
          );
    _privacyFlow?.wake();
  }

  @override
  void initState() {
    super.initState();
    _prompts = StartupPromptQueue();
    _windowChrome = widget.windowChrome ?? MethodChannelWindowChrome();
    _nativeHostConnector =
        widget.nativeHostConnector ??
        NativeHostSessionConnector(platform: WindowsNativeHostPlatformPort());
    _ownsApplicationLifecycle = widget.applicationLifecycle == null;
    _applicationLifecycle =
        widget.applicationLifecycle ?? MethodChannelApplicationLifecycle();
    _preferences = AppPreferencesModule(
      systemLocales: WidgetsBinding.instance.platformDispatcher.locales,
    );
    _composition = _createProductComposition();
    _preferences.projection.addListener(_handlePreferencesChanged);
    _startup.addListener(_handleStartupChanged);
    _closeRequestSubscription = _applicationLifecycle.closeRequests.listen(
      (_) => unawaited(_handleCloseRequest()),
    );
    _requestHostConnection();
  }

  void _handlePreferencesChanged() {
    _syncApplicationLifecycle();
    _scheduleStartupChoice();
  }

  void _handleStartupChanged() {
    if (_startup.complete) _observeStartupAccount(null);
    _scheduleStartupChoice();
  }

  void _observeStartupAccount(AccountModule? account) {
    _startupAccount?.projection.removeListener(_handleStartupAccountChanged);
    _startupAccount = account;
    account?.projection.addListener(_handleStartupAccountChanged);
  }

  void _handleStartupAccountChanged() {
    if (_disposed ||
        _exampleScene ||
        !_hasConnectedHost ||
        _startup.complete ||
        !identical(_startupAccount, _composition.account)) {
      return;
    }
    _finishStartupPreparation();
  }

  void _syncApplicationLifecycle() {
    final confirmed = _preferences.projection.value.confirmed;
    if (confirmed == null) {
      return;
    }
    final behavior = confirmed.applicationBehavior.normalize();
    unawaited(
      _applicationLifecycle.configure(
        ApplicationWindowBehavior(
          keepRunningInBackground: behavior.keepRunningInBackground,
          startMinimized: behavior.startMinimized,
        ),
      ),
    );
  }

  void _scheduleStartupChoice() {
    _noticeFlow?.wake();
    _privacyFlow?.wake();
    _updateFlow?.wake();
    _prompts.wake();
    if (_disposed ||
        !_startup.complete ||
        _handlingCloseRequest ||
        _exampleScene ||
        _startupChoiceVisible) {
      return;
    }
    final confirmed = _preferences.projection.value.confirmed;
    if (confirmed == null || confirmed.applicationBehavior.startupChoiceMade) {
      return;
    }
    _prompts.enqueue(
      'startup-choice',
      priority: 200,
      eligible: () =>
          _promptReady &&
          !(_noticeFlow?.blocksPrompts ?? false) &&
          !_startupChoiceVisible &&
          !(_privacyFlow?.blocksOptionalPrompt ?? false) &&
          _preferences
                  .projection
                  .value
                  .confirmed
                  ?.applicationBehavior
                  .startupChoiceMade ==
              false,
      show: _showStartupChoice,
    );
  }

  Future<void> _showStartupChoice() async {
    if (_startupChoiceVisible ||
        _disposed ||
        _exampleScene ||
        !mounted ||
        !_startup.complete ||
        _handlingCloseRequest) {
      return;
    }
    final navigatorContext = _navigatorKey.currentContext;
    final confirmed = _preferences.projection.value.confirmed;
    if (navigatorContext == null ||
        confirmed == null ||
        confirmed.applicationBehavior.startupChoiceMade) {
      if (navigatorContext == null && confirmed != null) {
        _scheduleStartupChoice();
      }
      return;
    }

    _startupChoiceVisible = true;
    try {
      await showFirstStartupChoicePrompt(
        navigatorContext,
        onSave: (selected) async {
          final latest = _preferences.projection.value.confirmed;
          return latest != null &&
              await _preferences.setApplicationBehavior(
                latest.applicationBehavior
                    .copyWith(
                      launchAtStartup: selected,
                      startMinimized: selected,
                      startupChoiceMade: true,
                    )
                    .normalize(),
              );
        },
      );
    } finally {
      _startupChoiceVisible = false;
    }
  }

  Future<void> _handleCloseRequest({
    bool completelyExit = false,
    Future<bool> Function()? beforeExit,
  }) async {
    if (_handlingCloseRequest || !mounted) {
      return;
    }
    _handlingCloseRequest = true;
    try {
      if (_prompts.hasBlockingRoute) {
        await _applicationLifecycle.cancelCloseRequest();
        return;
      }
      final privacy = _composition.localPrivacy;
      if (!await confirmNotificationLeave(_composition.notificationSettings)) {
        await _applicationLifecycle.cancelCloseRequest();
        return;
      }
      if (privacy != null && (privacy.dirty || privacy.saving)) {
        final context = _navigatorKey.currentContext;
        if (context == null ||
            !context.mounted ||
            !await confirmLocalPrivacyLeave(context, privacy)) {
          await _applicationLifecycle.cancelCloseRequest();
          return;
        }
      }
      if (completelyExit) {
        final context = _navigatorKey.currentContext;
        if (context == null ||
            !context.mounted ||
            !await confirmOverlayWorkspaceLeave(
              context,
              _composition.overlaySettings,
            )) {
          await _applicationLifecycle.cancelCloseRequest();
          return;
        }
        if (beforeExit != null) {
          var prepared = false;
          try {
            prepared = await beforeExit();
          } on Object {
            prepared = false;
          }
          if (!prepared || !mounted || _disposed) {
            await _applicationLifecycle.cancelCloseRequest();
            return;
          }
        }
        await _applicationLifecycle.exitApplication();
        return;
      }
      final projection = _preferences.projection.value;
      final confirmed = projection.confirmed;
      if (confirmed == null) {
        await _applicationLifecycle.exitApplication();
        return;
      }

      var behavior = confirmed.applicationBehavior.normalize();
      if (behavior.shouldPromptForCloseBehavior) {
        final navigatorContext = _navigatorKey.currentContext;
        if (navigatorContext == null || !navigatorContext.mounted) {
          await _applicationLifecycle.cancelCloseRequest();
          return;
        }
        final keepRunning = await showFirstCloseBehaviorPrompt(
          navigatorContext,
        );
        if (keepRunning == null) {
          await _applicationLifecycle.cancelCloseRequest();
          return;
        }
        behavior = behavior.copyWith(
          keepRunningInBackground: keepRunning,
          closeBehaviorChoiceMade: true,
        );
        if (!await _preferences.setApplicationBehavior(behavior)) {
          await _applicationLifecycle.cancelCloseRequest();
          if (mounted && navigatorContext.mounted) {
            ScaffoldMessenger.of(navigatorContext).showSnackBar(
              SnackBar(
                content: Text(
                  AppStrings.of(navigatorContext)
                      .text('settings.lifecycle.close.saveFailed'),
                ),
              ),
            );
          }
          return;
        }
      }

      if (behavior.keepRunningInBackground) {
        final showHint = !behavior.backgroundHintShown;
        await _applicationLifecycle.hideToTray(showHint: showHint);
        if (showHint) {
          await _preferences.setApplicationBehavior(
            behavior.copyWith(backgroundHintShown: true),
          );
        }
      } else {
        await _applicationLifecycle.exitApplication();
      }
    } finally {
      _handlingCloseRequest = false;
      _scheduleStartupChoice();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
          onInvoke: (intent) {
            unawaited(
              _handleCloseRequest(
                completelyExit: true,
                beforeExit: intent.beforeExit,
              ),
            );
            return null;
          },
        ),
      },
      child: StarBridgeApp(
        key: ObjectKey(_composition),
        navigatorKey: _navigatorKey,
        navigatorObservers: [_prompts],
        navigationRequests: _navigationRequests,
        composition: _composition,
        onRetryConnection: _retryHostConnection,
        startupSession: _startup,
        onRetryStartup: _retryStartup,
        exampleSceneControl: ExampleSceneControl.available(
          active: _exampleScene,
          onToggle: _toggleExampleScene,
        ),
      ),
    );
  }

  void _toggleExampleScene() {
    _updateFlow?.dispose();
    _updateFlow = null;
    _noticeFlow?.dispose();
    _noticeFlow = null;
    _privacyFlow?.dispose();
    _privacyFlow = null;
    _observeStartupAccount(null);
    final nextIsExample = !_exampleScene;
    _hostRevision++;
    _hasConnectedHost = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (nextIsExample) {
      _preferences.detachStore();
    }
    final nextComposition = nextIsExample
        ? _createExampleComposition()
        : _createProductComposition();
    setState(() {
      _exampleScene = nextIsExample;
      _composition = nextComposition;
    });
    if (!nextIsExample) {
      _requestHostConnection();
    }
  }

  void _requestHostConnection() {
    if (_disposed || _exampleScene || _hasConnectedHost) {
      return;
    }
    if (_connectionAttempt != null) {
      return;
    }
    final revision = _hostRevision;
    late final Future<void> attempt;
    attempt = _connectHost(revision).whenComplete(() {
      if (identical(_connectionAttempt, attempt)) {
        _connectionAttempt = null;
      }
      if (!_disposed &&
          !_exampleScene &&
          !_hasConnectedHost &&
          _reconnectTimer == null) {
        _requestHostConnection();
      }
    });
    _connectionAttempt = attempt;
  }

  Future<void> _retryHostConnection() async {
    if (_disposed || _exampleScene || _hasConnectedHost) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _requestHostConnection();
    final attempt = _connectionAttempt;
    if (attempt != null) {
      await attempt;
    }
  }

  Future<void> _retryStartup() async {
    if (_disposed || _exampleScene || _startup.complete) return;
    if (!_hasConnectedHost) {
      _startup.connecting(manual: true);
      await _retryHostConnection();
      return;
    }
    final revision = _hostRevision;
    final account = _composition.account;
    if (_preferences.projection.value.phase != AppPreferencesPhase.ready) {
      _startup.readingPreferences();
      await _preferences.retry();
    } else {
      _startup.readingAccount();
      await account.refresh();
    }
    if (!_disposed &&
        !_exampleScene &&
        _hasConnectedHost &&
        revision == _hostRevision) {
      _finishStartupPreparation();
    }
  }

  void _finishStartupPreparation() {
    if (_preferences.projection.value.phase == AppPreferencesPhase.ready) {
      _startup.resolveAccount(_composition.account.projection.value);
    } else {
      _startup.preferencesUnavailable();
    }
  }

  void _readStorageMigrationResult(BridgeClientSession session, int revision) {
    if (_disposed || revision != _hostRevision) return;
    if (!session.hostCapabilities.contains('dataLocation.getMigrationResult') ||
        !session.hostCapabilities.contains(
          'dataLocation.acknowledgeMigrationResult',
        )) {
      return;
    }
    unawaited(() async {
      DataLocationMigrationResult? result;
      try {
        result = await BridgeDataLocationResult(session).read();
      } on Object {
        _retryStorageResult(
          revision,
          () => _readStorageMigrationResult(session, revision),
        );
        return;
      }
      if (result == null || _disposed || revision != _hostRevision) return;
      final migrationResult = result;
      final key = 'storage-migration-result-${migrationResult.nonce}';
      _prompts.enqueue(
        key,
        priority: 20,
        eligible: () => _promptReady && revision == _hostRevision && !_disposed,
        show: () async {
          final context = _navigatorKey.currentContext;
          if (context == null || !context.mounted) {
            _retryStorageResult(
              revision,
              () => _readStorageMigrationResult(session, revision),
            );
            return;
          }
          final controller = ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                dataLocationCopy(
                  context,
                  migrationResult.state == 'migrated'
                      ? 'migrationCompleted'
                      : 'migrationFailed',
                ),
              ),
            ),
          );
          if (controller == null) {
            _retryStorageResult(
              revision,
              () => _readStorageMigrationResult(session, revision),
            );
            return;
          }
          await _acknowledgeStorageResult(
            session,
            revision,
            migrationResult.nonce,
          );
          await controller.closed;
        },
      );
    }());
  }

  void _retryStorageResult(int revision, void Function() retry) {
    if (_disposed || revision != _hostRevision) return;
    _storageResultRetry?.cancel();
    _storageResultRetry = Timer(const Duration(seconds: 5), () {
      if (!_disposed && revision == _hostRevision) retry();
    });
  }

  Future<void> _acknowledgeStorageResult(
    BridgeClientSession session,
    int revision,
    String nonce,
  ) async {
    if (_disposed || revision != _hostRevision) return;
    try {
      await BridgeDataLocationResult(session).acknowledge(nonce);
    } on Object {
      // Retry only the receipt: the user has already seen the result.
      _retryStorageResult(
        revision,
        () => unawaited(_acknowledgeStorageResult(session, revision, nonce)),
      );
    }
  }

  Future<void> _connectHost(int revision) async {
    try {
      _startup.connecting();
      final lease = await _nativeHostConnector.open();
      if (_disposed || _exampleScene || revision != _hostRevision) {
        await lease.close();
        return;
      }
      _startup.readingPreferences();
      await _preferences.attachStore(BridgeAppPreferencesStore(lease.session));
      if (_disposed || _exampleScene || revision != _hostRevision) {
        _preferences.detachStore();
        await lease.close();
        return;
      }
      _hasConnectedHost = true;
      final nextComposition = AppComposition.forConnectedProduct(
        nativeHost: lease,
        preferences: _preferences,
        windowChrome: _windowChrome,
      );
      if (!mounted) {
        nextComposition.dispose();
        return;
      }
      setState(() {
        _composition = nextComposition;
      });
      _bindPrivacyFlow();
      _noticeFlow?.dispose();
      _noticeFlow =
          lease.session.hostCapabilities.contains('legal.testBuildNotice')
          ? TestBuildNoticeFlow(
              session: lease.session,
              queue: _prompts,
              ready: () => _promptReady,
              onExit: () => _handleCloseRequest(completelyExit: true),
              onChanged: _scheduleStartupChoice,
            )
          : null;
      _noticeFlow?.wake();
      _updateFlow?.dispose();
      _updateFlow = ApplicationUpdateFlow(
        session: lease.session,
        queue: _prompts,
        ready: () => _promptReady && revision == _hostRevision,
        canPresent: () =>
            !(_noticeFlow?.blocksPrompts ?? false) &&
            !(_privacyFlow?.blocksOptionalPrompt ?? false),
        shownVersions: _shownUpdateVersions,
      );
      _updateFlow?.wake();
      _readStorageMigrationResult(lease.session, revision);
      if (lease.session.hostCapabilities.contains(
        'applicationUpdates.firstFrameReady',
      )) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
          if (!mounted ||
              _disposed ||
              _exampleScene ||
              revision != _hostRevision ||
              !_hasConnectedHost) {
            return;
          }
          await reportUpdateStartupReceipt(
            lease.session,
            isCurrent: () =>
                mounted &&
                !_disposed &&
                !_exampleScene &&
                revision == _hostRevision &&
                _hasConnectedHost,
          );
        });
      }
      if (!_startup.complete) _observeStartupAccount(nextComposition.account);
      _finishStartupPreparation();
      unawaited(
        lease.terminated.then((termination) {
          _handleHostTermination(revision, termination);
        }),
      );
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Native Host connection failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!_disposed && !_exampleScene && revision == _hostRevision) {
        _startup.hostUnavailable();
        _preferences.detachStore();
        _scheduleReconnect();
      }
    }
  }

  void _handleHostTermination(int revision, NativeHostTermination termination) {
    if (kDebugMode) {
      debugPrint(
        'Native Host terminated: code=${termination.code} '
        'exitCode=${termination.exitCode}',
      );
    }
    if (_disposed ||
        _exampleScene ||
        revision != _hostRevision ||
        !_hasConnectedHost) {
      return;
    }
    _hostRevision++;
    _hasConnectedHost = false;
    _updateFlow?.dispose();
    _updateFlow = null;
    _privacyFlow?.dispose();
    _privacyFlow = null;
    _observeStartupAccount(null);
    _startup.hostUnavailable();
    _noticeFlow?.dispose();
    _noticeFlow = null;
    _preferences.detachStore();
    final nextComposition = _createProductComposition();
    if (mounted) {
      setState(() {
        _composition = nextComposition;
      });
    } else {
      nextComposition.dispose();
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _exampleScene || _reconnectTimer != null) {
      return;
    }
    _reconnectTimer = Timer(widget.reconnectDelay, () {
      _reconnectTimer = null;
      _requestHostConnection();
    });
  }

  AppComposition _createProductComposition() {
    return AppComposition.forProductShell(
      preferences: _preferences,
      windowChrome: _windowChrome,
    );
  }

  AppComposition _createExampleComposition() {
    final review = ShellReviewConfiguration.forExampleScene(widget.environment);
    return AppComposition.forShellReview(
      windowChrome: _windowChrome,
      preferences: InMemoryAppPreferences(initial: review.preferences),
      shellChrome: InMemoryShellChrome(initial: review.projection),
      accountPort: InMemoryAccountAdapter.forReview(review.accountState),
      personalProfilePort: InMemoryPersonalProfileAdapter.forReview(
        signedIn: review.accountState != AccountReviewState.signedOut,
      ),
      officialFleetPort: InMemoryOfficialFleetAdapter.forReview(
        signedIn: review.accountState != AccountReviewState.signedOut,
      ),
      officialFleetMembersPort: InMemoryOfficialFleetMembersAdapter.forReview(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _updateFlow?.dispose();
    _noticeFlow?.dispose();
    _navigationRequests.dispose();
    _privacyFlow?.dispose();
    _prompts.dispose();
    _storageResultRetry?.cancel();
    _hostRevision++;
    _reconnectTimer?.cancel();
    _preferences.projection.removeListener(_handlePreferencesChanged);
    _observeStartupAccount(null);
    _startup.removeListener(_handleStartupChanged);
    _startup.dispose();
    unawaited(_closeRequestSubscription?.cancel());
    if (_ownsApplicationLifecycle) {
      _applicationLifecycle.dispose();
    }
    _preferences.dispose();
    super.dispose();
  }
}
