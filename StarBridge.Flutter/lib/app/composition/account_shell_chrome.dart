import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/account/account_module.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../../features/game_log/game_log_controller.dart';
import '../../features/overlay_settings/overlay_scene_controller.dart';
import '../../features/overlay_settings/overlay_scene_projection.dart';
import '../../features/overlay_settings/overlay_settings_module.dart';
import '../shell/chrome/shell_chrome_port.dart';
import '../shell/chrome/shell_chrome_projection.dart';
import 'overlay_appearance_qualification_binding.dart';
import '../../shared/release/official_client_profile.dart';

final class AccountShellChrome implements ShellChromePort {
  AccountShellChrome({
    required ShellChromePort base,
    required AccountModule account,
    this._gamePresence,
    this._gameLog,
    this._gameVersion,
    this._appAway,
    OverlaySceneController? scenes,
    OverlaySettingsModule? overlay,
  }) : _base = base,
       _account = account,
       scenes = scenes ?? overlay?.scenes,
       _overlay = overlay,
       _projection = ValueNotifier(
         _combine(base.projection.value, account.projection.value),
       ) {
    _base.projection.addListener(_update);
    _account.projection.addListener(_update);
    _gamePresence?.addListener(_update);
    _gameLog?.addListener(_update);
    _appAway?.addListener(_update);
    this.scenes?.projection.addListener(_update);
    _update();
  }

  final ShellChromePort _base;
  final OverlaySceneController? scenes;
  final OverlaySettingsModule? _overlay;
  final AccountModule _account;
  final ValueListenable<GamePresenceState>? _gamePresence;
  final ValueListenable<GameLogView>? _gameLog;
  final String? Function()? _gameVersion;
  final ValueListenable<bool>? _appAway;
  final ValueNotifier<ShellChromeProjection> _projection;
  ConnectionModeControl? _mode;
  void observeConnectionMode(ConnectionModeControl? mode) {
    if (!OfficialClientProfile.connectionModes) return;
    if (identical(mode, _mode)) return;
    _mode?.removeListener(_update);
    _mode = mode;
    _mode?.addListener(_update);
    _update();
  }

  @override
  ValueListenable<ShellChromeProjection> get projection => _projection;

  @override
  Future<SceneSelectionResult> selectOverlayScene(String sceneId) async =>
      scenes == null
      ? await _base.selectOverlayScene(sceneId)
      : await scenes!.select(sceneId)
      ? SceneSelectionResult.saved
      : SceneSelectionResult.rejected;

  void _update() {
    final account = _account.projection.value;
    _overlay?.workspace?.setAppearanceQualificationUnknown(
      overlayAppearanceQualificationUnknown(
        account.sessionState,
        _mode?.snapshot,
      ),
    );
    final localMode = _mode?.snapshot.state;
    final paused =
        _mode?.failed == false &&
        (localMode == ConnectionModeState.offline ||
            localMode == ConnectionModeState.local) &&
        account.failure?.code == 'account.local_mode';
    final pendingRecovery =
        _mode?.failed == false &&
        _mode?.snapshot.needsOnlineRecovery == true &&
        account.failure?.code == 'account.local_mode';
    var next =
        _combine(
          _base.projection.value,
          account,
          accountPaused: paused,
          pendingRecovery: pendingRecovery,
        ).copyWith(
          gamePresence: _gamePresence?.value,
          gameVersion: _gamePresence?.value == GamePresenceState.running
              ? _gameLog?.value.confirmedVersion ?? _gameVersion?.call()
              : null,
          clearGameVersion: _gamePresence?.value != GamePresenceState.running,
        );
    if (_appAway?.value == true &&
        next.presenceKey == 'presence.online' &&
        next.gamePresence != GamePresenceState.running) {
      next = next.copyWith(presenceKey: 'presence.away');
    }
    final retained = _mode?.snapshot.offlineAccount;
    if (_mode?.failed == false &&
        localMode == ConnectionModeState.offline &&
        retained != null) {
      next = next.copyWith(
        accountLabel: retained.displayName,
        presenceKey: 'presence.offline',
        accountAvatarImageData: retained.avatarImageData,
        clearAccountAvatar: retained.avatarImageData == null,
      );
    }
    if (scenes case final source?) {
      next = next.copyWith(
        overlay: projectOverlayScene(source.projection.value),
      );
    }
    _projection.value = next;
  }

  void dispose() {
    _mode?.removeListener(_update);
    scenes?.projection.removeListener(_update);
    _gamePresence?.removeListener(_update);
    _gameLog?.removeListener(_update);
    _appAway?.removeListener(_update);
    _base.projection.removeListener(_update);
    _account.projection.removeListener(_update);
    _projection.dispose();
  }

