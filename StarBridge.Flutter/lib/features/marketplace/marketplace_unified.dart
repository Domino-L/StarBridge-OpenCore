import 'package:flutter/material.dart';

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_states.dart' show marketButtonAction;
import 'marketplace_widgets.dart' show marketMoney, marketPrice;

// Shared pieces that carry the hall's language onto every page (2026-10-20):
// one tab style, one filter option style and one stat strip. Each target is a
// StarBridgeActionRow, so focus, screen-reader activation, selected semantics
// and the four interaction suites stay the same as everywhere else.

/// One entry of [MarketSubTabs].
@immutable
class MarketSubTab {
  const MarketSubTab(
    this.label, {
    required this.selected,
    required this.onTap,
    this.count,
    this.controlKey,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Shown after the label in mono ("出售 3").
  final Object? count;
  final Key? controlKey;
}

/// Second-level tabs in the hall's style: text, slanted dividers and a short
/// underline with a slanted tail under the selected one.
class MarketSubTabs extends StatelessWidget {
  const MarketSubTabs(this.tabs, {super.key});
  final List<MarketSubTab> tabs;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < tabs.length; i++) ...[
        if (i > 0) const MarketSlantDivider(height: 14),
        _SubTab(tabs[i]),
      ],
    ],
  );
}

class _SubTab extends StatefulWidget {
  const _SubTab(this.tab);
  final MarketSubTab tab;
  @override
  State<_SubTab> createState() => _SubTabState();
}

class _SubTabState extends State<_SubTab> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tab = widget.tab;
    final selected = tab.selected;
    // A native text button through the shared feedback wrapper: it keeps
    // native focus, Enter/Space and reader activation in every suite; the
    // hall's underline is the only selected face (no fill, no hover box).
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: MergeSemantics(
        child: Semantics(
          selected: selected,
          button: true,
          child: marketButtonAction(
            key: tab.controlKey ?? ValueKey(('market-subtab', tab.label)),
            hoverFace: false,
            TextButton(
              onPressed: tab.onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(),
                foregroundColor: t.colors.textPrimary,
                overlayColor: Colors.transparent,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      text: tab.label,
                      children: [
                        if (tab.count != null)
                          TextSpan(
                            text: ' ${tab.count}',
                            style: TextStyle(
                              fontFamily: t.typography.monoFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: t.colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected || hover
                          ? t.colors.textPrimary
                          : t.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipPath(
                    clipper: const _TailClipper(),
                    child: AnimatedContainer(
                      duration: t.motion.surfaceExit,
                      height: 2,
                      width: selected
                          ? 22
                          : hover
                          ? 16
                          : 0,
                      color: selected
                          ? t.colors.accent
                          : t.colors.textSecondary.withValues(alpha: .6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TailClipper extends CustomClipper<Path> {
  const _TailClipper();
  @override
  Path getClip(Size size) {
    final run = marketSlantRun(size.height) * 2;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo((size.width - run).clamp(0, size.width), size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_TailClipper oldClipper) => false;
}

/// One figure in a [MarketStatStrip].
@immutable
class MarketStat {
  const MarketStat(this.label, this.value, {this.color, this.mono = true});
  final String label;
  final Object value;
  final Color? color;
  final bool mono;
}

/// The banner's way of showing numbers: label over value, separated by
/// slanted dividers, on a flat panel. Replaces the older bar-marked strips.
class MarketStatStrip extends StatelessWidget {
  const MarketStatStrip(this.stats, {this.trailing, super.key});
  final List<MarketStat> stats;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const MarketSlantDivider(height: 34),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stats[i].label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  stats[i].value is Widget
                      ? stats[i].value as Widget
                      : Text(
                          '${stats[i].value}',
                          style: TextStyle(
                            fontFamily: stats[i].mono
                                ? t.typography.monoFamily
                                : null,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: stats[i].color ?? t.colors.textPrimary,
                          ),
                        ),
                ],
              ),
            ),
          ],
          ?trailing,
        ],
      ),
    );
  }
}

/// "¤ 1,200,000": the hall's money style without a side verb, for tables
/// whose tab already says sell or buy.
class MarketGoldPrice extends StatelessWidget {
  const MarketGoldPrice(this.value, {this.size = 15, super.key});
  final Object? value;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (marketNumber(value) == null) {
      return Text('—', style: TextStyle(color: t.colors.textSecondary));
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '¤ ',
            style: TextStyle(
              fontSize: size - 2,
              color: MarketplacePalette.gold.withValues(alpha: .8),
            ),
          ),
          TextSpan(text: marketPrice(context, value)),
        ],
      ),
      semanticsLabel: '¤ ${marketMoney(value)}',
      maxLines: 1,
      style: TextStyle(
        fontFamily: t.typography.monoFamily,
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: MarketplacePalette.gold,
      ),
    );
  }
}
