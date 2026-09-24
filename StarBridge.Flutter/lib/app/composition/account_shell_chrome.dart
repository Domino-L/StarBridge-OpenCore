import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/account/account_module.dart';
import '../../features/game_log/game_log_controller.dart';
import '../../features/overlay_settings/overlay_scene_controller.dart';
import '../../features/overlay_settings/overlay_scene_projection.dart';
import '../shell/chrome/shell_chrome_port.dart';
import '../shell/chrome/shell_chrome_projection.dart';

final class AccountShellChrome implements ShellChromePort {
  AccountShellChrome({
    required ShellChromePort base,
    required AccountModule account,
    this._gamePresence,
    this._gameLog,
    this._gameVersion,
    this._appAway,
    this.scenes,
  }) : _base = base,
       _account = account,
       _projection = ValueNotifier(
         _combine(base.projection.value, account.projection.value),
       ) {
    _base.projection.addListener(_update);
    _account.projection.addListener(_update);
    _gamePresence?.addListener(_update);
    _gameLog?.addListener(_update);
    _appAway?.addListener(_update);
    scenes?.projection.addListener(_update);
    _update();
  }

  final ShellChromePort _base;
  final OverlaySceneController? scenes;
  final AccountModule _account;
  final ValueListenable<GamePresenceState>? _gamePresence;
  final ValueListenable<GameLogView>? _gameLog;
  final String? Function()? _gameVersion;
  final ValueListenable<bool>? _appAway;
  final ValueNotifier<ShellChromeProjection> _projection;

  @override
  ValueListenable<ShellChromeProjection> get projection => _projection;

  @override
  Future<SceneSelectionResult> selectOverlayScene(String sceneId) async =>
      scenes == null ? await _base.selectOverlayScene(sceneId) :
      await scenes!.select(sceneId) ? SceneSelectionResult.saved : SceneSelectionResult.rejected;

  void _update() {
    var next = _combine(_base.projection.value, _account.projection.value)
        .copyWith(
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
    _projection.value = next;
    if (scenes case final source?) {
      _projection.value = next.copyWith(overlay: projectOverlayScene(source.projection.value));
    }
  }

  void dispose() {
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
    AccountProjection account,
  ) {
    final signedIn = account.isSignedIn || account.isLegacyAccount;
    final accountLabel = signedIn
        ? account.profile?.displayName?.trim() ?? ''
        : '';
    final accountConnectionIssue = _accountConnectionIssue(account);
    final connectionIssue = base.connectionIssue ?? accountConnectionIssue;
    final connectionIssueUsesAccountAction = base.connectionIssue != null
        ? base.connectionIssueUsesAccountAction
        : accountConnectionIssue != null;
    final syncKey = base.connectionIssue != null
        ? base.syncKey
        : accountConnectionIssue?.state == ConnectionVisualState.stale
        ? 'sync.cached'
        : accountConnectionIssue != null || account.failure != null
        ? 'sync.issue'
        : base.syncKey;
    return base.copyWith(
      accountLabel: accountLabel,
      accountAvatarImageData: account.profile?.avatarImageData,
      clearAccountAvatar: !signedIn || account.profile?.avatarImageData == null,
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
        account.profileFreshness == AccountProfileFreshness.cached) {
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
