import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_icon_action.dart';
import '../icons/icon_semantic.dart';
import '../icons/starbridge_icon.dart';

/// Controlled choice chip. Callers keep their existing single/multiple choice
/// rules and async guards; every activation immediately requests !selected.
class StarBridgeChoiceChip extends StatefulWidget {
  const StarBridgeChoiceChip({
    required this.label,
    required this.selected,
    this.onSelected,
    this.controlKey,
    this.side,
    this.foregroundColor,
    this.selectedColor,
    this.showCheckmark,
    this.shape,
    this.autofocus = false,
    super.key,
  }) : _filter = false,
       _input = false,
       onDeleted = null,
       deleteIcon = null,
       deleteLabel = null,
       deleteKey = null;

  /// Retains the caller's native multi-select chip projection in standard mode.
  const StarBridgeChoiceChip.filter({
    required this.label,
    required this.selected,
    this.onSelected,
    this.controlKey,
    this.side,
    this.foregroundColor,
    this.selectedColor,
    this.showCheckmark,
    this.shape,
    this.autofocus = false,
    super.key,
  }) : _filter = true,
       _input = false,
       onDeleted = null,
       deleteIcon = null,
       deleteLabel = null,
       deleteKey = null;

  /// Selection and removal remain distinct controlled actions. In standard
  /// mode this preserves InputChip geometry; suites use the approved chip
  /// face with an independent source-aware trailing target.
  const StarBridgeChoiceChip.input({
    required this.label,
    required this.selected,
    this.onSelected,
    this.onDeleted,
    this.deleteIcon,
    this.deleteLabel,
    this.deleteKey,
    this.controlKey,
    this.side,
    this.foregroundColor,
    this.selectedColor,
    this.showCheckmark,
    this.shape,
    this.autofocus = false,
    super.key,
  }) : _filter = false,
       _input = true;

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Key? controlKey;
  final BorderSide? side;

  /// Existing domain colours, scoped to this chip. Null keeps suite defaults.
  final Color? foregroundColor, selectedColor;

  /// The consumer's original native chip face in the standard suite
  /// (checkmark, shape). Suites keep their approved chip face.
  final bool? showCheckmark;
  final OutlinedBorder? shape;

  /// Focus this chip when its scope has no focus yet (dialog first field).
  final bool autofocus;
  final bool _filter;
  final bool _input;
  final ValueChanged<InteractionSource>? onDeleted;
  final Widget? deleteIcon;
  final String? deleteLabel;
  final Key? deleteKey;

  @override
  State<StarBridgeChoiceChip> createState() => _StarBridgeChoiceChipState();
}

