import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';
import 'starbridge_activation_origin.dart';
import '../tokens/starbridge_tokens.dart';

/// Displays the owner's projection. Does not save, confirm or debounce changes.
class StarBridgeSwitch extends StatefulWidget {
  const StarBridgeSwitch({
    required this.value,
    required this.label,
    this.onChanged,
    this.controlKey,
    this.activeTrackColor,
    super.key,
  }) : _tile = false,
       preserveNativeTile = false,
       titleWidget = null,
       rowBuilder = null,
       subtitle = null,
       subtitleWidget = null;

  /// The whole row shares the switch's single focus/semantics target and input
  /// origin. This avoids a second button or a pointer-only title tap handler.
  const StarBridgeSwitch.tile({
    required this.value,
    required this.label,
    this.subtitle,
    this.subtitleWidget,
    this.titleWidget,
    this.rowBuilder,
    this.preserveNativeTile = false,
    this.onChanged,
    this.controlKey,
    this.activeTrackColor,
    super.key,
  }) : _tile = true;

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;
  final Key? controlKey;

  /// Preserve the consumer's domain colour in native and approved suite faces.
  final Color? activeTrackColor;
  final bool _tile;

  /// Keep an existing adaptive SwitchListTile's native geometry in standard.
  /// Its row still shares this module's one input/focus/reader target.
  final bool preserveNativeTile;
  final String? subtitle;

  /// Retain the consumer's existing explanation hierarchy while the string
  /// remains the single reader hint. No extra action or business owner.
  final Widget? subtitleWidget;
  final Widget? titleWidget;

  /// Existing consumers can keep their row geometry. The supplied control
  /// is decorative here; the entire row keeps one input/focus/reader target.
  final Widget Function(Widget control)? rowBuilder;

  @override
  State<StarBridgeSwitch> createState() => _StarBridgeSwitchState();
}

class _StarBridgeSwitchState extends State<StarBridgeSwitch> {
  final _focus = FocusNode();
  final _rowControl = GlobalKey();
  InteractionSource? _source;
  int _nativeEpoch = 0;
  bool _pointerFocusPending = false;
  bool _keepStaticPointer = false;