  static ShellChromeProjection _combine(
    ShellChromeProjection base,
    AccountProjection account, {
    bool accountPaused = false,
    bool pendingRecovery = false,
  }) {
    final signedIn = account.isSignedIn || account.isLegacyAccount;
    final retainedDisplay =
        (account.isPreparingDisplay ||
            account.hasDisplayHandoff ||
            account.sessionState ==
                AccountSessionState.credentialTemporarilyUnavailable) &&
        account.profileFreshness == AccountProfileFreshness.cached &&
        account.cachedAt != null;
    final accountLabel = signedIn || retainedDisplay
        ? account.profile?.displayName?.trim() ?? ''
        : '';
    final accountConnectionIssue = accountPaused
        ? null
        : pendingRecovery
        ? const ConnectionIssueProjection(
            domain: ConnectionStatusDomain.identity,
            titleKey: 'connection.account.restorePending.title',
            detailKey: 'connection.account.restorePending.detail',
            state: ConnectionVisualState.limited,
            action: ConnectionIssueAction.restoreOnline,
          )
        : _accountConnectionIssue(account);
    final connectionIssue = base.connectionIssue ?? accountConnectionIssue;
    final connectionIssueUsesAccountAction = base.connectionIssue != null
        ? base.connectionIssueUsesAccountAction
        : accountConnectionIssue != null &&
              accountConnectionIssue.action !=
                  ConnectionIssueAction.restoreOnline;
    final syncKey = base.connectionIssue != null
        ? base.syncKey
        : account.isPreparingDisplay
        ? 'sync.cached'
        : accountConnectionIssue?.state == ConnectionVisualState.stale
        ? 'sync.cached'
        : accountConnectionIssue != null ||
              account.failure != null && !accountPaused
        ? 'sync.issue'
        : base.syncKey;
    return base.copyWith(
      accountLabel: accountLabel,
      accountAvatarImageData: account.profile?.avatarImageData,
      clearAccountAvatar:
          !(signedIn || retainedDisplay) ||
          account.profile?.avatarImageData == null,
      presenceKey:
          account.sessionState == AccountSessionState.loading ||
              account.sessionState ==
                  AccountSessionState.credentialTemporarilyUnavailable
          ? 'presence.unknown'
          : !signedIn
          ? 'presence.offline'
          : connectionIssue != null ||
                account.sessionState == AccountSessionState.legacyUnavailable
          ? 'presence.unknown'
          : 'presence.online',
      syncKey: account.isLegacyAccount
          ? 'account.legacySession.status'
          : syncKey,
      accountSignedIn: signedIn,
      accountIdentityUnconfirmed:
          pendingRecovery ||
          account.isPreparingDisplay ||
          account.sessionState ==
              AccountSessionState.credentialTemporarilyUnavailable,
      accountBusy: account.isBusy,
      connectionIssue: connectionIssue,
      clearConnectionIssue: connectionIssue == null,
      connectionIssueUsesAccountAction: connectionIssueUsesAccountAction,
      accountIssue: accountConnectionIssue,
      clearAccountIssue: accountConnectionIssue == null,
    );
  }

  static ConnectionIssueProjection? _accountConnectionIssue(
    AccountProjection account,
  ) {
    if (account.isLegacyAccount &&
        account.failure?.code == 'account.optional_scm_failed') {
      return null;
    }
    if (account.sessionState ==
        AccountSessionState.credentialTemporarilyUnavailable) {
      return const ConnectionIssueProjection(
        domain: ConnectionStatusDomain.network,
        titleKey: 'connection.account.unavailable.title',
        detailKey: 'connection.account.unavailable.detail',
        state: ConnectionVisualState.disconnected,
      );
    }
    if (account.sessionState == AccountSessionState.reauthorizationRequired) {
      return const ConnectionIssueProjection(
        domain: ConnectionStatusDomain.identity,
        titleKey: 'connection.account.reauthorize.title',
        detailKey: 'connection.account.reauthorize.detail',
        state: ConnectionVisualState.limited,
      );
    }
    if (account.sessionState == AccountSessionState.signedIn &&
        account.profileFreshness == AccountProfileFreshness.cached &&
        account.failure != null) {
      return const ConnectionIssueProjection(
        domain: ConnectionStatusDomain.network,
        titleKey: 'connection.account.cached.title',
        detailKey: 'connection.account.cached.detail',
        state: ConnectionVisualState.stale,
      );
    }
    if (account.failure case final failure?) {
      return ConnectionIssueProjection(
        domain: ConnectionStatusDomain.network,
        titleKey: 'connection.account.actionFailed.title',
        detailKey: failure.messageKey,
        state: failure.retryable
            ? ConnectionVisualState.limited
            : ConnectionVisualState.disconnected,
      );
    }
    return null;
  }
}