class _StarBridgeChoiceChipState extends State<StarBridgeChoiceChip> {
  final _focus = FocusNode();
  InteractionSource _nativeSource = InteractionSource.keyboard;
  InteractionSource? _selectionSource;
  bool? _requestedValue;
  int _nativeEpoch = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).autofocus(_focus);
      });
    }
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _activate(InteractionSource source) {
    if (widget.onSelected == null) return;
    _nativeSource = InteractionSource.keyboard;
    setState(() {
      _selectionSource = source;
      _requestedValue = !widget.selected;
      if (source == InteractionSource.keyboard) _nativeEpoch++;
    });
    unawaited(
      runStarBridgeActivation<void>(
        source,
        () => widget.onSelected!(!widget.selected),
      ),
    );
  }

  void _remove(InteractionSource source) {
    if (widget.onDeleted == null) return;
    _nativeSource = InteractionSource.keyboard;
    if (source == InteractionSource.keyboard) setState(() => _nativeEpoch++);
    unawaited(
      runStarBridgeActivation<void>(source, () => widget.onDeleted!(source)),
    );
  }

  @override
  void didUpdateWidget(StarBridgeChoiceChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (_requestedValue == widget.selected &&
          _selectionSource == InteractionSource.keyboard) {
        _nativeEpoch++;
      }
      _requestedValue = null;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StarBridgeInteractionRegion(child: Builder(builder: _buildControl));

  Widget _domainScope(InteractionData data, Widget child) {
    if (widget.foregroundColor == null && widget.selectedColor == null) {
      return child;
    }
    final p = data.palette;
    return InteractionScope(
      data: data.copyWith(
        palette: InteractionPalette(
          brightness: p.brightness,
          accent: widget.foregroundColor ?? p.accent,
          accentBright: widget.foregroundColor ?? p.accentBright,
          onAccent: p.onAccent,
          selectedFill: widget.selectedColor ?? p.selectedFill,
          surface: p.surface,
          raised: p.raised,
          border: p.border,
          textPrimary: widget.foregroundColor ?? p.textPrimary,
          textSecondary: widget.foregroundColor ?? p.textSecondary,
          textDisabled: p.textDisabled,
          focusRing: p.focusRing,
          success: p.success,
          onSuccess: p.onSuccess,
          danger: p.danger,
          onDanger: p.onDanger,
          warning: p.warning,
        ),
      ),
      child: child,
    );
  }

  Widget _buildControl(BuildContext context) {
    final data = InteractionScope.of(context);
    final enabled = widget.onSelected != null;
    final interactive = enabled || widget.onDeleted != null;
    if (data.suite != InteractionSuite.standard) {
      final target = SuiteChoiceChip(
        key: widget._input ? null : widget.controlKey,
        selectionKey: widget._input ? widget.controlKey : null,
        label: widget.label,
        selected: widget.selected,
        focusNode: _focus,
        onActivate: enabled ? _activate : null,
        trailing: widget.onDeleted == null
            ? null
            : StarBridgeIconAction(
                controlKey: widget.deleteKey,
                icon:
                    widget.deleteIcon ??
                    const StarBridgeIcon(
                      StarBridgeIconSemantic.windowClose,
                      size: 14,
                    ),
                label:
                    widget.deleteLabel ??
                    MaterialLocalizations.of(context).deleteButtonTooltip,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: const EdgeInsets.all(4),
                onActivate: _remove,
              ),
      );
      final decorated = widget.side == null
          ? target
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.fromBorderSide(widget.side!),
                borderRadius: suiteRadius(data.suite, 14),
              ),
              child: target,
            );
      final control = interactive
          ? decorated
          : IgnorePointer(child: ExcludeFocus(child: decorated));
      if (widget.onDeleted == null) return _domainScope(data, control);
      return _domainScope(
        data,
        CallbackShortcuts(
          bindings: {
            if (widget.onDeleted != null)
              for (final key in [
                LogicalKeyboardKey.delete,
                LogicalKeyboardKey.backspace,
              ])
                SingleActivator(key): () => _remove(InteractionSource.keyboard),
          },
          child: control,
        ),
      );
    }
    // Recreate only the native visual state on keyboard activation or a live
    // reduced-motion change. This clears running ink/checkmark transitions
    // rather than freezing them halfway. The focus node and owner stay put.
    final target = KeyedSubtree(
      key: ValueKey((
        _nativeEpoch,
        data.reduceMotion,
        enabled,
        data.reduceMotion ? widget.selected : null,
      )),
      child: widget._input
          ? InputChip(
              key: widget.controlKey,
              side: widget.side,
              label: Text(widget.label),
              selected: widget.selected,
              selectedColor: widget.selectedColor,
              labelStyle: enabled && widget.foregroundColor != null
                  ? TextStyle(color: widget.foregroundColor)
                  : null,
              checkmarkColor: widget.foregroundColor,
              focusNode: _focus,
              onSelected: enabled ? (_) => _activate(_nativeSource) : null,
              onDeleted: widget.onDeleted == null
                  ? null
                  : () => _remove(_nativeSource),
              deleteIcon: widget.deleteIcon,
              deleteButtonTooltipMessage: widget.deleteLabel,
              chipAnimationStyle: data.reduceMotion
                  ? ChipAnimationStyle(
                      enableAnimation: AnimationStyle.noAnimation,
                      selectAnimation: AnimationStyle.noAnimation,
                      avatarDrawerAnimation: AnimationStyle.noAnimation,
                      deleteDrawerAnimation: AnimationStyle.noAnimation,
                    )
                  : null,
            )
          : widget._filter
          ? FilterChip(
              side: widget.side,
              shape: widget.shape,
              showCheckmark: widget.showCheckmark,
              key: widget.controlKey,
              label: Text(widget.label),
              selected: widget.selected,
              selectedColor: widget.selectedColor,
              labelStyle: enabled && widget.foregroundColor != null
                  ? TextStyle(color: widget.foregroundColor)
                  : null,
              checkmarkColor: widget.foregroundColor,
              focusNode: _focus,
              onSelected: enabled ? (_) => _activate(_nativeSource) : null,
              chipAnimationStyle: data.reduceMotion
                  ? ChipAnimationStyle(
                      enableAnimation: AnimationStyle.noAnimation,
                      selectAnimation: AnimationStyle.noAnimation,
                      avatarDrawerAnimation: AnimationStyle.noAnimation,
                      deleteDrawerAnimation: AnimationStyle.noAnimation,
                    )
                  : null,
            )
          : ChoiceChip(
              side: widget.side,
              shape: widget.shape,
              showCheckmark: widget.showCheckmark,
              key: widget.controlKey,
              label: Text(widget.label),
              selected: widget.selected,
              selectedColor: widget.selectedColor,
              labelStyle: enabled && widget.foregroundColor != null
                  ? TextStyle(color: widget.foregroundColor)
                  : null,
              checkmarkColor: widget.foregroundColor,
              focusNode: _focus,
              onSelected: enabled ? (_) => _activate(_nativeSource) : null,
              chipAnimationStyle: data.reduceMotion
                  ? ChipAnimationStyle(
                      enableAnimation: AnimationStyle.noAnimation,
                      selectAnimation: AnimationStyle.noAnimation,
                      avatarDrawerAnimation: AnimationStyle.noAnimation,
                      deleteDrawerAnimation: AnimationStyle.noAnimation,
                    )
                  : null,
            ),
    );
    final body = Semantics(
      label: widget.label,
      selected: widget.selected,
      enabled: enabled,
      button: true,
      focusable: enabled,
      focused: _focus.hasFocus,
      excludeSemantics: true,
      onTap: enabled ? () => _activate(InteractionSource.keyboard) : null,
      child: CallbackShortcuts(
        bindings: {
          if (widget.onDeleted != null)
            for (final key in [
              LogicalKeyboardKey.delete,
              LogicalKeyboardKey.backspace,
            ])
              SingleActivator(key): () => _remove(InteractionSource.keyboard),
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): () => _activate(InteractionSource.keyboard),
        },
        child: Listener(
          onPointerDown: (_) => _nativeSource = InteractionSource.pointer,
          onPointerCancel: (_) => _nativeSource = InteractionSource.keyboard,
          child: interactive
              ? target
              : IgnorePointer(child: ExcludeFocus(child: target)),
        ),
      ),
    );
    // Native InputChip owns pointer hit testing. Its two accessibility actions
    // are explicit siblings so delete is neither hidden nor merged into select.
    return !widget._input || widget.onDeleted == null
        ? body
        : Stack(
            children: [
              body,
              Positioned(
                right: 2,
                top: 0,
                bottom: 0,
                child: Semantics(
                  key: widget.deleteKey,
                  button: true,
                  enabled: true,
                  label:
                      widget.deleteLabel ??
                      MaterialLocalizations.of(context).deleteButtonTooltip,
                  onTap: () => _remove(InteractionSource.keyboard),
                  child: const SizedBox(width: 28),
                ),
              ),
            ],
          );
  }
}
