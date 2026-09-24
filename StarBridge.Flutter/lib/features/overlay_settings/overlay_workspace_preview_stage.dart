import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_runtime_card.dart';
import 'overlay_workspace_runtime_projection.dart';

class OverlayWorkspacePreviewStage extends StatelessWidget {
  const OverlayWorkspacePreviewStage({
    required this.projection,
    this.fullscreenButton,
    this.editorCanvas,
    super.key,
  });

  final OverlayWorkspaceProjection projection;
  final Widget? fullscreenButton;
  final Widget? editorCanvas;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final visibility = OverlayWorkspaceRuntimeProjection.resolveVisibility(
      projection.settings!,
      noticeHasContent: true,
      chatHasContent: true,
      eventNotificationsHaveContent: true,
    );
    final visibleCount =
        projection.layout
            .where((item) => visibility.isLayoutModuleVisible(item.key))
            .length +
        (visibility.showCrosshair ? 1 : 0) +
        (visibility.showEventNotifications ? 1 : 0);
    return StarBridgeSurface(
      key: const Key('overlay-preview-stage'),
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space.md,
              vertical: tokens.space.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaces.chrome.fill,
              border: Border(
                bottom: BorderSide(color: tokens.surfaces.panel.border),
              ),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 28, color: tokens.colors.accent),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _copy(context, 'overlay.preview.stageTitle'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        _copy(context, 'overlay.preview.reference'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.colors.textSecondary,
                          fontFamily: tokens.typography.monoFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                if (fullscreenButton != null)
                  fullscreenButton!
                else
                  Text(
                    _copy(
                      context,
                      'overlay.preview.visibleCount',
                    ).replaceAll('{count}', visibleCount.toString()),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.colors.accent,
                      fontFamily: tokens.typography.monoFamily,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(tokens.space.md),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const ratio = 16 / 9;
                  final availableRatio =
                      constraints.maxWidth / constraints.maxHeight;
                  final width = availableRatio > ratio
                      ? constraints.maxHeight * ratio
                      : constraints.maxWidth;
                  final height = width / ratio;
                  return Center(
                    child: SizedBox(
                      width: width,
                      height: height,
                      child:
                          editorCanvas ??
                          OverlayWorkspaceRuntimePreview(
                            projection: projection,
                          ),
                    ),
                  );
                },
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space.md,
              vertical: tokens.space.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaces.status.fill,
              border: Border(
                top: BorderSide(color: tokens.surfaces.panel.border),
              ),
            ),
            child: Row(
              children: [
                StarBridgeIcon(
                  projection.dirty
                      ? StarBridgeIconSemantic.edit
                      : StarBridgeIconSemantic.connected,
                  size: 15,
                  color: projection.dirty
                      ? tokens.colors.warning
                      : tokens.colors.success,
                ),
                SizedBox(width: tokens.space.xs),
                Expanded(
                  child: Text(
                    _copy(
                      context,
                      projection.dirty
                          ? 'overlay.preview.draft'
                          : 'overlay.preview.saved',
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
