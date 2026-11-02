import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Inside an organization work surface (main fleet and communities alike,
/// user decision 2026-10-23, preview DesignPreviews/MainFleetBanner/
/// internals.html) shared controls take the holo shapes. The slant is kept
/// for choices only (filters, the search pair, section tabs); buttons and
/// tags get a bottom-right chamfer; indicators and avatars stay straight.
/// Absent (menu overlay, dialogs) the shared controls keep their own face.
class OrganizationHolo extends InheritedWidget {
  const OrganizationHolo({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrganizationHolo>() != null;

  @override
  bool updateShouldNotify(OrganizationHolo oldWidget) => false;
}

/// The holo shapes need the native control faces: an interaction suite
/// (rail, scan, glow) paints its own rounded face over them. Organization
/// pages keep one look whatever suite is chosen (user decision 2026-10-23),
/// so their shaped controls (search pair, filters, paging, tabs, composer)
/// are built with the standard suite; reduced motion, every other theme
/// setting, and the suite's own loading and other visuals are kept.
class OrganizationHoloFace extends StatelessWidget {
  const OrganizationHoloFace({
    required this.child,
    this.outsideSurface = false,
    super.key,
  });

  final Widget child;

  /// Controls of an organization page outside its work surface (the header's
  /// actions): the standard suite without the holo shapes.
  final bool outsideSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.extension<StarBridgeInteractionTheme>();
    if (!(outsideSurface || OrganizationHolo.of(context)) ||
        style == null ||
        style.suite == InteractionSuite.standard) {
      return child;
    }
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final extension in theme.extensions.values)
            if (extension is! StarBridgeInteractionTheme) extension,
          style.copyWith(suite: InteractionSuite.standard),
        ],
      ),
      child: StarBridgeInteractionRegion(child: child),
    );
  }
}

/// Horizontal run of the -24° holo slant over [height].
double organizationHoloRun(double height) =>
    height * math.tan(24 * math.pi / 180);

/// A box with optional chamfers and slanted ends, all inside its layout box:
/// [slantStart] leans the left edge, [slantEnd] the right edge (top further
/// right, as the banner's -24°); [cut] chamfers the bottom-right corner and
/// [topLeftCut] the top-left one.
class OrganizationHoloBorder extends OutlinedBorder {
  const OrganizationHoloBorder({
    super.side,
    this.cut = 0,
    this.topLeftCut = 0,
    this.slantStart = false,
    this.slantEnd = false,
  });

  final double cut, topLeftCut;
  final bool slantStart, slantEnd;

  Path _path(Rect r) {
    final run = organizationHoloRun(r.height);
    final path = Path()
      ..moveTo(r.left + (slantStart ? run : topLeftCut), r.top)
      ..lineTo(r.right, r.top);
    if (slantEnd) {
      path.lineTo(r.right - run, r.bottom);
    } else {
      path
        ..lineTo(r.right, r.bottom - cut)
        ..lineTo(r.right - cut, r.bottom);
    }
    path.lineTo(r.left, r.bottom);
    if (!slantStart && topLeftCut > 0) {
      path.lineTo(r.left, r.top + topLeftCut);
    }
    return path..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  OrganizationHoloBorder copyWith({BorderSide? side}) => OrganizationHoloBorder(
    side: side ?? this.side,
    cut: cut,
    topLeftCut: topLeftCut,
    slantStart: slantStart,
    slantEnd: slantEnd,
  );

  @override
  ShapeBorder scale(double t) => OrganizationHoloBorder(
    side: side.scale(t),
    cut: cut * t,
    topLeftCut: topLeftCut * t,
    slantStart: slantStart,
    slantEnd: slantEnd,
  );

  @override
  bool operator ==(Object other) =>
      other is OrganizationHoloBorder &&
      other.side == side &&
      other.cut == cut &&
      other.topLeftCut == topLeftCut &&
      other.slantStart == slantStart &&
      other.slantEnd == slantEnd;

  @override
  int get hashCode => Object.hash(side, cut, topLeftCut, slantStart, slantEnd);
}

/// The holo text field outline: top-left chamfer, and either a bottom-right
/// chamfer or, for the search pair, a right end in the banner slant.
class OrganizationHoloFieldBorder extends InputBorder {
  const OrganizationHoloFieldBorder({
    super.borderSide = const BorderSide(),
    this.slantEnd = false,
  });

