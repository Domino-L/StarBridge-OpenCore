import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// One line per editor group (user 11-05, plan A): the group, what is chosen
/// in words, the count, and the open/closed mark. Nothing is hidden: the
/// choices are written out, and the group still opens to change them.
class ProfileEditGroupRow extends StatelessWidget {
  const ProfileEditGroupRow({
    required this.title,
    required this.summary,
    required this.open,
    this.count,
    super.key,
  });

  final String title;
  final InlineSpan summary;
  final String? count;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context).textTheme;
    final secondary = tokens.colors.textSecondary;
    final choices = Text.rich(
      summary,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.bodyMedium,
    );
    final countText = count == null
        ? null
        : Text(count!, style: theme.bodySmall?.copyWith(color: secondary));
    final mark = StarBridgeIcon(
      open ? StarBridgeIconSemantic.menuDown : StarBridgeIconSemantic.forward,
      color: secondary,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
      child: LayoutBuilder(
        // A narrow window (or large text) puts the choices under the title.
        builder: (context, box) => box.maxWidth < 520
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: theme.titleSmall)),
                      SizedBox(width: tokens.space.xs),
                      mark,
                    ],
                  ),
                  SizedBox(height: tokens.space.xxs),
                  choices,
                  ?countText,
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(title, style: theme.titleSmall),
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(child: choices),
                  if (countText != null) ...[
                    SizedBox(width: tokens.space.sm),
                    countText,
                  ],
                  SizedBox(width: tokens.space.xs),
                  mark,
                ],
              ),
      ),
    );
  }
}