  void _finishPointer() {
    if (mounted && _keepStaticPointer) {
      setState(() => _keepStaticPointer = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (_focus.hasFocus && !_pointerFocusPending && widget.rowBuilder != null) {
      _source = InteractionSource.keyboard;
    }
    _pointerFocusPending = false;
    if (mounted) setState(() {});
  }

  void _request(bool value, InteractionSource source) {
    if (widget.onChanged == null) return;
    setState(() {
      _source = source;
      if (source == InteractionSource.keyboard) _nativeEpoch++;
    });
    runStarBridgeSynchronousActivation(source, () => widget.onChanged!(value));
  }

  @override
  void didUpdateWidget(StarBridgeSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new native toggle starts at its projected value. Keep its external
    // focus node so keyboard/reader changes land without a travel animation.
    if (oldWidget.value != widget.value &&
        _source == InteractionSource.keyboard) {
      _nativeEpoch++;
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

  Widget _buildControl(BuildContext context) {
    final data = InteractionScope.of(context);
    final enabled = widget.onChanged != null;
    final Widget control;
    if (data.suite == InteractionSuite.standard) {
      final native = KeyedSubtree(
        key: ValueKey((
          _nativeEpoch,
          data.reduceMotion,
          data.reduceMotion ? widget.value : null,
        )),
        child: widget.preserveNativeTile
            ? Material(
                type: MaterialType.transparency,
                child: SwitchListTile.adaptive(
                  key: widget.controlKey,
                  contentPadding: EdgeInsets.zero,
                  title: widget.titleWidget ?? Text(widget.label),
                  subtitle:
                      widget.subtitleWidget ??
                      (widget.subtitle == null ? null : Text(widget.subtitle!)),
                  value: widget.value,
                  activeTrackColor: widget.activeTrackColor,
                  onChanged: enabled
                      ? (value) => _request(value, InteractionSource.pointer)
                      : null,
                ),
              )
            : Switch(
                key: widget.controlKey,
                focusNode: widget.rowBuilder == null ? _focus : null,
                value: widget.value,
                activeTrackColor: widget.activeTrackColor,
                onChanged: enabled
                    ? (value) => _request(value, InteractionSource.pointer)
                    : null,
                overlayColor: data.reduceMotion
                    ? const WidgetStatePropertyAll(Colors.transparent)
                    : null,
              ),
      );
      control = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border:
              _focus.hasFocus &&
                  (_source == InteractionSource.keyboard || data.reduceMotion)
              ? Border.all(color: data.palette.focusRing, width: 2)
              : null,
        ),
        child: TickerMode(
          enabled: data.animates && _source != InteractionSource.keyboard,
          child: native,
        ),
      );
    } else {
      control = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () => _request(!widget.value, InteractionSource.pointer)
            : null,
        child: SizedBox(
          width: 60,
          height: 48,
          child: Center(
            child: InteractionScope(
              data: widget.activeTrackColor == null
                  ? data
                  : data.copyWith(
                      palette: InteractionPalette(
                        brightness: data.palette.brightness,
                        accent: widget.activeTrackColor!,
                        accentBright: widget.activeTrackColor!,
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
              child: SuiteSwitch(
                key: widget.controlKey,
                value: widget.value,
                focusNode: widget.rowBuilder == null ? _focus : null,
                changeSource: _source,
                onChanged: enabled
                    ? (value) => _request(value, InteractionSource.pointer)
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    if (widget.rowBuilder != null ||
        (widget.preserveNativeTile &&
            data.suite == InteractionSuite.standard)) {
      // The row face can switch between native ink and static keyboard mode.
      // Reparent the same decorative control so its value travel is not lost.
      final decorativeControl = ExcludeFocus(
        child: IgnorePointer(
          child: KeyedSubtree(key: _rowControl, child: control),
        ),
      );
      final row = SuitePressable(
        kind: PressableKind.row,
        focusNode: _focus,
        baseRadius:
            Theme.of(context)
                .extension<StarBridgeTokens>()
                ?.shape
                .radiusSmall ??
            6,
        semanticLabel: widget.label,
        semanticFocused: _focus.hasFocus,
        excludeChildSemantics: true,
        onActivate: enabled
            ? (source) => _request(!widget.value, source)
            : null,
        child: widget.rowBuilder == null
            ? decorativeControl
            : widget.rowBuilder!(decorativeControl),
      );
      return Semantics(
        toggled: widget.value,
        hint: widget.subtitle,
        child: Listener(
          onPointerDown: (_) {
            // Do not replace the static gesture recognizer mid-press when
            // pointer focus returns to a formerly keyboard-operated row.
            _keepStaticPointer =
                data.suite == InteractionSuite.standard &&
                _source == InteractionSource.keyboard;
            _source = InteractionSource.pointer;
            _pointerFocusPending = enabled && !_focus.hasFocus;
            if (enabled) _focus.requestFocus();
          },
          onPointerUp: (_) => _finishPointer(),
          onPointerCancel: (_) => _finishPointer(),
          // Native InkWell focus highlights otherwise keep a fade ticker
          // after keyboard activation. Preserve the focus target but use the
          // approved static row face until the next pointer interaction.
          child: InteractionScope(
            data: data.copyWith(
              reduceMotion:
                  data.reduceMotion ||
                  data.suite == InteractionSuite.standard &&
                      (_source == InteractionSource.keyboard ||
                          _keepStaticPointer),
            ),
            child: enabled
                ? row
                : IgnorePointer(child: ExcludeFocus(child: row)),
          ),
        ),
      );
    }
    final target = widget._tile
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled
                ? () => _request(!widget.value, InteractionSource.pointer)
                : null,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: enabled,
              title: widget.titleWidget ?? Text(widget.label),
              subtitle:
                  widget.subtitleWidget ??
                  (widget.subtitle == null ? null : Text(widget.subtitle!)),
              trailing: IgnorePointer(child: control),
            ),
          )
        : control;
    return Semantics(
      label: widget.label,
      hint: widget.subtitle,
      toggled: widget.value,
      enabled: enabled,
      focusable: enabled,
      focused: _focus.hasFocus,
      onTap: enabled
          ? () => _request(!widget.value, InteractionSource.keyboard)
          : null,
      excludeSemantics: true,
      child: CallbackShortcuts(
        bindings: {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): () =>
                _request(!widget.value, InteractionSource.keyboard),
        },
        child: Listener(
          // Clear the previous instant origin before the suite's pointer tap.
          onPointerDown: (_) {
            _source = InteractionSource.pointer;
            if (enabled) _focus.requestFocus();
          },
          child: enabled
              ? target
              : IgnorePointer(child: ExcludeFocus(child: target)),
        ),
      ),
    );
  }
}