  final bool slantEnd;

  OrganizationHoloBorder get _shape => OrganizationHoloBorder(
    side: borderSide,
    topLeftCut: 10,
    cut: 10,
    slantEnd: slantEnd,
  );

  @override
  bool get isOutline => true;

  @override
  OrganizationHoloFieldBorder copyWith({BorderSide? borderSide}) =>
      OrganizationHoloFieldBorder(
        borderSide: borderSide ?? this.borderSide,
        slantEnd: slantEnd,
      );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) => _shape.paint(canvas, rect);

  @override
  ShapeBorder scale(double t) => OrganizationHoloFieldBorder(
    borderSide: borderSide.scale(t),
    slantEnd: slantEnd,
  );

  @override
  bool operator ==(Object other) =>
      other is OrganizationHoloFieldBorder &&
      other.borderSide == borderSide &&
      other.slantEnd == slantEnd;

  @override
  int get hashCode => Object.hash(borderSide, slantEnd);
}

/// Holo colours shared by the controls above.
class OrganizationHoloColors {
  OrganizationHoloColors(BuildContext context)
    : accent = context.tokens.colors.accent,
      glass = context.tokens.colors.textPrimary.withValues(alpha: .16),
      hair = context.tokens.colors.textPrimary.withValues(alpha: .10),
      well = context.tokens.surfaces.ground.fill.withValues(alpha: .55);

  final Color accent, glass, hair, well;
}

double _lineHeight(BuildContext context) {
  final style = Theme.of(context).textTheme.bodyLarge;
  return MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 16) *
      (style?.height ?? 1.2);
}

/// Input height of a holo field: 40, or more when large text needs it. The
/// search button beside it takes the same height so their slants line up.
double organizationHoloFieldHeight(BuildContext context) =>
    math.max(40, _lineHeight(context) + 12);

/// Field decoration for a holo text field; null keeps the theme's own.
InputDecoration organizationHoloField(
  BuildContext context,
  InputDecoration decoration, {
  bool slantEnd = false,
}) {
  final c = OrganizationHoloColors(context);
  final danger = context.tokens.colors.danger;
  final pad = (organizationHoloFieldHeight(context) - _lineHeight(context)) / 2;
  OrganizationHoloFieldBorder border(Color color) =>
      OrganizationHoloFieldBorder(
        borderSide: BorderSide(color: color),
        slantEnd: slantEnd,
      );
  return decoration.copyWith(
    filled: true,
    fillColor: c.well,
    isDense: true,
    contentPadding: EdgeInsetsDirectional.fromSTEB(
      16,
      pad,
      slantEnd ? 28 : 16,
      pad,
    ),
    border: border(c.glass),
    enabledBorder: border(c.glass),
    disabledBorder: border(c.hair),
    focusedBorder: border(c.accent),
    errorBorder: border(danger),
    focusedErrorBorder: border(danger),
  );
}

/// Native button face inside a holo surface: chamfered, or a parallelogram
/// for the search button that sits against the field's slanted end.
ButtonStyle organizationHoloButton(
  BuildContext context, {
  bool primary = false,
  bool parallelogram = false,
}) {
  final c = OrganizationHoloColors(context);
  final tokens = context.tokens;
  return ButtonStyle(
    shape: WidgetStatePropertyAll(
      parallelogram
          ? const OrganizationHoloBorder(slantStart: true, slantEnd: true)
          : const OrganizationHoloBorder(cut: 8),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => primary || parallelogram
          ? BorderSide.none
          : BorderSide(
              color: states.contains(WidgetState.disabled) ? c.hair : c.glass,
            ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      // A disabled primary keeps a dim accent so its place stays visible.
      if (states.contains(WidgetState.disabled)) {
        return primary ? c.accent.withValues(alpha: .28) : Colors.transparent;
      }
      if (primary) return c.accent;
      final hover =
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused);
      return tokens.colors.textPrimary.withValues(
        alpha: parallelogram ? (hover ? .24 : .16) : (hover ? .14 : .08),
      );
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? tokens.colors.textSecondary.withValues(alpha: .6)
          : primary
          ? tokens.colors.onAccent
          : tokens.colors.textPrimary,
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: parallelogram ? 30 : 20),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
  );
}
