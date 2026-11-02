import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_choice_navigation.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'organization_holo.dart';

/// Height of the holo choice face, or more when large text needs it.
double organizationHoloChoiceHeight(BuildContext context) {
  final style = Theme.of(context).textTheme.labelLarge;
  final line =
      MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
      (style?.height ?? 1.2);
  return math.max(32, line + 12);
}

/// The holo parallelogram over its layout box. Its corners lean half a run
/// past the box on each side, so neighbours nest at their spacing.
Path organizationHoloChoicePath(Size size, {double inset = 0}) {
  final lean = organizationHoloRun(size.height) / 2;
  return Path()
    ..moveTo(lean + inset, inset)
    ..lineTo(size.width + lean - inset, inset)
    ..lineTo(size.width - lean - inset, size.height - inset)
    ..lineTo(inset - lean, size.height - inset)
    ..close();
}

/// A filter choice for holo surfaces. It paints its own slanted face instead
/// of reshaping a chip, and follows no interaction suite: holo pages keep one
/// look (user decision 2026-10-29). Selection fills along the slant, hover
/// runs one light band across it; reduced motion jumps to the end state.
/// Nothing is drawn outside the face (user 2026-10-30): a click shows no focus,
/// and keyboard focus deepens the face itself.
class OrganizationHoloChoice extends StatefulWidget {
  const OrganizationHoloChoice({
    required this.label,
    required this.selected,
    this.onSelected,
    this.onActivate,
    this.controlKey,
    this.focusNode,
    this.inGroup = false,
    this.child,
    super.key,
  });

  /// Shown as text unless [child] is given; always the choice's reader label.
  final String label;
  final bool selected;

  /// Requests !selected, as a choice chip does; null disables the choice.
  final ValueChanged<bool>? onSelected;

  /// Used instead of [onSelected] by a host that runs the activation itself.
  final ValueChanged<InteractionSource>? onActivate;
  final Key? controlKey;

  /// The host's node, when it moves focus between its choices.
  final FocusNode? focusNode;

  /// One of a mutually exclusive group, for the reader.
  final bool inGroup;
  final Widget? child;

  @override
  State<OrganizationHoloChoice> createState() => _OrganizationHoloChoiceState();
}

