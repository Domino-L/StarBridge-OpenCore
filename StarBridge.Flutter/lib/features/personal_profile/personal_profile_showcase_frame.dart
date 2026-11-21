import 'package:flutter/material.dart';

import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Marks a subtree as the Steam-style single column (accepted preview
/// ProfileSteam, 2026-11-02). Module surfaces inside it drop their own panel
/// and render as a flat band with a title bar instead.
class ProfileShowcaseScope extends InheritedWidget {
  const ProfileShowcaseScope({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileShowcaseScope>() !=
      null;

  @override
  bool updateShouldNotify(ProfileShowcaseScope oldWidget) => false;
}

/// Band fill and hairline over the column, from the theme so the light theme
/// gets a light column.
Color profileBandFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.035)
    : Colors.black.withValues(alpha: 0.03);

Color profileHairline(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.09)
    : Colors.black.withValues(alpha: 0.09);

/// One showcase or rail section: a quiet title bar over the content.
class ProfileShowcaseBand extends StatelessWidget {
  const ProfileShowcaseBand({
    required this.title,
    required this.child,
    this.trailing,
    this.padding,
    this.fill = false,
    super.key,
  });

  /// Under a bounded height the content takes the space left by the title.
  final bool fill;
  final String title;
  final Widget? trailing;
  final Widget child;

  /// Null uses the band's standard inset; zero lets pictures run to the edge.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: profileBandFill(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            constraints: BoxConstraints(minHeight: tokens.space.xl + 16),
            padding: EdgeInsetsDirectional.fromSTEB(
              tokens.space.md,
              tokens.space.xs,
              tokens.space.sm,
              tokens.space.xs,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: profileHairline(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.colors.textPrimary,
                    ),
                  ),
                ),
                if (trailing case final trailing?) ...[
                  SizedBox(width: tokens.space.sm),
                  DefaultTextStyle.merge(
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.colors.textSecondary,
                    ),
                    child: trailing,
                  ),
                ],
              ],
            ),
          ),
          if (fill)
            Expanded(
              child: Padding(
                padding: padding ?? EdgeInsets.all(tokens.space.md),
                child: child,
              ),
            )
          else
            Padding(
              padding: padding ?? EdgeInsets.all(tokens.space.md),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// The page column: a dark (or light) translucent sheet over the wallpaper,
/// header on top, single-column showcases on the left and the side rail on
/// the right. Below 860 the rail follows the showcases.
class PersonalProfileSteamColumn extends StatefulWidget {
  const PersonalProfileSteamColumn({
    required this.header,
    required this.main,
    this.rail,
    super.key,
  });

  final Widget header;
  final Widget main;
  final Widget? rail;

  static const railWidth = 272.0;

  @override
  State<PersonalProfileSteamColumn> createState() => _SteamColumnState();
}

class _SteamColumnState extends State<PersonalProfileSteamColumn> {
  // Showcases and rail keep their state (open dialogs, drafts) when the
  // window crosses the wide/narrow width and they change parent.
  final _mainKey = GlobalKey(debugLabel: 'profile-steam-main');
  final _railKey = GlobalKey(debugLabel: 'profile-steam-rail');

  Widget get header => widget.header;
  Widget get main => KeyedSubtree(key: _mainKey, child: widget.main);
  Widget? get rail => widget.rail == null
      ? null
      : KeyedSubtree(key: _railKey, child: widget.rail!);
  double get railWidth => PersonalProfileSteamColumn.railWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ground = tokens.surfaces.ground.fill;
    return DecoratedBox(
      key: const Key('profile-steam-column'),
      decoration: BoxDecoration(
        color: ground.withValues(alpha: 0.87),
        border: Border.all(
          color: profileHairline(context).withValues(alpha: 0.5),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, outer) => Padding(
          // A phone-width window keeps the content's own width.
          padding: EdgeInsets.all(
            outer.maxWidth < 600 ? tokens.space.sm : tokens.space.xl,
          ),
          child: _content(tokens),
        ),
      ),
    );
  }

  Widget _content(StarBridgeTokens tokens) {
    return ProfileShowcaseScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = widget.rail != null && constraints.maxWidth >= 860;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              SizedBox(height: tokens.space.lg),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    SizedBox(width: tokens.space.lg),
                    SizedBox(width: railWidth, child: rail),
                  ],
                )
              else ...[
                main,
                if (rail != null) ...[SizedBox(height: tokens.space.md), rail!],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A big tabular number with a small caption under it (header stats, trade
/// card, hangar count).
class ProfileBigNumber extends StatelessWidget {
  const ProfileBigNumber({
    required this.value,
    required this.label,
    this.size = 25,
    this.color,
    super.key,
  });

  final String value;
  final String label;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: size,
            height: 1.1,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color ?? tokens.colors.textPrimary,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: tokens.colors.textSecondary),
        ),
      ],
    );
  }
}

/// Small grey caption used for sub-labels inside showcases.
class ProfileCaption extends StatelessWidget {
  const ProfileCaption(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 12, color: context.tokens.colors.textSecondary),
  );
}

/// A flat tag chip ("领航员").
class ProfileFlatTag extends StatelessWidget {
  const ProfileFlatTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.textPrimary.withValues(alpha: 0.07),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: TextStyle(fontSize: 12.5, color: tokens.colors.textPrimary),
        ),
      ),
    );
  }
}

/// Domain colour of a role category bar, shared with the hangar overview.
Color profileDomainColor(BuildContext context, DomainColorRole role) =>
    context.tokens.domainColors.resolve(role).foreground;
