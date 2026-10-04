import 'dart:async';

import '../../features/overlay_settings/overlay_workspace_module.dart';
import '../../features/overlay_settings/overlay_scene_controller.dart';
import 'menu_feature_session.dart';

final class MenuHudSession extends MenuFeatureSession {
  MenuHudSession(
    this.workspace,
    this.scenes,
    void Function(Map<String, Object?>) publish,
  ) : super(publish, const Stream.empty());
  final OverlayWorkspaceModule workspace;
  final OverlaySceneController? scenes;
  String notice = '';
  bool _toggling = false;
  int _intentEpoch = 0;
  String get _failureNotice {
    final language = workspace.runtimeLanguage.toLowerCase();
    if (!language.startsWith('zh')) {
      return 'Could not complete this action. Check the overlay settings in the client and try again.';
    }
    if (language.contains('tw') ||
        language.contains('hk') ||
        language.contains('hant')) {
      return '未完成，請檢查客戶端浮層設定後重試。';
    }
    return '未完成，请检查客户端浮层设置后重试。';
  }

  @override
  void show(bool value) {
    if (disposed || visible == value) return;
    visible = value;
    _intentEpoch++;
    if (value) {
      workspace.projection.addListener(_publishRuntime);
      _publishRuntime();
      unawaited(
        workspace
            .refreshRuntime(workspace.runtimeLanguage)
            .catchError((Object _) => false),
      );
    } else {
      workspace.projection.removeListener(_publishRuntime);
    }
  }

  void _publishRuntime() {
    if (!visible || disposed) return;
    final view = workspace.projection.value;
    emit({
      'state': view.runtime.available ? 'ready' : 'unavailable',
      'title': '信息浮层',
      'notice': notice,
      'busy': _toggling || view.runtimeBusy,
      'hudEnabled': view.runtime.available ? view.runtime.enabled : null,
    });
  }

  @override
  void act(String key, String value) {
    if (key != 'toggle' || value.isNotEmpty) return;
    if (!disposed && visible && !_toggling) unawaited(_toggle());
  }

  Future<void> _toggle() async {
    final epoch = _intentEpoch;
    _toggling = true;
    _publishRuntime();
    try {
      // The same primary workspace owns current state and open/close commands.
      // This direct button does not mount a HUD settings window or start a poller.
      final read = await workspace.refreshRuntime(workspace.runtimeLanguage);
      if (disposed || epoch != _intentEpoch) return;
      if (!read) {
        notice = _failureNotice;
        return;
      }
      if (workspace.projection.value.runtimeBusy) return;
      final result = workspace.projection.value.runtime.enabled
          ? await workspace.closeRuntime(workspace.runtimeLanguage)
          : await workspace.openRuntime(workspace.runtimeLanguage);
      if (disposed || epoch != _intentEpoch) return;
      notice = result ? '' : _failureNotice;
    } on Object {
      if (!disposed && epoch == _intentEpoch) notice = _failureNotice;
    } finally {
      _toggling = false;
      _publishRuntime();
    }
  }

  @override
  void reset() {
    notice = '';
  }

  @override
  Future<void> closePort() async {
    workspace.projection.removeListener(_publishRuntime);
  }

  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation;
    await workspace.refreshRuntime(workspace.runtimeLanguage);
    if (!current(epoch)) throw StateError('retired');
    final view = workspace.projection.value, runtime = view.runtime;
    return {
      'title': '信息浮层',
      'notice': notice,
      'busy': _toggling || view.runtimeBusy,
      'hudEnabled': runtime.available ? runtime.enabled : null,
    };
  }
}
