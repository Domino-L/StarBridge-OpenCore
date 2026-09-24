import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_creation_port.dart';
import 'legacy_community_tag_catalog.dart';

/// WPF separators plus the middle dot emitted by the Flutter editor.
List<String> communityTagNames(String value) => value
    .split(RegExp(r'[/·、,，;；|]'))
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty && part != '未公开')
    .toSet()
    .toList();

/// Presentation only: no catalog fetches and no rewrite of unknown saved tags.
class CommunityGameplayTags extends StatelessWidget {
  const CommunityGameplayTags({
    required this.value,
    this.options,
    this.maxVisible,
    this.maxTagWidth,
    this.fitAvailableSpace = false,
    super.key,
  });
  final String value;
  final CommunityCreationOptions? options;
  final int? maxVisible;
  final double? maxTagWidth;

  /// Card summaries fit real label sizes into their bounded area. Other uses
  /// retain the unrestricted wrapping layout.
  final bool fitAvailableSpace;

  @override
  Widget build(BuildContext context) {
    final names = communityTagNames(value);
    if (!fitAvailableSpace) {
      return _wrap(context, names, maxVisible ?? names.length, maxTagWidth);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return _wrap(context, names, names.length, maxTagWidth);
        }
        final width = constraints.maxWidth;
        final labelWidth = (width - 22).clamp(0.0, double.infinity);
        final style = Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontWeight: FontWeight.w600);
        Size measure(String text, TextStyle? textStyle, double maxWidth) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(textStyle),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.localeOf(context),
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: maxWidth);
          final size = painter.size;
          painter.dispose();
          return size;
        }

        final sizes = [
          for (final name in names)
            measure(_option(name)?.name ?? name, style, labelWidth) +
                const Offset(22, 12),
        ];
        bool fits(Iterable<Size> items) {
          double usedWidth = 0, usedHeight = 0, rowHeight = 0;
          var empty = true;
          for (final size in items) {
            if (!empty && usedWidth + 8 + size.width > width) {
              usedHeight += rowHeight + 4;
              usedWidth = 0;
              rowHeight = 0;
              empty = true;
            }
            usedWidth += (empty ? 0 : 8) + size.width;
            if (size.height > rowHeight) rowHeight = size.height;
            empty = false;
            if (usedHeight + rowHeight > constraints.maxHeight) return false;
          }
          return true;
        }

        var visible = names.length;
        if (!fits(sizes)) {
          for (visible = names.length - 1; visible > 0; visible--) {
            final more =
                measure('+${names.length - visible}', null, width) +
                const Offset(0, 10);
            if (fits([...sizes.take(visible), more])) break;
          }
        }
        return _wrap(context, names, visible, width);
      },
    );
  }

  Widget _wrap(
    BuildContext context,
    List<String> names,
    int visible,
    double? tagWidth,
  ) => Wrap(
    spacing: 8,
    runSpacing: fitAvailableSpace ? 4 : 8,
    children: [
      for (final name in names.take(visible)) _tag(context, name, tagWidth),
      if (names.length > visible)
        Tooltip(
          message: names.skip(visible).join(' · '),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text('+${names.length - visible}'),
          ),
        ),
    ],
  );

  CommunityTagOption? _option(String name) {
    for (final candidate in [
      ...?options?.tags,
      ...LegacyCommunityTagCatalog.tags,
    ]) {
      if (candidate.name.toLowerCase() == name.toLowerCase() ||
          candidate.id.toLowerCase() == name.toLowerCase()) {
        return candidate;
      }
    }
    return null;
  }

  Widget _tag(BuildContext context, String name, double? tagWidth) {
    final tag = _option(name);
    CommunityTagCategory? category;
    for (final candidate in [
      ...?options?.categories,
      ...LegacyCommunityTagCatalog.categories,
    ]) {
      if (candidate.id == tag?.categoryId) {
        category = candidate;
        break;
      }
    }
    final accent = category == null
        ? context.tokens.colors.textSecondary
        : Color(
            0xff000000 | int.parse(category.accentHex.substring(1), radix: 16),
          );
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? accent
        : Color.lerp(accent, Colors.black, .48)!;
    final label = tag?.name ?? name;
    return Tooltip(
      message: tag == null
          ? name
          : '${category?.name ?? ''} · $label\n${tag.description}',
      child: Container(
        constraints: tagWidth == null
            ? null
            : BoxConstraints(maxWidth: tagWidth),
        key: ValueKey('community-gameplay-tag-$name'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .14),
          border: Border.all(color: accent.withValues(alpha: .68)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          maxLines: tagWidth == null ? null : 1,
          overflow: tagWidth == null ? null : TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
