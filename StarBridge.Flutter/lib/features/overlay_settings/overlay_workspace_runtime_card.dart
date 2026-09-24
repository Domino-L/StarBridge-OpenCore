import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_layout_editor.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

class OverlayWorkspaceRuntimeCard extends StatelessWidget {
  const OverlayWorkspaceRuntimeCard({
    required this.projection,
    required this.onAction,
    this.showPreview = false,
    this.fullscreenButton,
    this.editorCanvas,
    super.key,
  });

  final OverlayWorkspaceProjection projection;
  final VoidCallback onAction;
  final bool showPreview;
  final Widget? fullscreenButton;
  final Widget? editorCanvas;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final runtime = projection.runtime;
    final isOpen = runtime.windowState == 'open';
    final isFailed = runtime.windowState == 'failed';
    final isUnavailable = runtime.windowState == 'unavailable';
    final accent = isFailed || isUnavailable
        ? tokens.colors.warning
        : isOpen
        ? tokens.colors.success
        : tokens.colors.accent;
    final titleKey = projection.runtimeBusy
        ? switch (projection.runtimeOperation) {
            OverlayRuntimeOperation.opening => 'overlay.runtime.opening',
            OverlayRuntimeOperation.closing => 'overlay.runtime.closing',
            OverlayRuntimeOperation.retrying => 'overlay.runtime.retrying',
            _ => 'overlay.runtime.checking',
          }
        : switch (runtime.windowState) {
            'open' => 'overlay.runtime.open',
            'failed' => 'overlay.runtime.failed',
            'unavailable' => 'overlay.runtime.unavailable',
            _ => 'overlay.runtime.closed',
          };
    final descriptionKey = switch (runtime.windowState) {
      'open' => 'overlay.runtime.openDescription',
      'failed' => _runtimeFailureDescription(runtime.failureCode),
      'unavailable' => _runtimeFailureDescription(runtime.failureCode),
      _ => 'overlay.runtime.closedDescription',
    };
    final actionKey = switch (runtime.windowState) {
      'open' => 'overlay.runtime.closeAction',
      'failed' => 'overlay.runtime.retryAction',
      'unavailable' => 'overlay.runtime.checkAction',
      _ => 'overlay.runtime.openAction',
    };

    return StarBridgeSurface(
      key: const Key('overlay-runtime-card'),
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: tokens.shape.small,
                    ),
                    child: projection.runtimeBusy
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : StarBridgeIcon(
                            StarBridgeIconSemantic.overlay,
                            color: accent,
                          ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _copy(context, titleKey),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: tokens.space.xs),
                        Text(
                          _copy(context, descriptionKey),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.sm),
              Wrap(
                spacing: tokens.space.lg,
                runSpacing: tokens.space.xs,
                children: [
                  Text(
                    _copy(
                      context,
                      'overlay.runtime.hotkey.${runtime.hotkeyState}',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    _copy(
                      context,
                      'overlay.runtime.follow.${runtime.followGameState}',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (runtime.usedFallbackSkin) ...[
                SizedBox(height: tokens.space.sm),
                Text(
                  _copy(context, 'overlay.runtime.skinFallback'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.colors.warning),
                ),
              ],
            ],
          );
          final action = FilledButton(
            key: const Key('overlay-runtime-action'),
            onPressed: projection.busy ? null : onAction,
            child: Text(_copy(context, actionKey)),
          );
          if (showPreview) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                SizedBox(height: tokens.space.md),
                action,
                if (fullscreenButton != null) ...[
                  SizedBox(height: tokens.space.sm),
                  fullscreenButton!,
                ],
                SizedBox(height: tokens.space.md),
                Divider(color: tokens.surfaces.panel.border, height: 1),
                SizedBox(height: tokens.space.md),
                Text(
                  _copy(context, 'overlay.runtime.previewTitle'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(height: tokens.space.xs),
                Text(
                  _copy(context, 'overlay.runtime.previewDescription'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                SizedBox(height: tokens.space.sm),
                editorCanvas ??
                    OverlayWorkspaceRuntimePreview(projection: projection),
              ],
            );
          }
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                SizedBox(height: tokens.space.md),
                action,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: details),
              SizedBox(width: tokens.space.lg),
              action,
            ],
          );
        },
      ),
    );
  }

  static String _runtimeFailureDescription(String? code) => switch (code) {
    'overlay.runtime_start_timeout' => 'overlay.runtime.timeoutDescription',
    'overlay.runtime_permission_denied' =>
      'overlay.runtime.permissionDescription',
    _ => 'overlay.runtime.failedDescription',
  };
}

/// Read-only embedding uses the same content and geometry as both editors.
class OverlayWorkspaceRuntimePreview extends StatelessWidget {
  const OverlayWorkspaceRuntimePreview({required this.projection, super.key});
  final OverlayWorkspaceProjection projection;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: OverlayWorkspaceLayoutWorkbench(
      layout: projection.layout,
      settings: projection.settings!,
      canvasOnly: true,
      showHiddenModules: false,
      onChanged: (_, _) {},
    ),
  );
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
