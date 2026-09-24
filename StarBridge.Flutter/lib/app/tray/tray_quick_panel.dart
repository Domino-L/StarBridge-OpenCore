import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../design_system/brand/starbridge_app_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'tray_quick_panel_copy.dart';
import '../shell/chrome/shell_chrome_projection.dart';
import 'tray_presence_status.dart';
import '../presence/manual_presence.dart';
import '../presence/manual_presence_widgets.dart';

enum TrayRuntimeState { running, background, unavailable }

enum TrayOverlayState { enabled, disabled, unavailable }

/// Host-projected facts only. No guessed identity, scene or version defaults.
class TrayQuickPanelState {
  const TrayQuickPanelState({
    this.runtime = TrayRuntimeState.unavailable,
    this.overlay = TrayOverlayState.unavailable,
    this.version,
    this.scene,
  });
  final TrayRuntimeState runtime;
  final TrayOverlayState overlay;
  final String? version, scene;
}

/// Content for the tray surface, not a second engine or a native-window owner.
/// Integration must provide dismiss/restore/exit and authenticated overlay actions.
class TrayQuickPanel extends StatefulWidget {
  const TrayQuickPanel({
    required this.state,
    required this.onDismiss,
    this.chromeProjection,
    this.manualPresence,
    this.onOpen,
    this.onOverlaySettings,
    this.onToggleOverlay,
    this.onExit,
    this.logoKey,
    super.key,
  });
  final TrayQuickPanelState state;
  final Key? logoKey;
  final ValueListenable<ShellChromeProjection>? chromeProjection;
  final ManualPresenceController? manualPresence;
  final VoidCallback onDismiss;
  final Future<void> Function()? onOpen,
      onOverlaySettings,
      onToggleOverlay,
      onExit;
  @override
  State<TrayQuickPanel> createState() => _TrayQuickPanelState();
}

class _TrayQuickPanelState extends State<TrayQuickPanel> {
  bool _busy = false;
  bool _failed = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      // Do not release the guard on a timeout: late native actions may still run.
      await action();
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => trayQuickPanelText(context, key);
    final state = widget.state;
    Widget button(
      String key,
      StarBridgeIconSemantic icon,
      Future<void> Function()? action, {
      bool danger = false,
    }) => OutlinedButton.icon(
      key: Key('tray-$key'),
      onPressed: _busy || action == null ? null : () => _run(action),
      style: danger
          ? OutlinedButton.styleFrom(foregroundColor: tokens.colors.danger)
          : null,
      icon: StarBridgeIcon(icon),
      label: Text(t(key)),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: Focus(
        autofocus: true,
        child: SizedBox(
          width: 336,
          child: StarBridgeSurface(
            role: SurfaceRole.floating,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      StarBridgeAppIcon(key: widget.logoKey, size: 36),
                      SizedBox(width: tokens.space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('brand'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              t('runtime.${state.runtime.name}'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (state.version case final version?)
                              Text(
                                version,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: tokens.colors.textSecondary,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: t('close'),
                        onPressed: widget.onDismiss,
                        icon: const StarBridgeIcon(
                          StarBridgeIconSemantic.windowClose,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.space.md),
                  if (widget.manualPresence case final presence?)
                    MenuAnchor(
                      menuChildren: [
                        ManualPresenceChoices(controller: presence),
                      ],
                      builder: (context, controller, _) => TextButton(
                        key: const Key('tray-presence-menu'),
                        onPressed: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                manualPresenceText(context, 'presence.title'),
                              ),
                            ),
                            ManualPresenceBadge(controller: presence),
                            const SizedBox(width: 8),
                            const StarBridgeIcon(
                              StarBridgeIconSemantic.menuDown,
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    TrayPresenceStatus(projection: widget.chromeProjection),
                  SizedBox(height: tokens.space.md),
                  StarBridgeSurface(
                    role: SurfaceRole.panel,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('overlay'),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        SizedBox(height: tokens.space.xs),
                        Text(
                          t('overlay.${state.overlay.name}'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: state.overlay == TrayOverlayState.enabled
                                    ? tokens.colors.success
                                    : tokens.colors.textSecondary,
                              ),
                        ),
                        SizedBox(height: tokens.space.sm),
                        button(
                          state.overlay == TrayOverlayState.enabled
                              ? 'disable'
                              : 'enable',
                          StarBridgeIconSemantic.overlay,
                          state.overlay == TrayOverlayState.unavailable
                              ? null
                              : widget.onToggleOverlay,
                        ),
                        SizedBox(height: tokens.space.sm),
                        Text(
                          t('scene'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.colors.textSecondary),
                        ),
                        Text(
                          state.scene ?? t('unknown'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: tokens.space.sm),
                  button('open', StarBridgeIconSemantic.home, widget.onOpen),
                  button(
                    'settings',
                    StarBridgeIconSemantic.settings,
                    widget.onOverlaySettings,
                  ),
                  SizedBox(height: tokens.space.xs),
                  const Divider(),
                  button(
                    'exit',
                    StarBridgeIconSemantic.logout,
                    widget.onExit,
                    danger: true,
                  ),
                  if (_busy)
                    Text(
                      t('busy'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_failed)
                    Text(
                      t('failed'),
                      style: TextStyle(color: tokens.colors.danger),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
