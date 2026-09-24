import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_editor_state.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_editor_tools.dart';
import 'overlay_workspace_layout_editor.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_module.dart';

class OverlayWorkspaceFullscreenButton extends StatelessWidget {
  const OverlayWorkspaceFullscreenButton({
    required this.module,
    required this.editor,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayWorkspaceEditorState editor;

  Future<void> _open(BuildContext context) async {
    if (editor.fullscreenOpening) return;
    editor.change(() => editor.fullscreenOpening = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final failureText = _copy(context, 'overlay.editor.windowFailed');
    void failed() {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failureText)));
      }
    }

    var entered = false;
    try {
      await module.editorWindow.enter();
      entered = true;
      // Window resizing can replace this button's responsive subtree. The
      // workspace and root Navigator, not the launcher element, own the route.
      if (!navigator.mounted || editor.disposed) return;
      await navigator.push<void>(
        PageRouteBuilder(
          fullscreenDialog: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              OverlayWorkspaceFullscreenEditor(module: module, editor: editor),
        ),
      );
    } on Object {
      failed();
    } finally {
      if (entered) {
        try {
          await module.editorWindow.exit();
        } on Object {
          failed();
        }
      }
      editor.change(() => editor.fullscreenOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) => OutlinedButton.icon(
      key: const Key('overlay-enter-fullscreen'),
      onPressed: editor.fullscreenOpening ? null : () => _open(context),
      icon: const StarBridgeIcon(
        StarBridgeIconSemantic.windowMaximize,
        size: 16,
      ),
      label: Text(_copy(context, 'overlay.editor.fullscreen')),
    ),
  );
}

