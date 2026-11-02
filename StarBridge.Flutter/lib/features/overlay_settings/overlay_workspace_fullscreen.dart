import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_editor_state.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_editor_tools.dart';
import 'overlay_workspace_gesture_save.dart';
import 'overlay_workspace_layout_editor.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_models.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class OverlayWorkspaceFullscreenButton extends StatelessWidget {
  const OverlayWorkspaceFullscreenButton({
    required this.module,
    required this.editor,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayWorkspaceEditorState editor;

  Future<void> _open(BuildContext context, InteractionSource source) async {
    if (editor.fullscreenOpening) return;
    editor.change(() => editor.fullscreenOpening = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final failureText = _copy(context, 'overlay.editor.windowFailed');
    final failureSnack = starBridgeSnackBarFromContext(
      context,
      starBridgeTimedSnackBar(content: Text(failureText)),
      source: source,
    );
    final data = resolveStarBridgeInteraction(context);
    final link = InteractionScope.linkOf(context);
    void failed() {
      if (messenger.mounted) {
        messenger.showSnackBar(failureSnack);
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
          pageBuilder: (routeContext, _, _) {
            final body = starBridgeInitialReadViewport(
              routeContext,
              source: source,
              child: OverlayWorkspaceFullscreenEditor(
                module: module,
                editor: editor,
                initialSource: source,
              ),
            );
            final themed = Builder(
              builder: (context) {
                final current = InteractionScope.of(context);
                return StarBridgeInteractionConfiguration(
                  suite: current.suite,
                  reduceMotion: current.reduceMotion,
                  child: body,
                );
              },
            );
            return link == null
                ? InteractionScope(data: data, child: themed)
                : InteractionScope.follow(link, child: themed);
          },
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
    builder: (context, _) => StarBridgeActionButton(
      controlKey: const Key('overlay-enter-fullscreen'),
      onActivate: editor.fullscreenOpening
          ? null
          : (source) => unawaited(
              runStarBridgeActivation(source, () => _open(context, source)),
            ),
      child: _commandLabel(
        StarBridgeIconSemantic.windowMaximize,
        _copy(context, 'overlay.editor.fullscreen'),
      ),
    ),
  );
}

class OverlayWorkspaceFullscreenEditor extends StatefulWidget {
  const OverlayWorkspaceFullscreenEditor({
    required this.module,
    required this.editor,
    this.initialSource = InteractionSource.programmatic,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayWorkspaceEditorState editor;
  final InteractionSource initialSource;
  @override
  State<OverlayWorkspaceFullscreenEditor> createState() =>
      _FullscreenEditorState();
}

class _FullscreenEditorState extends State<OverlayWorkspaceFullscreenEditor> {
  bool _leaving = false;
  bool _canPop = false;
  late InteractionSource _pendingSource = widget.initialSource;

  void _commitInput() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }

  Future<void> _save(InteractionSource source) async {
    _commitInput();
    final current = widget.module.projection.value;
    if (!current.available || current.busy || !current.dirty) return;
    _pendingSource = source;
    await runStarBridgeActivation(source, widget.module.save);
  }

  Future<void> _runRuntimeAction(
    OverlayWorkspaceProjection projection,
    InteractionSource source,
  ) async {
    _pendingSource = source;
    await runStarBridgeActivation(source, () => _runtimeAction(projection));
  }

  Future<void> _runtimeAction(OverlayWorkspaceProjection projection) async {
    _commitInput();
    final language = Localizations.localeOf(context).toLanguageTag();
    switch (projection.runtime.windowState) {
      case 'open':
      case 'suppressed':
      case 'opening':
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

  Future<void> _leave(InteractionSource source) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      _commitInput();
      await runStarBridgeActivation(source, widget.module.editorWindow.exit);
      if (!mounted) return;
      setState(() => _canPop = true);
      // PopScope must rebuild before handling the programmatic exit.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } on Object {
      if (mounted) {
        setState(() => _leaving = false);
        _showError(context, source);
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
      unawaited(_leave(InteractionSource.keyboard));
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyS) {
      unawaited(_save(InteractionSource.keyboard));
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
            StarBridgeActionButton(
              controlKey: const Key('overlay-exit-fullscreen'),
              onActivate: _leaving
                  ? null
                  : (source) => unawaited(_leave(source)),
              child: _commandLabel(
                StarBridgeIconSemantic.windowRestore,
                _copy(context, 'overlay.editor.exit'),
              ),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              controlKey: const Key('overlay-fullscreen-runtime-action'),
              onActivate: projection.busy
                  ? null
                  : (source) =>
                        unawaited(_runRuntimeAction(projection, source)),
              child: _commandLabel(
                StarBridgeIconSemantic.overlay,
                _copy(context, switch (projection.runtime.windowState) {
                  'open' || 'suppressed' => 'overlay.runtime.closeAction',
                  'opening' => 'overlay.runtime.cancelOpenAction',
                  'failed' => 'overlay.runtime.retryAction',
                  'unavailable' => 'overlay.runtime.checkAction',
                  _ => 'overlay.runtime.openAction',
                }),
              ),
            ),
            ListenableBuilder(
              listenable: widget.editor,
              builder: (context, _) => StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('overlay-toggle-tools'),
                onActivate: (_) => widget.editor.change(
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
            StarBridgeIconAction(
              controlKey: const Key('overlay-fullscreen-undo'),
              label: _copy(context, 'overlay.workspace.undo'),
              onActivate: widget.module.canUndo && !projection.busy
                  ? (_) => widget.module.undo()
                  : null,
              icon: const StarBridgeIcon(StarBridgeIconSemantic.undo),
            ),
            StarBridgeIconAction(
              controlKey: const Key('overlay-fullscreen-redo'),
              label: _copy(context, 'overlay.workspace.redo'),
              onActivate: widget.module.canRedo && !projection.busy
                  ? (_) => widget.module.redo()
                  : null,
              icon: const StarBridgeIcon(StarBridgeIconSemantic.redo),
            ),
            // Layout changes save on their own, as on the settings page.
            Text(
              _copy(
                context,
                !projection.dirty
                    ? 'overlay.workspace.saved'
                    : projection.failure == null
                    ? 'overlay.workspace.saving'
                    : 'overlay.workspace.saveFailed',
              ),
              key: const Key('overlay-fullscreen-save-status'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: projection.dirty && projection.failure != null
                    ? context.tokens.colors.warning
                    : null,
              ),
            ),
            if (projection.busy)
              Builder(
                builder: (context) {
                  final data = resolveStarBridgeInteraction(context);
                  return InteractionScope(
                    data: data.copyWith(
                      reduceMotion:
                          data.reduceMotion ||
                          _pendingSource == InteractionSource.keyboard,
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: SuiteBusyFrame(
                        busy: true,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: SuiteBusyLabel(
                            _copy(
                              context,
                              projection.operation ==
                                      OverlayWorkspaceOperation.saving
                                  ? 'overlay.workspace.saving'
                                  : switch (projection.runtimeOperation) {
                                      OverlayRuntimeOperation.opening =>
                                        'overlay.runtime.opening',
                                      OverlayRuntimeOperation.closing =>
                                        'overlay.runtime.closing',
                                      OverlayRuntimeOperation.retrying =>
                                        'overlay.runtime.retrying',
                                      OverlayRuntimeOperation.reading =>
                                        'overlay.runtime.checking',
                                      _ => 'overlay.loading',
                                    },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeInteractionRegion(
      child: PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave(InteractionSource.keyboard));
        },
        child: Scaffold(
          key: const Key('overlay-fullscreen-editor'),
          backgroundColor: tokens.surfaces.ground.fill,
          body: OverlayWorkspaceGestureSave(
            module: widget.module,
            child: Focus(
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
                            editOwner: (widget.module, projection.snapshot),
                            currentEditOwner: () => (
                              widget.module,
                              widget.module.projection.value.snapshot,
                            ),
                            appearances: projection.snapshot!.appearances,
                            controller: widget.editor,
                            previewIdentity: widget.module.previewIdentity,
                            sources: projection.sources,
                            sourceScenes: widget.module.sourceScenes,
                            fullScreen: true,
                            editorActions: _toolbar(context, projection),
                            presetId: projection.snapshot!.activePresetId!,
                            startupExtra: OverlayWorkspaceHotkeyCard(
                              hotkey: projection.hotkey!,
                              onBindingChanged: (value) =>
                                  widget.module.updateHotkey(binding: value),
                              onEnabledChanged: (value) =>
                                  widget.module.updateHotkey(enabled: value),
                              onRegisterHotKeyChanged: (value) => widget.module
                                  .updateHotkey(registerHotKey: value),
                              registrationFailures:
                                  projection.runtime.hotkeyRegistrationFailures,
                            ),
                            onChanged: (item, coalesce) => widget.module
                                .updateLayoutItem(item, coalesce: coalesce),
                            onSettingChanged: widget.module.updateSetting,
                            onExperiencePreset:
                                widget.module.applyExperiencePreset,
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
                        child: Text(
                          _copy(context, 'overlay.unavailable.title'),
                        ),
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
                                    StarBridgeActionButton(
                                      kind: StarBridgeActionKind.quiet,
                                      controlKey: const Key(
                                        'overlay-exit-fullscreen',
                                      ),
                                      onActivate: _leaving
                                          ? null
                                          : (source) =>
                                                unawaited(_leave(source)),
                                      child: Text(
                                        _copy(context, 'overlay.editor.exit'),
                                      ),
                                    ),
                                    StarBridgeActionButton(
                                      kind: StarBridgeActionKind.quiet,
                                      controlKey: const Key(
                                        'overlay-toggle-tools',
                                      ),
                                      onActivate: (_) => widget.editor.change(
                                        () => widget.editor.toolsVisible = true,
                                      ),
                                      child: Text(
                                        _copy(
                                          context,
                                          'overlay.editor.showTools',
                                        ),
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
        ),
      ),
    );
  }
}

void _showError(BuildContext context, InteractionSource source) =>
    showStarBridgeSnackBar(
      context,
      starBridgeTimedSnackBar(content: Text(_copy(context, 'overlay.editor.windowFailed'))),
      source: source,
    );
Widget _commandLabel(StarBridgeIconSemantic icon, String label) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    StarBridgeIcon(icon, size: 16),
    const SizedBox(width: 8),
    Flexible(child: Text(label)),
  ],
);
String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
