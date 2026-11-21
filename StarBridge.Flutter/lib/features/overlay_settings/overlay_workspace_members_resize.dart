import 'overlay_workspace_layout_item.dart';
import 'overlay_workspace_projection.dart';
import 'overlay_workspace_rules.dart';
import 'overlay_workspace_schema.dart';

/// The members box's new size and placement as one draft: null when it does
/// not apply (no Members row, locked, another item). Throws on an invalid size.
OverlayWorkspaceProjection? overlayWorkspaceMembersResized(
  OverlayWorkspaceProjection current,
  int width,
  int height,
  OverlayWorkspaceLayoutItem item,
) {
  final index = current.layout.indexWhere((i) => i.key == 'Members');
  if (index < 0 || current.layout[index].isLocked || item.key != 'Members') {
    return null;
  }
  final settings = applyOverlayWorkspaceSettingChange(
    applyOverlayWorkspaceSettingChange(
      current.settings!,
      'visorMembersWidth',
      width,
    ),
    'visorMembersHeight',
    height,
  );
  final layout = List<OverlayWorkspaceLayoutItem>.of(current.layout)
    ..[index] = item;
  return current.copyWith(
    settings: settings,
    layout: List.unmodifiable(layout),
    clearFailure: true,
    dirty: true,
  );
}

/// Field kinds whose repeated changes merge into one undo step (sliders,
/// colours, event durations); a +/- button passes coalesce: false instead.
const overlayWorkspaceCoalescingKinds = {
  OverlayWorkspaceFieldKind.number,
  OverlayWorkspaceFieldKind.color,
  OverlayWorkspaceFieldKind.eventDurations,
};
