import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../design_system/styles/marketplace_palette.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/remote_image.dart';
import 'marketplace_copy.dart';
import 'marketplace_diagonal.dart' show MarketParallelogramPainter;
import 'marketplace_port.dart';
import 'marketplace_price_format.dart';
import 'marketplace_silhouette.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_states.dart';

export 'marketplace_states.dart';
export 'marketplace_cards.dart';

String marketMoney(Object? value) {
  final number = marketNumber(value);
  if (number == null || !number.isFinite) return '—';
  final raw = number.round().toString();
  return raw.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]!},',
  );
}

/// A price in the format saved under 显示设置 (see [marketPriceIn]).
String marketPrice(BuildContext context, Object? value) =>
    marketPriceIn(
      value,
      format: MarketPriceFormatScope.of(context),
      locale: marketLocale(context),
    );

int? marketItemId(MarketRow row) {
  final direct = marketNumber(row['id'])?.toInt();
  if (direct != null) return direct;
  final items = marketRows(row['items']);
  return items.isEmpty ? null : marketNumber(items.first['itemId'])?.toInt();
}

/// Checklist (multi-item) orders have no single item photo; they use the SCM
/// market crate instead of borrowing the first item's picture.
const marketChecklistArt = 'asset:assets/brand/scm_market_crate.png';

bool marketIsChecklist(MarketRow row) =>
    row['displayType'] == 2 || row['checklist'] == true;

String? marketThumbnail(MarketRow row) {
  if (marketIsChecklist(row)) return marketChecklistArt;
  if (row['thumbnailUrl'] case final String image when image.isNotEmpty) {
    return image;
  }
  final items = marketRows(row['items']);
  return items.isEmpty ? null : items.first['thumbnailUrl'] as String?;
}

/// The category an item or order is filed under (0 when SCM did not say);
/// an order names it on its first item.
int marketCategoryOf(MarketRow row) =>
    marketNumber(row['categoryId'])?.toInt() ??
    marketNumber(marketRows(row['items']).firstOrNull?['categoryId'])
        ?.toInt() ??
    0;

class MarketArt extends StatelessWidget {
  const MarketArt(
    this.source, {
    this.category = 0,
    this.large = false,
    this.tint,
    this.categoryIcon = false,
    this.categoryPending = false,
    super.key,
  });

  /// An item's or order's photo; without one, its category's icon.
  MarketArt.of(MarketRow row, {this.large = false, super.key})
    : source = marketThumbnail(row),
      category = marketCategoryOf(row),
      tint = null,
      categoryIcon = false,
      categoryPending = row['categoryPending'] == true;
  final String? source;
  final int category;
  final bool large;
  final Color? tint;

  /// Category tiles always use approved local artwork, not remote images.
  final bool categoryIcon;

  /// The category is still being read: an empty panel, not the generic icon.
  final bool categoryPending;
  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    if (categoryIcon) {
      return SizedBox.expand(
        child: MarketSilhouette(category, color: colors.textPrimary),
      );
    }
    // Item photos are information buyers rely on: shown whole (contain),
    // never cropped, recoloured or covered by overlays. The bands a photo
    // leaves are filled with the same photo blurred under a dark mask, not
    // black bars (user 2026-10-23, in both themes); the loader shares the
    // bytes, a tiny decode keeps the blur cheap.
    final backdrop = Theme.of(context).brightness == Brightness.dark
        ? MarketplacePalette.artBackdrop
        : context.tokens.surfaces.ground.fill;
    Widget fallback() => categoryPending && category <= 0
        ? const SizedBox.expand()
        : MarketSilhouette(category, color: colors.textSecondary);
    final remote = source != null &&
        source!.isNotEmpty &&
        !source!.startsWith('asset:');
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: ColoredBox(
        color: backdrop,
        child: source == null || source!.isEmpty
            ? fallback()
            : !remote
            ? Image.asset(
                source!.substring(6),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback(),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    key: const ValueKey('market-art-backdrop'),
                    imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: RemoteImage(
                      source!,
                      fit: BoxFit.cover,
                      cacheWidth: 48,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  ColoredBox(
                    color: MarketplacePalette.artBackdrop.withValues(
                      alpha: 0.6,
                    ),
                  ),
                  RemoteImage(
                    source!,
                    fit: BoxFit.contain,
                    cacheWidth: large ? 900 : 420,
                    excludeFromSemantics: true,
                    // An empty panel while it loads, the icon only if it fails.
                    loadingBuilder: (_) => const SizedBox.expand(),
                    errorBuilder: (_, _, _) => fallback(),
                  ),
                ],
              ),
      ),
    );
  }
}