class _OrganizationHoloChoiceState extends State<OrganizationHoloChoice>
    with TickerProviderStateMixin {
  FocusNode? _ownFocus;
  late FocusNode _focus = widget.focusNode ?? (_ownFocus = FocusNode());
  late final _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.selected ? 1 : 0,
  );
  late final _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  late final _band = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _pressed = false;
  bool _reduceMotion = false;

  // Focus taken by a press is not shown; it clears when focus leaves.
  bool _focusFromPointer = false;

  bool get _enabled => widget.onSelected != null || widget.onActivate != null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
  }

  void _refresh() {
    if (!_focus.hasFocus) _focusFromPointer = false;
    if (mounted) setState(() {});
  }

  void _highlightChanged(FocusHighlightMode _) => _refresh();

  void _to(AnimationController controller, double value) {
    if (_reduceMotion) {
      controller.value = value;
    } else {
      controller.animateTo(value, curve: Curves.easeOutCubic);
    }
  }

  void _activate(InteractionSource source) {
    if (source == InteractionSource.keyboard && _focusFromPointer) {
      setState(() => _focusFromPointer = false);
    }
    final onActivate = widget.onActivate;
    if (onActivate != null) {
      onActivate(source);
      return;
    }
    final onSelected = widget.onSelected;
    if (onSelected == null) return;
    unawaited(
      runStarBridgeActivation<void>(source, () => onSelected(!widget.selected)),
    );
  }

  void _setHover(bool hovered) {
    _to(_hover, hovered ? 1 : 0);
    if (hovered && !_reduceMotion && _enabled) _band.forward(from: 0);
  }

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  void didUpdateWidget(OrganizationHoloChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focus.removeListener(_refresh);
      _ownFocus?.dispose();
      _ownFocus = null;
      _focus = widget.focusNode ?? (_ownFocus = FocusNode());
      _focus.addListener(_refresh);
    }
    if (widget.selected != oldWidget.selected) {
      _to(_fill, widget.selected ? 1 : 0);
    }
    if (!_enabled) {
      _pressed = false;
      _hover.value = 0;
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    _focus.removeListener(_refresh);
    _ownFocus?.dispose();
    _fill.dispose();
    _hover.dispose();
    _band.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final reduce = InteractionScope.of(context).reduceMotion;
        if (reduce && !_reduceMotion) {
          _fill.value = widget.selected ? 1 : 0;
          _band.value = 0;
        }
        _reduceMotion = reduce;
        return _build(context);
      },
    ),
  );

  Widget _build(BuildContext context) {
    final tokens = context.tokens;
    final holo = OrganizationHoloColors(context);
    final height = organizationHoloChoiceHeight(context);
    final focused =
        _focus.hasFocus &&
        !_focusFromPointer &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final foreground = widget.selected
        ? tokens.colors.textPrimary
        : tokens.colors.textSecondary;
    final labelStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: foreground);
    final face = ListenableBuilder(
      listenable: Listenable.merge([_fill, _hover, _band]),
      builder: (context, child) => CustomPaint(
        painter: _HoloChoicePainter(
          fill: _fill.value,
          hover: _hover.value,
          band: _band.isAnimating ? _band.value : null,
          pressed: _pressed,
          focused: focused,
          accent: holo.accent,
          glass: holo.glass,
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          widthFactor: 1,
          child: widget.child == null
              ? Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  style: labelStyle,
                )
              : DefaultTextStyle.merge(style: labelStyle, child: widget.child!),
        ),
      ),
    );
    return Semantics(
      label: widget.label,
      selected: widget.selected,
      enabled: _enabled,
      button: true,
      focusable: _enabled,
      focused: _focus.hasFocus,
      inMutuallyExclusiveGroup: widget.inGroup ? true : null,
      excludeSemantics: true,
      onTap: _enabled ? () => _activate(InteractionSource.keyboard) : null,
      child: CallbackShortcuts(
        bindings: {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): () => _activate(InteractionSource.keyboard),
        },
        child: Focus(
          focusNode: _focus,
          canRequestFocus: _enabled,
          skipTraversal: !_enabled,
          child: MouseRegion(
            cursor: _enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => _setHover(true),
            onExit: (_) => _setHover(false),
            child: GestureDetector(
              key: widget.controlKey,
              behavior: HitTestBehavior.opaque,
              onTapDown: _enabled
                  ? (_) {
                      _focusFromPointer = true;
                      _setPressed(true);
                    }
                  : null,
              onTapCancel: _enabled
                  ? () {
                      if (!_focus.hasFocus) _focusFromPointer = false;
                      _setPressed(false);
                    }
                  : null,
              onTapUp: _enabled ? (_) => _setPressed(false) : null,
              onTap: _enabled
                  ? () {
                      _focus.requestFocus();
                      _activate(InteractionSource.pointer);
                    }
                  : null,
              child: Opacity(
                opacity: _enabled ? 1 : .45,
                child: SizedBox(height: height, child: face),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoloChoicePainter extends CustomPainter {
  const _HoloChoicePainter({
    required this.fill,
    required this.hover,
    required this.band,
    required this.pressed,
    required this.focused,
    required this.accent,
    required this.glass,
  });

  final double fill, hover;
  final double? band;
  final bool pressed, focused;
  final Color accent, glass;

  // A slanted strip of the face from [start] to [end] across its width.
  Path _strip(Size size, double start, double end) {
    final lean = organizationHoloRun(size.height) / 2;
    return Path()
      ..moveTo(start + lean, 0)
      ..lineTo(end + lean, 0)
      ..lineTo(end - lean, size.height)
      ..lineTo(start - lean, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final face = organizationHoloChoicePath(size);
    final travel = size.width;
    canvas.save();
    canvas.clipPath(face);
    if (hover > 0 || pressed) {
      canvas.drawPath(
        face,
        Paint()..color = accent.withValues(alpha: pressed ? .22 : .08 * hover),
      );
    }
    if (fill > 0) {
      canvas.drawPath(
        _strip(size, 0, travel * fill),
        Paint()..color = accent.withValues(alpha: .18),
      );
      // The leading bar marks the chosen face without relying on the fill.
      canvas.drawPath(
        _strip(size, 0, 3),
        Paint()..color = accent.withValues(alpha: fill),
      );
    }
    final bandAt = band;
    if (bandAt != null) {
      final x = travel * bandAt - 10;
      canvas.drawPath(
        _strip(size, x, x + 18),
        Paint()
          ..color = accent.withValues(alpha: .22 * math.sin(bandAt * math.pi)),
      );
    }
    canvas.restore();
    final emphasis = math.max(fill, hover * .6);
    canvas.drawPath(
      organizationHoloChoicePath(size, inset: .5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(glass, accent, emphasis)!,
    );
    if (focused) {
      // Inside the face only: a deeper tint and a heavier edge of its own.
      canvas.drawPath(face, Paint()..color = accent.withValues(alpha: .12));
      canvas.drawPath(
        organizationHoloChoicePath(size, inset: 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_HoloChoicePainter old) =>
      old.fill != fill ||
      old.hover != hover ||
      old.band != band ||
      old.pressed != pressed ||
      old.focused != focused ||
      old.accent != accent ||
      old.glass != glass;
}

/// The holo face for a section tab, for [StarBridgeChoiceNavigation].
Widget organizationHoloNavigationFace(
  BuildContext context,
  StarBridgeNavigationChoice choice,
  bool selected,
  FocusNode focusNode,
  ValueChanged<InteractionSource> activate,
) => OrganizationHoloChoice(
  controlKey: choice.controlKey,
  label: choice.label,
  selected: selected,
  focusNode: focusNode,
  inGroup: true,
  onActivate: choice.enabled ? activate : null,
  child: choice.child,
);

/// The same slanted outline for a static holo control, such as the sort box
/// beside the filters, so the row keeps one look.
class OrganizationHoloChoiceFrame extends StatelessWidget {
  const OrganizationHoloChoiceFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = organizationHoloChoiceHeight(context);
    return CustomPaint(
      painter: _HoloChoicePainter(
        fill: 0,
        hover: 0,
        band: null,
        pressed: false,
        focused: false,
        accent: OrganizationHoloColors(context).accent,
        glass: OrganizationHoloColors(context).glass,
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(widthFactor: 1, child: child),
        ),
      ),
    );
  }
}
