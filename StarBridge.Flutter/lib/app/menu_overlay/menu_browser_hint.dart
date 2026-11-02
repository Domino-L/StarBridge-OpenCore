import 'package:flutter/material.dart';

import '../../platform/window/native_viewport_visibility.dart';
import 'menu_workspace_controller.dart';

/// A hint is an OverlayPortal, not a popup route. Own just its native viewport
/// lease through its actual exit/disposal, including retained panel visibility.
class MenuBrowserHint extends StatelessWidget {
  const MenuBrowserHint({
    required this.workspace,
    required this.active,
    required this.builder,
    super.key,
  });
  final MenuWorkspaceController workspace;
  final bool active;
  final Widget Function(ValueChanged<bool> visible) builder;

  @override
  Widget build(BuildContext context) => NativeViewportMenu(
    builder: (open, close) => ListenableBuilder(
      listenable: workspace,
      builder: (context, _) => TooltipVisibility(
        visible:
            active &&
            NativeViewportScope.isActive(context) &&
            workspace.panelsVisible &&
            workspace.isOpen('browser'),
        child: builder((visible) => visible ? open() : close()),
      ),
    ),
  );
}