class OverlayWorkspaceFullscreenEditor extends StatefulWidget {
  const OverlayWorkspaceFullscreenEditor({
    required this.module,
    required this.editor,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayWorkspaceEditorState editor;
  @override
  State<OverlayWorkspaceFullscreenEditor> createState() =>
      _FullscreenEditorState();
}

class _FullscreenEditorState extends State<OverlayWorkspaceFullscreenEditor> {
  bool _leaving = false;
  bool _canPop = false;

  void _commitInput() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }

  Future<void> _save() async {
    _commitInput();
    await widget.module.save();
  }

  Future<void> _runRuntimeAction(OverlayWorkspaceProjection projection) async {
    _commitInput();
    final language = Localizations.localeOf(context).toLanguageTag();
    switch (projection.runtime.windowState) {
      case 'open':
        await widget.module.closeRuntime(language);
        return;
      case 'failed':
        await widget.module.retryRuntime(language);
        return;
      case 'unavailable':
        await widget.module.refreshRuntime(language);
        return;
      default:
        await widget.module.openRuntime(language);
        return;
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      _commitInput();
      await widget.module.editorWindow.exit();
      if (!mounted) return;
      setState(() => _canPop = true);
      // PopScope must rebuild before handling the programmatic exit.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } on Object {
      if (mounted) {
        setState(() => _leaving = false);
        _showError(context);
      }
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.f11) {
      unawaited(_leave());
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyS) {
      unawaited(_save());
      return KeyEventResult.handled;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    final editingText =
        focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (editingText) return KeyEventResult.ignored;
    if (keyboard.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        if (keyboard.isShiftPressed) {
          widget.module.redo();
        } else {
          widget.module.undo();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        widget.module.redo();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.tab) {
      widget.editor.change(
        () => widget.editor.toolsVisible = !widget.editor.toolsVisible,
      );
      return KeyEventResult.handled;
    }
    final projection = widget.module.projection.value;
    if (projection.busy || !projection.available) return KeyEventResult.ignored;
    final selected = projection.layout.where(
      (item) => item.key == widget.editor.selectedKey,
    );
    if (selected.isEmpty) return KeyEventResult.ignored;
    final item = selected.first;
    if (key == LogicalKeyboardKey.delete) {
      final field = overlayModuleVisibilityFields[item.key];
      if (field != null) widget.module.updateSetting(field, false);
      return KeyEventResult.handled;
    }
    if (item.isLocked || widget.editor.layoutLocked) {
      return KeyEventResult.ignored;
    }
    final step = keyboard.isShiftPressed ? 10.0 : widget.editor.nudgePixels;
    final movement = switch (key) {
      LogicalKeyboardKey.arrowLeft => ('x', -step),
      LogicalKeyboardKey.arrowRight => ('x', step),
      LogicalKeyboardKey.arrowUp => ('y', -step),
      LogicalKeyboardKey.arrowDown => ('y', step),
      _ => null,
    };
    if (movement == null) return KeyEventResult.ignored;
    widget.module.updateLayoutItem(
      OverlayWorkspaceLayoutGeometry.nudge(
        item,
        movement.$1,
        movement.$2,
        surfaceSize: widget.editor.fullscreenSurfaceSize,
      ),
      coalesce: false,
    );
    return KeyEventResult.handled;
  }

  Widget _toolbar(BuildContext context, OverlayWorkspaceProjection projection) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surfaces.floating.fill,
      borderRadius: tokens.shape.small,
      child: Padding(
        padding: EdgeInsets.all(tokens.space.xs),
        child: Wrap(
          spacing: tokens.space.xs,
          runSpacing: tokens.space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('overlay-exit-fullscreen'),
              onPressed: _leaving ? null : _leave,
              icon: const StarBridgeIcon(
                StarBridgeIconSemantic.windowRestore,
                size: 16,
              ),
              label: Text(_copy(context, 'overlay.editor.exit')),
            ),
            FilledButton.icon(
              key: const Key('overlay-fullscreen-runtime-action'),
              onPressed: projection.busy
                  ? null
                  : () => _runRuntimeAction(projection),
              icon: const StarBridgeIcon(
                StarBridgeIconSemantic.overlay,
                size: 16,
              ),
              label: Text(
                _copy(context, switch (projection.runtime.windowState) {
                  'open' => 'overlay.runtime.closeAction',
                  'failed' => 'overlay.runtime.retryAction',
                  'unavailable' => 'overlay.runtime.checkAction',
                  _ => 'overlay.runtime.openAction',
                }),
              ),
            ),
            ListenableBuilder(
              listenable: widget.editor,
              builder: (context, _) => TextButton(
                key: const Key('overlay-toggle-tools'),
                onPressed: () => widget.editor.change(
                  () =>
                      widget.editor.toolsVisible = !widget.editor.toolsVisible,
                ),
                child: Text(
                  _copy(
                    context,
                    widget.editor.toolsVisible
                        ? 'overlay.editor.hideTools'
                        : 'overlay.editor.showTools',
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: _copy(context, 'overlay.workspace.undo'),
              onPressed: widget.module.canUndo && !projection.busy
                  ? widget.module.undo
                  : null,
              icon: const StarBridgeIcon(StarBridgeIconSemantic.undo),
            ),
            IconButton(
              tooltip: _copy(context, 'overlay.workspace.redo'),
              onPressed: widget.module.canRedo && !projection.busy
                  ? widget.module.redo
                  : null,
              icon: const StarBridgeIcon(StarBridgeIconSemantic.redo),
            ),
            FilledButton(
              key: const Key('overlay-fullscreen-save'),
              onPressed: projection.available && !projection.busy
                  ? _save
                  : null,
              child: Text(_copy(context, 'overlay.workspace.save')),
            ),
            TextButton(
              key: const Key('overlay-fullscreen-discard'),
              onPressed: projection.dirty && !projection.busy
                  ? widget.module.discardChanges
                  : null,
              child: Text(_copy(context, 'overlay.workspace.discard')),
            ),
            Text(
              _copy(
                context,
                projection.dirty
                    ? 'overlay.workspace.dirty'
                    : 'overlay.workspace.saved',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (projection.busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        key: const Key('overlay-fullscreen-editor'),
        backgroundColor: tokens.surfaces.ground.fill,
        body: Focus(
          autofocus: true,
          onKeyEvent: _key,
          child: ValueListenableBuilder(
            valueListenable: widget.module.projection,
            builder: (context, projection, _) => Stack(
              fit: StackFit.expand,
              children: [
                if (projection.available)
                  Positioned.fill(
                    child: AbsorbPointer(
                      absorbing: projection.busy,
                      child: OverlayWorkspaceLayoutWorkbench(
                        layout: projection.layout,
                        settings: projection.settings!,
                        appearances: projection.snapshot!.appearances,
                        controller: widget.editor,
                        previewIdentity: widget.module.previewIdentity,
                        fullScreen: true,
                        editorActions: _toolbar(context, projection),
                        presetId: projection.snapshot!.activePresetId!,
                        startupExtra: OverlayWorkspaceHotkeyCard(
                          hotkey: projection.hotkey!,
                          onBindingChanged: (value) =>
                              widget.module.updateHotkey(binding: value),
                          onEnabledChanged: (value) =>
                              widget.module.updateHotkey(enabled: value),
                        ),
                        onChanged: (item, coalesce) => widget.module
                            .updateLayoutItem(item, coalesce: coalesce),
                        onSettingChanged: widget.module.updateSetting,
                        onExperiencePreset: widget.module.applyExperiencePreset,
                        onEventNotificationPlacement:
                            widget.module.updateEventNotificationPlacement,
                        onEventNotificationGestureStart:
                            widget.module.beginEventNotificationGesture,
                        onEventNotificationGestureEnd:
                            widget.module.endEventNotificationGesture,
                      ),
                    ),
                  )
                else
                  Center(
                    child: Text(_copy(context, 'overlay.unavailable.title')),
                  ),
                ListenableBuilder(
                  listenable: widget.editor,
                  builder: (context, _) => widget.editor.toolsVisible
                      ? const SizedBox.shrink()
                      : Positioned(
                          left: 12,
                          bottom: 36,
                          child: Material(
                            color: tokens.surfaces.floating.fill,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _leave,
                                  child: Text(
                                    _copy(context, 'overlay.editor.exit'),
                                  ),
                                ),
                                TextButton(
                                  key: const Key('overlay-toggle-tools'),
                                  onPressed: () => widget.editor.change(
                                    () => widget.editor.toolsVisible = true,
                                  ),
                                  child: Text(
                                    _copy(context, 'overlay.editor.showTools'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                Positioned(
                  left: 16,
                  bottom: 12,
                  child: Text(
                    _copy(context, 'overlay.editor.keys'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ),
                if (projection.failure != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 36,
                    child: Material(
                      color: tokens.colors.warningSoft,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _copy(
                            context,
                            'overlay.error.${projection.failure!.name}',
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showError(BuildContext context) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text(_copy(context, 'overlay.editor.windowFailed'))),
    );
String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
