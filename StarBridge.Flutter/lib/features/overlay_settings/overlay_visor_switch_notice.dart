import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// One-time line for users of the earlier overlay: 0.7.3 overlay v2 keeps its
/// own storage and starts from defaults (user, 11-07: "我觉得需要把之前浮层存的
/// 全部重置掉，这完全是一个新的东西了").
class OverlayVisorSwitchNotice extends StatelessWidget {
  const OverlayVisorSwitchNotice({required this.onClose, super.key});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    String copy(String cn, String tw, String en) {
      final locale = Localizations.localeOf(context);
      return locale.languageCode != 'zh'
          ? en
          : locale.scriptCode == 'Hant' || locale.countryCode == 'TW'
          ? tw
          : cn;
    }

    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space.sm),
      child: Material(
        key: const Key('overlay-visor-switch-notice'),
        color: tokens.surfaces.floating.fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.space.md,
            tokens.space.xs,
            tokens.space.xs,
            tokens.space.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  copy(
                    '浮层升级到新版，设置已恢复默认',
                    '浮層升級到新版，設定已恢復預設',
                    'The overlay has been upgraded. Its settings are back to defaults.',
                  ),
                ),
              ),
              StarBridgeActionButton(
                key: const Key('overlay-visor-switch-notice-close'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => onClose(),
                child: Text(copy('知道了', '知道了', 'Got it')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells the Host the one-time upgrade line has been shown.
abstract interface class OverlayVisorNoticePort {
  Future<void> dismissVisorNotice();
}

/// 0.7.3 one-time upgrade line. Shown once the Host reports it. Reading changes
/// nothing on disk: only the user's "知道了" tells the Host, which then writes
/// its marker in the overlay v2 folder, and the page reads the workspace again. With unsaved edits open (or a save
/// running) the confirmation waits: once the page is idle again, after that
/// save or after the edits are discarded, the Host is told and the page reads
/// again, so the confirmation never races a save and is never lost.
final class OverlayVisorNoticeState {
  OverlayVisorNoticeState(this._port, this._module) {
    _module.projection.addListener(_confirmWhenIdle);
  }
  final OverlayVisorNoticePort? _port;
  final OverlayWorkspaceModule _module;
  final _visible = ValueNotifier(false);
  bool _seen = false, _disposed = false, _confirmPending = false;
  ValueListenable<bool> get visible => _visible;

  void note(OverlayWorkspaceSnapshot snapshot) {
    if (_disposed || !snapshot.visorSwitchNotice || _seen || _port == null) {
      return;
    }
    _seen = true;
    _visible.value = true;
  }

  void close() {
    if (_disposed) return;
    _visible.value = false;
    if (_port == null) return;
    _confirmPending = true;
    _confirmWhenIdle();
  }

  void _confirmWhenIdle() {
    final port = _port, projection = _module.projection.value;
    if (_disposed || !_confirmPending || port == null) return;
    if (projection.dirty || projection.busy) return;
    _confirmPending = false;
    unawaited(
      port.dismissVisorNotice().then(
        (_) => _disposed ? null : _module.refresh(),
        onError: (Object _) {},
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _module.projection.removeListener(_confirmWhenIdle);
    _visible.dispose();
  }
}
