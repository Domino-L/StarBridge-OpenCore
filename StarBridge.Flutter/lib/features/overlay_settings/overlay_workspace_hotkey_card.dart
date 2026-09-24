import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';

class OverlayWorkspaceHotkeyCard extends StatefulWidget {
  const OverlayWorkspaceHotkeyCard({
    required this.hotkey,
    required this.onBindingChanged,
    required this.onEnabledChanged,
    super.key,
  });

  final OverlayWorkspaceHotkey hotkey;
  final ValueChanged<String> onBindingChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  State<OverlayWorkspaceHotkeyCard> createState() =>
      _OverlayWorkspaceHotkeyCardState();
}

class _OverlayWorkspaceHotkeyCardState
    extends State<OverlayWorkspaceHotkeyCard> {
  final FocusNode _captureFocus = FocusNode(debugLabel: 'overlay-hotkey');
  bool _capturing = false;
  String? _captureError;

  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  void _startCapture() {
    setState(() {
      _capturing = true;
      _captureError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureFocus.requestFocus();
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_capturing || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _capturing = false;
        _captureError = null;
      });
      return KeyEventResult.handled;
    }
    if (_modifierKeys.contains(event.logicalKey)) return KeyEventResult.handled;

    final key = event.logicalKey.keyLabel.trim().toUpperCase();
    final isFunctionKey = RegExp(r'^F(?:[1-9]|1[0-2])$').hasMatch(key);
    final isLetterOrDigit = RegExp(r'^[A-Z0-9]$').hasMatch(key);
    final keyboard = HardwareKeyboard.instance;
    final modifiers = <String>[
      if (keyboard.isControlPressed) 'Ctrl',
      if (keyboard.isAltPressed) 'Alt',
      if (keyboard.isShiftPressed) 'Shift',
      if (keyboard.isMetaPressed) 'Win',
    ];
    if ((!isFunctionKey && modifiers.isEmpty) ||
        (!isFunctionKey && !isLetterOrDigit)) {
      setState(
        () => _captureError = _copy(
          context,
          'overlay.workspace.hotkeyCaptureInvalid',
        ),
      );
      return KeyEventResult.handled;
    }

    widget.onBindingChanged([...modifiers, key].join('+'));
    setState(() {
      _capturing = false;
      _captureError = null;
    });
    return KeyEventResult.handled;
  }

  static final _modifierKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final binding = Focus(
              focusNode: _captureFocus,
              onKeyEvent: _handleKey,
              child: Container(
                key: ValueKey('overlay-hotkey-${widget.hotkey.binding}'),
                padding: EdgeInsets.all(tokens.space.md),
                decoration: BoxDecoration(
                  color: tokens.surfaces.ground.fill,
                  border: Border.all(
                    color: _capturing
                        ? tokens.colors.accent
                        : tokens.surfaces.panel.border,
                  ),
                  borderRadius: tokens.shape.medium,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _copy(context, 'overlay.workspace.hotkey'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SizedBox(height: tokens.space.sm),
                    if (_capturing)
                      Text(
                        _copy(context, 'overlay.workspace.hotkeyCapturing'),
                        key: const Key('overlay-hotkey-capturing'),
                        style: TextStyle(color: tokens.colors.accent),
                      )
                    else
                      Wrap(
                        spacing: tokens.space.xs,
                        runSpacing: tokens.space.xs,
                        children: widget.hotkey.binding
                            .split('+')
                            .map((part) => _HotkeyKeycap(label: part))
                            .toList(growable: false),
                      ),
                    if (_captureError != null) ...[
                      SizedBox(height: tokens.space.xs),
                      Text(
                        _captureError!,
                        style: TextStyle(color: tokens.colors.danger),
                      ),
                    ],
                    SizedBox(height: tokens.space.sm),
                    Wrap(
                      spacing: tokens.space.sm,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('overlay-hotkey-record'),
                          onPressed: _capturing ? null : _startCapture,
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.tools,
                          ),
                          label: Text(
                            _copy(context, 'overlay.workspace.hotkeyRecord'),
                          ),
                        ),
                        TextButton(
                          key: const Key('overlay-hotkey-reset'),
                          onPressed: _capturing
                              ? null
                              : () => widget.onBindingChanged('Ctrl+Shift+O'),
                          child: Text(
                            _copy(context, 'overlay.workspace.hotkeyReset'),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _copy(context, 'overlay.workspace.hotkeyHelp'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
            final enabled = SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_copy(context, 'overlay.workspace.hotkeyEnabled')),
              subtitle: Text(_hotkeyState(context, widget.hotkey.runtimeState)),
              value: widget.hotkey.enabled,
              onChanged: widget.onEnabledChanged,
            );
            if (constraints.maxWidth < 640) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  binding,
                  SizedBox(height: tokens.space.sm),
                  enabled,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: binding),
                SizedBox(width: tokens.space.md),
                Expanded(child: enabled),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HotkeyKeycap extends StatelessWidget {
  const _HotkeyKeycap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaces.panel.fill,
        border: Border.all(color: tokens.surfaces.panel.border),
        borderRadius: tokens.shape.small,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

String _hotkeyState(BuildContext context, String state) => _copy(
  context,
  'overlay.workspace.hotkey.${const {'registered', 'conflict', 'invalid', 'disabled'}.contains(state) ? state : 'pending'}',
);

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
