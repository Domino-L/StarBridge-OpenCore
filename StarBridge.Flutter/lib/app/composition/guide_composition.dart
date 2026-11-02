import '../../features/onboarding/connection_mode_port.dart';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../shared/guide/guide_controller.dart';
import '../../shared/guide/guide_scope.dart';
import '../../shared/guide/guide_state_adapters.dart';
import '../shell/chrome/shell_chrome_projection.dart';
import 'app_composition.dart';
import 'guide_windows_notice_binding.dart';

/// Wires the in-app guide to Host (`guide.state.v1`). Without the capability
/// the hub still exists but stays silent: no tips, tours or checklist.
final class GuideBinding {
  GuideBinding._(this.hub, this._release);
  final GuideHub hub;
  final VoidCallback _release;

  static GuideBinding? compose(
    AppComposition composition, {
    required void Function(String route) navigate,
  }) {
    final session = composition.firstUseSession;
    if (session == null) return null;
    final port = BridgeGuideState(session);
    if (!port.supported) return null;
    final account = composition.account.projection;
    final chrome = composition.shellChrome.projection;
    // Re-read per account/profile switch, not on every account refresh.
    final context = ValueNotifier<(int, AccountSessionState)>((
      account.value.generation,
      account.value.sessionState,
    ));
    void follow() =>
        context.value = (account.value.generation, account.value.sessionState);
    account.addListener(follow);
    final online = ValueNotifier(chrome.value.accountSignedIn);
    final mode = composition.manualPresence?.connectionMode;
    bool isLocal() => mode?.snapshot.state == ConnectionModeState.local;
    final local = ValueNotifier(isLocal());
    void modeChanged() => local.value = isLocal();
    mode?.addListener(modeChanged);
    final controller = GuideController(port, reload: context);
    void game() {
      online.value = chrome.value.accountSignedIn;
      if (chrome.value.gamePresence == GamePresenceState.running) {
        controller.markDone('recognize');
      }
    }

    chrome.addListener(game);
    final notice = GuideWindowsNoticeBinding(
      composition.notificationSettings,
      composition.desktopNotifications,
    );
    final hub = GuideHub(
      controller: controller,
      online: online,
      navigate: navigate,
      localMode: local,
      windowsNotice: notice,
    );
    return GuideBinding._(hub, () {
      account.removeListener(follow);
      chrome.removeListener(game);
      mode?.removeListener(modeChanged);
      hub.dispose();
      notice.dispose();
      controller.dispose();
      online.dispose();
      local.dispose();
      context.dispose();
    });
  }

  void dispose() => _release();
}
