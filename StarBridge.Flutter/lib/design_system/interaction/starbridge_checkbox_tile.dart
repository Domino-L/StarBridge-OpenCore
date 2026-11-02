import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';
import 'starbridge_activation_origin.dart';

/// One accessible row for a controlled checkbox. The caller owns selection,
/// limits and persistence; the row only forwards an immediate change request.
class StarBridgeCheckboxTile extends StatefulWidget {
  const StarBridgeCheckboxTile({
    required this.value,
    required this.label,
    this.onChanged,
    this.controlKey,
    this.subtitle,
    this.titleWidget,
    this.dense = true,
    this.trailingControl = false,
    this.activeColor,
    this.contentPadding = EdgeInsets.zero,
    this.rowBuilder,
    this.autofocus = false,
    this.checkboxScale = 1,
    this.compactTarget = false,
    this.mixed = false,
    this.visualDensity,
    super.key,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;
  final Key? controlKey;
  final String? subtitle;
  final Widget? titleWidget;
  final bool dense, trailingControl;
  final Color? activeColor;
  final EdgeInsetsGeometry contentPadding;

  /// Preserve a consumer's existing row instead of imposing ListTile geometry.
  /// The supplied checkbox is decorative; this adapter keeps one activation.
  final Widget Function(Widget control)? rowBuilder;

  /// Focus the row when its scope has no focus yet (dialog first field).
  final bool autofocus;

  /// Native CheckboxListTile geometry for consumers migrating from it:
  /// [compactTarget] shrink-wraps the standard checkbox's tap target and
  /// [checkboxScale] matches its `checkboxScaleFactor`.
  final double checkboxScale;
  final bool compactTarget;

  /// Partially selected (a "select all" over a partial selection): shown as
  /// the native/suite tristate mark and spoken as mixed. Activation still
  /// requests `!value`; the caller decides what that means.
  final bool mixed;

  /// The consumer's original standard checkbox density.
  final VisualDensity? visualDensity;

  @override
  State<StarBridgeCheckboxTile> createState() => _StarBridgeCheckboxTileState();
}

class _StarBridgeCheckboxTileState extends State<StarBridgeCheckboxTile> {
  final _focus = FocusNode();
  InteractionSource? _source;
  bool? _requestedValue;
  int _nativeEpoch = 0;
  bool _pointerFocusPending = false;

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
    if (_focus.hasFocus && !_pointerFocusPending) {
      _source = InteractionSource.keyboard;
    }
    _pointerFocusPending = false;
    if (mounted) setState(() {});
  }

  void _request(InteractionSource source) {
    if (widget.onChanged == null) return;
    setState(() {
      _source = source;
      _requestedValue = !widget.value;
      if (source == InteractionSource.keyboard) _nativeEpoch++;
    });
    unawaited(
      runStarBridgeActivation<void>(
        source,
        () => widget.onChanged!(!widget.value),
      ),
    );
  }

  @override
  void didUpdateWidget(StarBridgeCheckboxTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (_requestedValue != widget.value) {
        _source = InteractionSource.programmatic;
      } else if (_source == InteractionSource.keyboard) {
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
      StarBridgeInteractionRegion(child: Builder(builder: _buildRow));

  Widget _buildRow(BuildContext context) {
    final data = InteractionScope.of(context);
    final enabled = widget.onChanged != null;
    final Widget checkbox;
    if (data.suite == InteractionSuite.standard) {
      final native = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border:
              _focus.hasFocus &&
                  (_source == InteractionSource.keyboard || data.reduceMotion)
              ? Border.all(color: data.palette.focusRing, width: 2)
              : null,
        ),
        child: TickerMode(
          enabled: data.animates && _source != InteractionSource.keyboard,
          child: KeyedSubtree(
            key: ValueKey((
              _nativeEpoch,
              data.reduceMotion,
              data.reduceMotion ? widget.value : null,
            )),
            child: Checkbox(
              activeColor: widget.activeColor,
              key: widget.controlKey,
              materialTapTargetSize: widget.compactTarget
                  ? MaterialTapTargetSize.shrinkWrap
                  : null,
              visualDensity: widget.visualDensity,
              tristate: widget.mixed,
              value: widget.mixed ? null : widget.value,
              focusNode: _focus,
              onChanged: enabled
                  ? (_) => _request(InteractionSource.pointer)
                  : null,
              overlayColor: data.reduceMotion
                  ? const WidgetStatePropertyAll(Colors.transparent)
                  : null,
            ),
          ),
        ),
      );
      checkbox = widget.checkboxScale == 1
          ? native
          : Transform.scale(scale: widget.checkboxScale, child: native);
    } else {
      checkbox = SizedBox(
        width: widget.rowBuilder == null ? 40 : 48,
        height: widget.rowBuilder == null ? 40 : 48,
        child: Center(
          child: InteractionScope(
            data: widget.activeColor == null
                ? data
                : data.copyWith(
                    palette: InteractionPalette(
                      brightness: data.palette.brightness,
                      accent: widget.activeColor!,
                      accentBright: widget.activeColor!,
                      onAccent: data.palette.onAccent,
                      selectedFill: data.palette.selectedFill,
                      surface: data.palette.surface,
                      raised: data.palette.raised,
                      border: data.palette.border,
                      textPrimary: data.palette.textPrimary,
                      textSecondary: data.palette.textSecondary,
                      textDisabled: data.palette.textDisabled,
                      focusRing: data.palette.focusRing,
                      success: data.palette.success,
                      onSuccess: data.palette.onSuccess,
                      danger: data.palette.danger,
                      onDanger: data.palette.onDanger,
                      warning: data.palette.warning,
                    ),
                  ),
            child: SuiteCheckbox(
              key: widget.controlKey,
              tristate: widget.mixed,
              value: widget.mixed ? null : widget.value,
              focusNode: _focus,
              changeSource: _source,
              onChanged: enabled
                  ? (_) => _request(InteractionSource.pointer)
                  : null,
            ),
          ),
        ),
      );
    }
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _request(InteractionSource.pointer) : null,
      child:
          widget.rowBuilder?.call(IgnorePointer(child: checkbox)) ??
          ListTile(
            dense: widget.dense,
            contentPadding: widget.contentPadding,
            enabled: enabled,
            leading: widget.trailingControl
                ? null
                : IgnorePointer(child: checkbox),
            trailing: widget.trailingControl
                ? IgnorePointer(child: checkbox)
                : null,
            title: widget.titleWidget ?? Text(widget.label),
            subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
          ),
    );
    return Semantics(
      label: widget.label,
      hint: widget.subtitle,
      checked: widget.mixed ? null : widget.value,
      mixed: widget.mixed ? true : null,
      enabled: enabled,
      focusable: enabled,
      focused: _focus.hasFocus,
      excludeSemantics: true,
      onTap: enabled ? () => _request(InteractionSource.keyboard) : null,
      child: CallbackShortcuts(
        bindings: {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): () => _request(InteractionSource.keyboard),
        },
        child: Listener(
          onPointerDown: (_) {
            _source = InteractionSource.pointer;
            _pointerFocusPending = enabled && !_focus.hasFocus;
            if (enabled) _focus.requestFocus();
          },
          child: enabled ? row : IgnorePointer(child: ExcludeFocus(child: row)),
        ),
      ),
    );
  }
}
