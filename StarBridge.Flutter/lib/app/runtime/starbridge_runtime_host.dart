import 'dart:async';

import '../../platform/window/method_channel_menu_preview_window.dart';

import '../../features/settings/notification_editor_frame.dart';

import '../routing/exit_application_intent.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/account/account_module.dart';
import '../../features/communities/community_hangar_sharing_port.dart';
import '../../features/overlay_settings/overlay_settings_feature.dart';
import '../../platform/host/native_host_connector.dart';
import '../../platform/host/native_host_session_connector.dart';
import '../../platform/host/windows_native_host_platform.dart';
import '../../platform/lifecycle/application_lifecycle_port.dart';
import '../../platform/lifecycle/method_channel_application_lifecycle.dart';
import '../../platform/window/method_channel_window_chrome.dart';
import '../../platform/window/window_chrome_port.dart';
import '../bootstrap/starbridge_app.dart';
import '../composition/app_composition.dart';
import '../localization/app_strings.dart';
import '../preferences/app_preferences.dart';
import '../preferences/app_preferences_module.dart';
import '../preferences/app_preferences_projection.dart';
import '../preferences/bridge_app_preferences.dart';
import '../startup/startup_session.dart';
import '../startup/startup_first_content.dart';
import '../startup/startup_readiness_binding.dart';
import 'application_behavior_prompt.dart';
import 'application_lifecycle_prompts.dart';
import 'example_scene_control.dart';
import 'runtime_example_composition.dart';
import 'startup_prompt_queue.dart';
import 'first_use_privacy_flow.dart';
import 'test_build_notice_flow.dart';
import 'update_startup_receipt.dart';
import 'application_update_flow.dart';
import 'menu_tool_page_navigation.dart';
import '../routing/open_destination_intent.dart';
import '../../features/settings/local_privacy_page.dart';
import 'storage_result_flow.dart';
import 'storage_result_retry.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

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
  final MenuWindowLifetime _menuLifetime = MenuWindowLifetime();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final StartupSession _startup = StartupSession();
  late final WindowChromePort _windowChrome;
  late final NativeHostConnector _nativeHostConnector;
  late final ApplicationLifecyclePort _applicationLifecycle;
  late final bool _ownsApplicationLifecycle;
  StreamSubscription<void>? _closeRequestSubscription;
  late final AppPreferencesModule _preferences;
  late AppComposition _composition;
  StartupReadinessBinding? _startupReads;
  bool _exampleScene = false;
  bool _disposed = false;
  bool _hasConnectedHost = false;
  int _hostRevision = 0;
  Future<void>? _connectionAttempt;
  Timer? _reconnectTimer;
  late final _storageResultRetry = StorageResultRetry(
    current: (revision) => !_disposed && revision == _hostRevision,
  );
  late final _storageResult = StorageMigrationResultFlow(
    retry: _storageResultRetry,
    prompts: _prompts,
    isCurrent: (revision) => !_disposed && revision == _hostRevision,
    ready: () => _promptReady,
    context: () => _navigatorKey.currentContext,
  );
  bool _handlingCloseRequest = false;
  bool _startupChoiceVisible = false;
  // "稍后再说": ask again on the next launch, not again in this session.
  bool _behaviorPromptDeferred = false;
  late final StartupPromptQueue _prompts;
  FirstUsePrivacyFlow? _privacyFlow;
  TestBuildNoticeFlow? _noticeFlow;
  ApplicationUpdateFlow? _updateFlow;
  final _shownUpdateVersions = <String>{};
  final _navigationRequests = ValueNotifier<OpenDestinationIntent?>(null);
  late final VoidCallback _unbindToolPages;

  bool get _promptReady =>
      !_disposed &&
      mounted &&
      _startup.complete &&
      !_handlingCloseRequest &&
      !_exampleScene &&
      _hasConnectedHost;

  void _bindPrivacyFlow({BridgeClientSession? session}) {
    _navigationRequests.value = null;
    _privacyFlow?.dispose();
    final privacy = _composition.localPrivacy;
    _privacyFlow = privacy == null
        ? null
        : FirstUsePrivacyFlow(
            account: _composition.account,
            eventSession: session,
            membershipChanges: _composition.communities,
            hangarSharing:
                _composition.communities.port is CommunityHangarSharingPort
                ? _composition.communities.port as CommunityHangarSharingPort
                : null,
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
    _menuLifetime.execHangarRequests.addListener(_openMenuExecHangar);
    _unbindToolPages = bindMenuToolPages(_menuLifetime, _navigationRequests);
    _preferences.projection.addListener(_handlePreferencesChanged);
    _startup.addListener(_handleStartupChanged);
    _closeRequestSubscription = _applicationLifecycle.closeRequests.listen(
      (_) => unawaited(_handleCloseRequest()),
    );
    _requestHostConnection();
  }

  void _openMenuExecHangar() {
    if (!_disposed && mounted) {
      _navigationRequests.value = const OpenDestinationIntent(
        '/tools/exec-hangar',
      );
    }
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
    _startupReads?.dispose();
    _startupReads = account == null
        ? null
        : StartupReadinessBinding(
            account: account,
            mode: _composition.manualPresence?.connectionMode,
            firstContent: startupFirstContent(_composition),
            current: () =>
                !_disposed &&
                !_exampleScene &&
                _hasConnectedHost &&
                !_startup.complete &&
                identical(account, _composition.account),
            onChanged: _finishStartupPreparation,
          );
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

  late final _firstUseHold = FirstUseChoiceHold(_scheduleStartupChoice);
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
    if (confirmed == null ||
        _behaviorPromptDeferred ||
        _behaviorChosen(confirmed.applicationBehavior)) {
      return;
    }
    _prompts.enqueue(
      'startup-choice',
      priority: 200,
      eligible: () =>
          _promptReady &&
          !(_noticeFlow?.blocksPrompts ?? false) &&
          !_firstUseHold.active &&
          !_startupChoiceVisible &&
          !(_privacyFlow?.blocksOptionalPrompt ?? false) &&
          !_behaviorPromptDeferred &&
          _behaviorPending(),
      show: _showStartupChoice,
    );
  }

  static bool _behaviorChosen(ApplicationBehaviorPreferences behavior) =>
      behavior.startupChoiceMade && behavior.closeBehaviorChoiceMade;
  bool _behaviorPending() {
    final behavior =
        _preferences.projection.value.confirmed?.applicationBehavior;
    return behavior != null && !_behaviorChosen(behavior);
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
        _behaviorPromptDeferred ||
        _behaviorChosen(confirmed.applicationBehavior)) {
      if (navigatorContext == null && confirmed != null) {
        _scheduleStartupChoice();
      }
      return;
    }

    _startupChoiceVisible = true;
    try {
      // Existing users: one prompt for whichever of the two was never chosen.
      final saved = await showApplicationBehaviorPrompt(
        navigatorContext,
        _preferences,
      );
      if (!saved) _behaviorPromptDeferred = true;
    } finally {
      _startupChoiceVisible = false;
    }
  }

  Future<void> _handleCloseRequest({
    bool completelyExit = false,
    bool decliningTerms = false,
    Future<bool> Function()? beforeExit,
  }) async {
    if (_handlingCloseRequest || !mounted) {
      return;
    }
    _handlingCloseRequest = true;
    try {
      if (_prompts.hasBlockingRoute &&
          !(decliningTerms &&
              completelyExit &&
              _noticeFlow?.ownsCurrentRoute == true)) {
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
        await _menuLifetime.completeExit();
        await _applicationLifecycle.exitApplication();
        return;
      }
      final projection = _preferences.projection.value;
      final confirmed = projection.confirmed;
      if (confirmed == null) {
        await _menuLifetime.completeExit();
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
              starBridgeTimedSnackBar(
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
        await _menuLifetime.completeExit();
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
              intent.runWithSource(
                () => _handleCloseRequest(
                  completelyExit: true,
                  beforeExit: intent.beforeExit,
                ),
              ),
            );
            return null;
          },
        ),
      },
      child: StarBridgeApp(
        taskbarAttentionScope: _menuLifetime.taskbarAttentionScope,
        key: ObjectKey(_composition),
        navigatorKey: _navigatorKey,
        navigatorObservers: [_prompts],
        promptQueue: _prompts,
        canPresentIdentityPrompt: () =>
            _promptReady && !(_noticeFlow?.blocksPrompts ?? false),
        usageTermsPending: _noticeFlow?.blocksPrompts ?? false,
        onFirstUseOwnsDeviceChoices: _firstUseHold.set,
        navigationRequests: _navigationRequests,
        composition: _composition,
        // 调试用：STARBRIDGE_HOLIDAY_PREVIEW=xmas 启动即预览圣诞外观，不用改系统日期。
        initialHolidayPreview: widget.environment['STARBRIDGE_HOLIDAY_PREVIEW'],
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
    if (_preferences.projection.value.phase != AppPreferencesPhase.ready) {
      _startup.readingPreferences();
      await _preferences.retry();
    } else {
      _startup.readingAccount();
      await _startupReads?.retry();
    }
    if (!_disposed &&
        !_exampleScene &&
        _hasConnectedHost &&
        revision == _hostRevision) {
      _finishStartupPreparation();
    }
  }

  void _finishStartupPreparation() => _startup.resolvePreparation(
    preferencesConfirmed:
        _preferences.projection.value.phase == AppPreferencesPhase.ready,
    account: _composition.account.projection.value,
    connectionMode: _composition.manualPresence?.connectionMode,
    firstContentSettled: _startupReads?.firstContentSettled ?? true,
  );

  Future<void> _connectHost(int revision) async {
    try {
      _startup.connecting();
      final lease = await _nativeHostConnector.open();
      if (_disposed || _exampleScene || revision != _hostRevision) {
        await lease.close();
        return;
      }
      _startup.readingPreferences();
      await _menuLifetime.prepareStartup(lease.session);
      await _preferences.attachStore(BridgeAppPreferencesStore(lease.session));
      if (_disposed || _exampleScene || revision != _hostRevision) {
        _preferences.detachStore();
        await lease.close();
        return;
      }
      _hasConnectedHost = true;
      final nextComposition = AppComposition.forConnectedProduct(
        menuLifetime: _menuLifetime,
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
      _bindPrivacyFlow(session: lease.session);
      _noticeFlow?.dispose();
      _noticeFlow =
          lease.session.hostCapabilities.contains('legal.testBuildNotice')
          ? TestBuildNoticeFlow(
              session: lease.session,
              queue: _prompts,
              ready: () => _promptReady,
              onExit: () => _handleCloseRequest(
                completelyExit: true,
                decliningTerms: true,
              ),
              onChanged: () {
                if (mounted && !_disposed) setState(() {});
                _scheduleStartupChoice();
              },
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
      _storageResult.read(lease.session, revision);
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
      menuLifetime: _menuLifetime,
      preferences: _preferences,
      windowChrome: _windowChrome,
    );
  }

  AppComposition _createExampleComposition() => createRuntimeExampleComposition(
    environment: widget.environment,
    menuLifetime: _menuLifetime,
    windowChrome: _windowChrome,
  );

  @override
  void dispose() {
    _disposed = true;
    _updateFlow?.dispose();
    _noticeFlow?.dispose();
    _unbindToolPages();
    _navigationRequests.dispose();
    _menuLifetime.execHangarRequests.removeListener(_openMenuExecHangar);
    _menuLifetime.execHangarRequests.dispose();
    _privacyFlow?.dispose();
    _prompts.dispose();
    _storageResultRetry.dispose();
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
