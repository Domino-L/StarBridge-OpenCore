import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

/// Owns native ink, not focus, layout, gestures or commands. Call resolveStyle
/// each build with the live widget/theme styles, and dispose with the caller.
/// Retiring paint never replaces an InkWell or cancels a pending pointer.
class StarBridgeNativeInk {
  StarBridgeNativeInk() {
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    KeyboardModality.retain();
    KeyboardModality.listenable.addListener(_modalityChanged);
  }

  // Native buttons enter the focused state on any focus, including focus a
  // closing menu hands back after a click. Paint it only for keyboard input.
  void _modalityChanged() => _highlightModeChanged(FocusHighlightMode.touch);

  static Set<WidgetState> _keyboardStates(Set<WidgetState> s) =>
      KeyboardModality.showsFocus ? s : ({...s}..remove(WidgetState.focused));

  // The ink tint also follows the native touch rule (no focus tint in touch
  // mode); the frame keeps native focus semantics apart from pointer focus.
  static Set<WidgetState> _paintStates(Set<WidgetState> s) =>
      FocusManager.instance.highlightMode == FocusHighlightMode.touch
      ? ({...s}..remove(WidgetState.focused))
      : _keyboardStates(s);

  final states = WidgetStatesController();
  final _features = <InteractiveInkFeature>{};
  bool? _animated;
  ButtonStyle _style = const ButtonStyle();
  ButtonStyle? _theme;
  Color _fallback = Colors.transparent;

  void _highlightModeChanged(FocusHighlightMode _) {
    // Focus may stay on an autofocus target while input modality changes.
    // Re-resolve paint without changing focus, gestures or command ownership.
    states.value = {...states.value};
  }

  void retire() {
    for (final feature in _features.toList()) {
      feature.dispose();
    }
  }

  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    KeyboardModality.listenable.removeListener(_modalityChanged);
    KeyboardModality.release();
    retire();
    states.dispose();
  }

  Color _inkColor() {
    final pressed = {...states.value, WidgetState.pressed};
    return _style.overlayColor?.resolve(pressed) ??
        _theme?.overlayColor?.resolve(pressed) ??
        _fallback;
  }

  ButtonStyle resolveStyle(
    BuildContext context, {
    required bool animated,
    required ButtonStyle style,
    required ButtonStyle? themeStyle,
  }) {
    if (_animated != animated) retire();
    _animated = animated;
    _style = style;
    _theme = themeStyle;
    _fallback = Theme.of(context).splashColor;
    Color? fill(Set<WidgetState> s) =>
        _style.backgroundColor?.resolve(s) ??
        _theme?.backgroundColor?.resolve(s);
    Color? overlay(Set<WidgetState> s) =>
        _style.overlayColor?.resolve(s) ?? _theme?.overlayColor?.resolve(s);
    return style.copyWith(
      animationDuration: Duration.zero,
      splashFactory: animated
          ? _RetiringSplashFactory(
              delegate:
                  style.splashFactory ??
                  themeStyle?.splashFactory ??
                  Theme.of(context).splashFactory,
              features: _features,
              color: _inkColor,
            )
          : NoSplash.splashFactory,
      // InkHighlight captures its initial alpha in an independent tween.
      // Keep it transparent from creation, and paint state changes directly.
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        final paintStates = _paintStates(s);
        final background = fill(s), tint = overlay(paintStates);
        return tint == null
            ? background
            : Color.alphaBlend(tint, background ?? Colors.transparent);
      }),
      side: switch (style.side ?? themeStyle?.side) {
        final side? => WidgetStateProperty.resolveWith(
          (s) => side.resolve(_keyboardStates(s)),
        ),
        null => null,
      },
    );
  }
}

class _RetiringSplashFactory extends InteractiveInkFeatureFactory {
  const _RetiringSplashFactory({
    required this.delegate,
    required this.features,
    required this.color,
  });
  final InteractiveInkFeatureFactory delegate;
  final Set<InteractiveInkFeature> features;
  final ValueGetter<Color> color;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    final feature = _DelegatedInkFeature(
      controller: controller,
      referenceBox: referenceBox,
      resolveColor: this.color,
      customBorder: customBorder,
      onRemoved: onRemoved,
      features: features,
    );
    features.add(feature);
    feature.delegate = delegate.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: this.color(),
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: feature.finish,
    );
    return feature;
  }
}

/// InkWell writes its highlight colour into its current splash on rebuild.
/// The real theme feature stays registered and paints once; this no-op handle
/// forwards its lifetime/shape/gesture but resolves splash colour independently.
class _DelegatedInkFeature extends InteractiveInkFeature {
  _DelegatedInkFeature({
    required super.controller,
    required super.referenceBox,
    required this.resolveColor,
    required this.features,
    super.customBorder,
    super.onRemoved,
  }) : super(color: resolveColor()) {
    controller.addInkFeature(this);
  }
  final ValueGetter<Color> resolveColor;
  final Set<InteractiveInkFeature> features;
  late InteractiveInkFeature delegate;
  bool _finished = false, _delegateRemoved = false;

  @override
  Color get color => delegate.color;
  @override
  set color(Color value) {
    if (!_finished) delegate.color = resolveColor();
  }

  @override
  set customBorder(ShapeBorder? value) {
    super.customBorder = value;
    if (!_finished) delegate.customBorder = value;
  }

  @override
  void confirm() {
    if (!_finished) delegate.confirm();
  }

  @override
  void cancel() {
    if (!_finished) delegate.cancel();
  }

  void finish() {
    if (_finished) return;
    _delegateRemoved = true;
    dispose();
  }

  @override
  void dispose() {
    if (_finished) return;
    _finished = true;
    if (!_delegateRemoved) delegate.dispose();
    features.remove(this);
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {}
}
