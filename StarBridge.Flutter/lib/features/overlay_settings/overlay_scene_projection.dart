import '../../app/shell/chrome/shell_chrome_projection.dart';
import 'overlay_scene_controller.dart';

OverlaySceneProjection projectOverlayScene(OverlaySceneState state) {
  final options = <OverlaySceneOption>[
    if (state.presetBindingId != null)
      const OverlaySceneOption(
        id: 'resumeBinding',
        labelKey: 'overlay.source.resumeBinding',
      ),
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
    if (state.preferredId == 'missing' ||
        state.preferredId.startsWith('org:') &&
            !state.targets.any((x) => state.preferredId == 'org:${x.code}'))
      OverlaySceneOption(
        id: state.preferredId,
        labelKey: 'overlay.source.missing',
        enabled: false,
      ),
    if (state.actualId == 'local')
      const OverlaySceneOption(
        id: 'local',
        labelKey: 'overlay.source.localName',
        enabled: false,
      ),
  ];
  return OverlaySceneProjection(
    options: options,
    preferredSceneId: state.preferredId,
    actualSceneId: state.actualId,
    canChange: state.available && !state.busy,
    selectionOrigin: state.temporarySourceId != null
        ? 'temporary'
        : state.presetBindingId != null
        ? 'preset'
        : 'account',
    fallbackReasonKey: state.busy
        ? 'overlay.source.saving'
        : state.status == 'ready'
        ? null
        : 'overlay.source.${state.status}',
  );
}