class MarketPrice extends StatelessWidget {
  const MarketPrice(this.value, {this.size = 15, this.unit = 'UEC', super.key});
  final Object? value;
  final double size;
  final String unit;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${marketMoney(value)}${marketNumber(value) == null ? '' : ' $unit'}',
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            marketMoney(value),
            style: TextStyle(
              fontFamily: context.tokens.typography.monoFamily,
              fontSize: size == 22
                  ? context.tokens.typography.headline
                  : context.tokens.typography.monoLarge,
              fontWeight: context.tokens.typography.emphasisWeight,
            ),
          ),
          if (marketNumber(value) != null) ...[
            const SizedBox(width: 5),
            Text(
              unit,
              style: TextStyle(
                fontSize: context.tokens.typography.label,
                color: context.tokens.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Keeps the original retry callback, copy and native geometry. No request or
/// local busy state belongs to this presentation adapter.
class MarketToggle extends StatelessWidget {
  const MarketToggle({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.fill = false,
    super.key,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  /// Stretch the slanted face across the given width, label centred.
  final bool fill;
  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.tokens.colors.accent
        : context.tokens.colors.textSecondary;
    final textStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontSize: 12);
    // The hall's slanted option: the button keeps its shared interaction
    // wrapper but draws no box of its own; the parallelogram is the face.
    // A quiet (row) target: the suites' secondary kind paints a raised fill
    // and a rectangular border at rest, which showed as a box around the
    // slant (user report, build 11). Hover is drawn by [MarketSlantFace].
    final style = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      textStyle: textStyle,
      foregroundColor: foreground,
      backgroundColor: Colors.transparent,
      overlayColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      shape: const RoundedRectangleBorder(),
    );
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        button: true,
        child: SizedBox(
          height: 28,
          child: StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            hoverFace: false,
            nativeStyle: style,
            minHeight: 28,
            padding: EdgeInsets.zero,
            onActivate: (_) => onSelected(!selected),
            child: MarketSlantFace(
              selected: selected,
              child: Container(
                width: fill ? double.infinity : null,
                alignment: fill ? Alignment.center : null,
                padding: EdgeInsets.symmetric(horizontal: fill ? 6 : 13, vertical: 4),
                child: DefaultTextStyle.merge(
                  style: textStyle?.copyWith(
                    inherit: false,
                    color: selected
                        ? context.tokens.colors.textPrimary
                        : foreground,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                  child: label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The slanted face of a hall option: accent when selected, a lighter accent
/// edge and tint while the pointer is over it, the hall line otherwise. It
/// replaces the suites' rectangular hover face on slanted controls.
class MarketSlantFace extends StatefulWidget {
  const MarketSlantFace({
    required this.selected,
    required this.child,
    this.restBorder,
    super.key,
  });
  final bool selected;
  final Widget child;
  final Color? restBorder;
  @override
  State<MarketSlantFace> createState() => _MarketSlantFaceState();
}

class _MarketSlantFaceState extends State<MarketSlantFace> {
  bool _hover = false;
  void _set(bool value) {
    if (_hover != value) setState(() => _hover = value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.colors.accent;
    return MouseRegion(
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: CustomPaint(
        painter: MarketParallelogramPainter(
          fill: widget.selected
              ? accent.withValues(alpha: .16)
              : _hover
              ? accent.withValues(alpha: .07)
              : null,
          border: widget.selected
              ? accent
              : _hover
              ? accent.withValues(alpha: .7)
              : widget.restBorder ?? marketLine(context),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Options laid out as equal-width slanted cells: as many per line as fit
/// (at least [minCell] wide), with lines balanced so no lone orphan trails.
class MarketChoiceGrid extends StatelessWidget {
  const MarketChoiceGrid({
    required this.children,
    this.minCell = 56,
    this.gap = 4,
    super.key,
  });
  final List<Widget> children;
  final double minCell, gap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = children.length;
      if (count == 0) return const SizedBox.shrink();
      if (!box.maxWidth.isFinite) {
        return Wrap(spacing: gap, runSpacing: gap, children: children);
      }
      final fit = ((box.maxWidth + gap) / (minCell + gap)).floor().clamp(1, count);
      final lines = (count / fit).ceil();
      final columns = (count / lines).ceil();
      // Rounded down a hair so float error never pushes the last cell over.
      final cell =
          ((box.maxWidth - gap * (columns - 1)) / columns * 100).floor() / 100;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: cell, child: child),
        ],
      );
    },
  );
}

class MarketRemainder extends StatelessWidget {
  const MarketRemainder({
    required this.count,
    required this.total,
    required this.open,
    super.key,
  });
  final int count, total;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: MarketDashedFrame(marketLine(context)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: marketLocale(context) == 'en' ? 'Remaining ' : '其余 ',
                  ),
                  TextSpan(
                    text: marketMoney(count),
                    style: TextStyle(
                      fontFamily: context.tokens.typography.monoFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: marketLocale(context) == 'en'
                        ? ' items have no listings'
                        : ' 种暂时没有挂单',
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 28,
            child: StarBridgeActionButton(
              kind: StarBridgeActionKind.secondary,
              onActivate: (_) => open(),
              minHeight: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              nativeStyle: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                foregroundColor: context.tokens.colors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                marketLocale(context) == 'en'
                    ? 'Show all $total'
                    : '显示全部 $total 种',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One hall message at a time (user 10-29: the 撤销 bar never went away).
/// Clears the current and queued bars first; bars come from
/// starBridgeTimedSnackBar, so even one with an action times out.
extension MarketSnackBars on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showOnly(
    SnackBar bar,
  ) {
    hideCurrentSnackBar();
    clearSnackBars();
    return showSnackBar(bar);
  }
}
