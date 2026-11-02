import 'package:flutter/material.dart';

import '../../design_system/icons/menu_hud_drag_handle_icon.dart';
import '../../features/overlay_settings/overlay_workspace_layout_item.dart';
import 'menu_bridge_style.dart';

/// Small text button used on the placement toolbars.
class MenuHudBarButton extends StatelessWidget {
  const MenuHudBarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.primary = false,
    this.trailing,
    this.toggle = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool selected, primary;
  final String? trailing;
  // An on/off switch shows a check mark when on, not only a colour change.
  final bool toggle;
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: primary
            ? BridgeInk.blue
            : selected
            ? BridgeInk.selected
            : Colors.transparent,
      ),
      child: BridgeMenuAction(
        label: label,
        selected: selected,
        onPressed: onPressed,
        padding: EdgeInsets.symmetric(
          horizontal: primary ? 16 : 10,
          vertical: 8,
        ),
        child: Text.rich(
          TextSpan(
            text: toggle && selected ? '✓ $label' : label,
            children: [
              if (trailing != null)
                TextSpan(
                  text: '  $trailing',
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
            color: primary
                ? BridgeInk.onAccent
                : enabled
                ? BridgeInk.text
                : BridgeInk.line,
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.first = false});
  final List<Widget> children;
  final bool first;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      border: first
          ? null
          : const Border(left: BorderSide(color: BridgeInk.divider)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// Top bar: grid/snap toggles, history, hidden modules, Cancel and Done.
class MenuHudPlacementToolbar extends StatelessWidget {
  const MenuHudPlacementToolbar({
    super.key,
    required this.text,
    required this.presetName,
    required this.changed,
    required this.grid,
    required this.align,
    required this.canUndo,
    required this.canRedo,
    required this.hidden,
    required this.hiddenOpen,
    required this.busy,
    required this.onDrag,
    required this.onGrid,
    required this.onAlign,
    required this.onUndo,
    required this.onRedo,
    required this.onHiddenOpen,
    required this.onShow,
    required this.onCancel,
    required this.onDone,
  });
  final String Function(String key, [Map<String, String> args]) text;
  final String presetName;
  final bool changed, grid, align, canUndo, canRedo, hiddenOpen, busy;
  final Map<String, String> hidden;
  final GestureDragUpdateCallback onDrag;
  final VoidCallback onGrid, onAlign, onUndo, onRedo, onHiddenOpen;
  final ValueChanged<String> onShow;
  final VoidCallback onCancel, onDone;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        key: const ValueKey('menu-hud-place-toolbar'),
        decoration: const BoxDecoration(
          color: BridgeInk.window,
          border: Border(
            top: BorderSide(color: BridgeInk.blue),
            bottom: BorderSide(color: BridgeInk.line),
          ),
          boxShadow: [
            BoxShadow(color: BridgeInk.placementBarShadow, blurRadius: 40),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  key: const ValueKey('menu-hud-place-toolbar-grip'),
                  // The whole 32 px box grabs, not only the icon's pixels.
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: onDrag,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints.tightFor(width: 32)
                        .copyWith(minHeight: 32),
                    child: Center(
                      child: MenuHudDragHandleIcon(
                        size: 16,
                        color: BridgeInk.line,
                        semanticLabel: text('menu.hudPlace.moveToolbar'),
                      ),
                    ),
                  ),
                ),
              ),
              _Section(
                first: true,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text('menu.hudPlace.title'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        changed
                            ? '$presetName · ${text('menu.hudPlace.changed')}'
                            : presetName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BridgeInk.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _Section(
                children: [
                  MenuHudBarButton(
                    key: const ValueKey('menu-hud-place-grid'),
                    label: text('menu.hudPlace.grid'),
                    selected: grid,
                    toggle: true,
                    onPressed: onGrid,
                  ),
                  MenuHudBarButton(
                    key: const ValueKey('menu-hud-place-align'),
                    label: text('menu.hudPlace.align'),
                    selected: align,
                    toggle: true,
                    onPressed: onAlign,
                  ),
                ],
              ),
              _Section(
                children: [
                  MenuHudBarButton(
                    key: const ValueKey('menu-hud-place-undo'),
                    label: text('menu.hudPlace.undo'),
                    onPressed: canUndo && !busy ? onUndo : null,
                  ),
                  MenuHudBarButton(
                    key: const ValueKey('menu-hud-place-redo'),
                    label: text('menu.hudPlace.redo'),
                    onPressed: canRedo && !busy ? onRedo : null,
                  ),
                ],
              ),
              _Section(
                children: [
                  MenuHudBarButton(
                    key: const ValueKey('menu-hud-place-hidden'),
                    label: text('menu.hudPlace.hidden', {
                      'count': '${hidden.length}',
                    }),
                    selected: hiddenOpen,
                    onPressed: onHiddenOpen,
                  ),
                ],
              ),
              _Section(
                children: [
                  MenuHudBarButton(
                    key: const ValueKey('menu-hud-place-cancel'),
                    label: text('menu.hudPlace.cancel'),
                    trailing: 'Esc',
                    onPressed: busy ? null : onCancel,
                  ),
                  const SizedBox(width: 4),
                  MenuHudBarButton(
                    key: const ValueKey('menu-hud-place-done'),
                    label: text('menu.hudPlace.done'),
                    trailing: 'Enter',
                    primary: true,
                    onPressed: busy ? null : onDone,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (hiddenOpen)
        Container(
          key: const ValueKey('menu-hud-place-hidden-list'),
          width: 240,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: const BoxDecoration(
            color: BridgeInk.window,
            border: Border(top: BorderSide(color: BridgeInk.blue)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hidden.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: BridgeCaption(text('menu.hudPlace.noneHidden')),
                ),
              for (final entry in hidden.entries)
                Row(
                  children: [
                    const SizedBox(width: 14),
                    Expanded(child: Text(entry.value)),
                    MenuHudBarButton(
                      key: ValueKey('menu-hud-place-show-${entry.key}'),
                      label: text('menu.hudPlace.show'),
                      onPressed: () => onShow(entry.key),
                    ),
                  ],
                ),
            ],
          ),
        ),
      const SizedBox(height: 6),
      Text(
        text('menu.hudPlace.hint'),
        style: const TextStyle(
          fontSize: 12,
          color: BridgeInk.muted,
          shadows: [Shadow(blurRadius: 3)],
        ),
      ),
    ],
  );
}

/// Tools for the selected module: lock, opacity, default position, hide.
class MenuHudModuleTools extends StatelessWidget {
  const MenuHudModuleTools({
    super.key,
    required this.text,
    required this.moduleKey,
    required this.item,
    required this.opacityOpen,
    required this.onLock,
    required this.onOpacityOpen,
    required this.onOpacity,
    required this.onReset,
    required this.onHide,
  });
  final String Function(String key, [Map<String, String> args]) text;
  final String moduleKey;
  final OverlayWorkspaceLayoutItem? item;
  final bool opacityOpen;
  final VoidCallback onLock, onOpacityOpen, onReset, onHide;
  final void Function(OverlayWorkspaceLayoutItem item, bool first) onOpacity;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return Column(
      key: const ValueKey('menu-hud-place-module-tools'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: BridgeInk.window,
            border: Border(top: BorderSide(color: BridgeInk.blue)),
            boxShadow: [
              BoxShadow(color: BridgeInk.placementToolShadow, blurRadius: 30),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (moduleKey == 'Crosshair')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: BridgeCaption(text('menu.hudPlace.crosshairNote')),
                ),
              if (item != null) ...[
                MenuHudBarButton(
                  key: const ValueKey('menu-hud-place-lock'),
                  label: text(
                    item.isLocked
                        ? 'menu.hudPlace.locked'
                        : 'menu.hudPlace.lock',
                  ),
                  selected: item.isLocked,
                  onPressed: onLock,
                ),
                MenuHudBarButton(
                  key: const ValueKey('menu-hud-place-opacity'),
                  label: text('menu.hudPlace.opacity'),
                  selected: opacityOpen,
                  onPressed: onOpacityOpen,
                ),
                MenuHudBarButton(
                  key: const ValueKey('menu-hud-place-reset'),
                  label: text('menu.hudPlace.reset'),
                  onPressed: item.isLocked ? null : onReset,
                ),
              ],
              MenuHudBarButton(
                key: const ValueKey('menu-hud-place-hide'),
                label: text('menu.hudPlace.hide'),
                onPressed: onHide,
              ),
            ],
          ),
        ),
        if (opacityOpen && item != null)
          Container(
            key: const ValueKey('menu-hud-place-opacity-panel'),
            width: 280,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: BridgeInk.window,
              border: Border(top: BorderSide(color: BridgeInk.blue)),
            ),
            child: Column(
              children: [
                for (final (label, value, apply) in [
                  (
                    'menu.hudPlace.text',
                    item.textOpacity,
                    (double v) => item.copyWith(textOpacity: v),
                  ),
                  (
                    'menu.hudPlace.background',
                    item.backgroundOpacity,
                    (double v) => item.copyWith(backgroundOpacity: v),
                  ),
                  (
                    'menu.hudPlace.decoration',
                    item.decorationOpacity,
                    (double v) => item.copyWith(decorationOpacity: v),
                  ),
                ]) ...[
                  Row(
                    children: [
                      Expanded(child: BridgeCaption(text(label))),
                      Text('${(value * 100).round()}%'),
                    ],
                  ),
                  Slider(
                    value: value,
                    divisions: 20,
                    onChangeStart: (v) => onOpacity(apply(v), true),
                    onChanged: (v) => onOpacity(apply(v), false),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
