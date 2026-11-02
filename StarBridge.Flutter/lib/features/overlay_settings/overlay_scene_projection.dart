import '../../app/shell/chrome/shell_chrome_projection.dart';
import 'overlay_scene_controller.dart';

OverlaySceneProjection projectOverlayScene(OverlaySceneState state) {
  // While the active plan fixes a source, choices would change nothing; the
  // only enabled action is to follow the shared choice again.
  final free = state.presetBindingId == null;
  final options = <OverlaySceneOption>[
    if (!free)
      const OverlaySceneOption(
        id: 'followShared',
        labelKey: 'overlay.source.followShared',
      ),
    OverlaySceneOption(
      id: 'auto',
      labelKey: 'overlay.source.auto',
      enabled: free,
    ),
    OverlaySceneOption(
      id: 'room',
      labelKey: 'overlay.source.room',
      enabled: free,
    ),
    if (state.offersFleet)
      OverlaySceneOption(
        id: 'fleet',
        labelKey: 'overlay.source.fleet',
        label: state.fleetName,
        enabled: free,
      ),
    for (final target in state.targets)
      OverlaySceneOption(
        id: 'org:${target.code}',
        labelKey: '',
        label: target.name,
        enabled: free,
      ),
    if (state.preferredId == 'missing' ||
        state.preferredId == 'fleet' && !state.offersFleet ||
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
        // A main fleet the viewer has left reads like an unavailable organization.
        : 'overlay.source.${state.status == 'notMember' ? 'unavailable' : state.status}',
  );
}
