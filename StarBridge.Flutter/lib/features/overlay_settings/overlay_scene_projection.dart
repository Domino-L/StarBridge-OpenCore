import '../../app/shell/chrome/shell_chrome_projection.dart';
import 'overlay_scene_controller.dart';

OverlaySceneProjection projectOverlayScene(OverlaySceneState state) {
  final options = <OverlaySceneOption>[
    const OverlaySceneOption(id: 'auto', labelKey: 'overlay.source.auto'),
    const OverlaySceneOption(id: 'room', labelKey: 'overlay.source.room'),
    const OverlaySceneOption(
      id: 'fleet',
      labelKey: 'overlay.source.fleet',
      enabled: false,
    ),
    for (final target in state.targets)
      OverlaySceneOption(
        id: 'org:${target.code}',
        labelKey: '',
        label: target.name,
      ),
    if (state.mode == 'community' &&
        !state.targets.any((x) => x.code == state.code))
      OverlaySceneOption(
        id: state.preferredId,
        labelKey: 'overlay.source.missing',
        enabled: false,
      ),
  ];
  return OverlaySceneProjection(
    options: options,
    preferredSceneId: state.preferredId,
    actualSceneId: state.actualId,
    canChange: state.available && !state.busy,
    fallbackReasonKey: state.busy
        ? 'overlay.source.saving'
        : state.status == 'ready'
        ? null
        : 'overlay.source.${state.status}',
  );
}
