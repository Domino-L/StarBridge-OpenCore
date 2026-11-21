import 'package:flutter/material.dart';

import '../styles/scm_brand_style.dart';
import '../tokens/starbridge_tokens.dart';

enum ScmBrandMarkScale { compact, standard }

class ScmBrandMark extends StatelessWidget {
  const ScmBrandMark({
    this.scale = ScmBrandMarkScale.standard,
    this.framed = true,
    super.key,
  });

  const ScmBrandMark.compact({super.key})
    : scale = ScmBrandMarkScale.compact,
      framed = true;

  static const markAssetPath = 'assets/brand/scm_mark.png';
  static const wordmarkAssetPath = 'assets/brand/scm_wordmark.png';

  final ScmBrandMarkScale scale;

  /// Without the dark plate (help page header, user 11-16). The upstream
  /// assets are light grey, so on a light surface they take the text colours.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final compact = scale == ScmBrandMarkScale.compact;
    final markExtent = compact ? 22.0 : 56.0;
    final wordmarkHeight = compact ? 0.0 : 20.0;
    final horizontalPadding = compact ? tokens.space.xs : tokens.space.sm;
    final verticalPadding = compact ? tokens.space.xxs : tokens.space.xs;
    // Unframed keeps the same padding, so the tap target does not shrink (the
    // plate's border is painted inside it).
    final onLight = !framed && Theme.of(context).brightness == Brightness.light;
    final markTint = onLight ? tokens.colors.textPrimary : null;
    final wordmarkTint = onLight ? tokens.colors.textSecondary : null;

    return Semantics(
      image: true,
      label: 'SCM',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: framed
              ? BoxDecoration(
                  color: ScmBrandStyle.surface,
                  borderRadius: tokens.shape.small,
                  border: Border.all(
                    color: ScmBrandStyle.border,
                    width: tokens.stroke.hairline,
                  ),
                )
              : const BoxDecoration(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  markAssetPath,
                  width: markExtent,
                  height: markExtent,
                  color: markTint,
                  colorBlendMode: markTint == null ? null : BlendMode.srcIn,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
                if (!compact) ...[
                  SizedBox(width: tokens.space.md),
                  Image.asset(
                    wordmarkAssetPath,
                    height: wordmarkHeight,
                    color: wordmarkTint,
                    colorBlendMode: wordmarkTint == null
                        ? null
                        : BlendMode.srcIn,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
