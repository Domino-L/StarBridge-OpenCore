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
  @override
  void reset() {
    notice = '';
  }

  @override
  Future<void> closePort() async {} // Borrowed client controllers.
  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation;
    await workspace.refreshRuntime('zh-CN');
    if (!current(epoch)) throw StateError('retired');
    final view = workspace.projection.value, runtime = view.runtime;
    return {
      'title': '信息浮层',
      'notice': notice,
      'rows': [
        {
          'title': runtime.isVisible ? '信息浮层已显示' : '信息浮层已隐藏',
          'detail': runtime.failed || !runtime.available
              ? '当前无法使用，请检查客户端的浮层设置后重试。'
              : '使用客户端已保存的布局与外观。',
        },
      ],
      'buttons': [
        if (!view.runtimeBusy && view.available)
          button(runtime.isVisible ? '关闭信息浮层' : '打开信息浮层', (_) async {
            final result = runtime.isVisible
                ? await workspace.closeRuntime('zh-CN')
                : await workspace.openRuntime('zh-CN');
            notice = result ? '' : '未完成，请检查客户端浮层设置后重试。';
          }),
        if (scenes?.projection.value.available == true) ...[
          button('自动选择协作场景', (_) async {
            await scenes!.select('auto');
          }),
          button('保持当前房间场景', (_) async {
            await scenes!.select('room');
          }),
          for (final target in scenes!.projection.value.targets)
            button('使用 ${target.name}', (_) async {
              await scenes!.select('org:${target.code}');
            }),
        ],
      ],
    };
  }
}
