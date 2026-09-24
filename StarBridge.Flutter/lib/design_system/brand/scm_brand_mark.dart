import 'package:flutter/material.dart';

import '../styles/scm_brand_style.dart';
import '../tokens/starbridge_tokens.dart';

enum ScmBrandMarkScale { compact, standard }

class ScmBrandMark extends StatelessWidget {
  const ScmBrandMark({this.scale = ScmBrandMarkScale.standard, super.key});

  const ScmBrandMark.compact({super.key}) : scale = ScmBrandMarkScale.compact;

  static const markAssetPath = 'assets/brand/scm_mark.png';
  static const wordmarkAssetPath = 'assets/brand/scm_wordmark.png';

  final ScmBrandMarkScale scale;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final compact = scale == ScmBrandMarkScale.compact;
    final markExtent = compact ? 22.0 : 56.0;
    final wordmarkHeight = compact ? 0.0 : 20.0;
    final horizontalPadding = compact ? tokens.space.xs : tokens.space.sm;
    final verticalPadding = compact ? tokens.space.xxs : tokens.space.xs;

    return Semantics(
      image: true,
      label: 'SCM',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ScmBrandStyle.surface,
            borderRadius: tokens.shape.small,
            border: Border.all(
              color: ScmBrandStyle.border,
              width: tokens.stroke.hairline,
            ),
          ),
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
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
                if (!compact) ...[
                  SizedBox(width: tokens.space.md),
                  Image.asset(
                    wordmarkAssetPath,
                    height: wordmarkHeight,
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
