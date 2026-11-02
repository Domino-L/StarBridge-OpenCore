import '../../shared/guide/guide_scope.dart';
import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import '../../design_system/styles/marketplace_palette.dart';

import '../../design_system/icons/favorite_icon.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_hall_drawers.dart';
import 'marketplace_hover.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_publish_entry.dart';
import 'marketplace_states.dart' show marketButtonAction;
import 'marketplace_price_format.dart' show showMarketDisplaySettings;
import 'marketplace_trade_style.dart';

const _scmOrange = MarketplacePalette.scmOrange;

/// The trading hall's full-bleed head: the SCM plate, glass slabs into the
/// dark status area, the trader's own figures and primary actions, then the
/// slanted-divider tab bar with search. It touches the title bar and the side
/// navigation; only its bottom edge leaves space.
class MarketHallHead extends StatelessWidget {
  const MarketHallHead(
    this.c, {
    required this.search,
    required this.onRefresh,
    super.key,
  });
  final MarketplaceController c;
  final Widget search;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Banner(c),
      _TabsBar(c, search: search, onRefresh: onRefresh),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner(this.c);
  final MarketplaceController c;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000, medium = box.maxWidth >= 720;
        final height = medium ? 104.0 : 84.0;
        final profile = c.tradeProfile;
        final visible = c.myListings.where((r) => r['visible'] == true).length;
        final hidden = c.myListings.length - visible;
        final limit = marketNumber(profile?['orderLimit'])?.toInt();
        // A failed reputation read never shows a stale figure.
        final point = c.failures.contains('reputation')
            ? null
            : c.blocks['reputation']?.data['point'] ?? profile?['point'];
        final done = marketNumber(profile?['completedTransactionCount']);
        final open = profile == null ? null : marketTradeOpenNow(profile);
        final windowText = profile == null
            ? null
            : marketTradeTime(context, profile);
        final stats = <Widget>[
          if (c.trades.supported)
            _Stat(
              label: marketText(context, 'bannerTodo'),
              value: '${c.trades.todo.length}',
              valueColor: c.trades.todo.isEmpty
                  ? null
                  : MarketplaceSurfaceColors.gold,
              note: marketTextN(context, 'bannerActive', c.activeTradeCount),
            ),
          if (c.myListingsSupported)
            _Stat(
              label: marketText(context, 'myListings'),
              value: c.myListingsLoaded ? '$visible' : '—',
              suffix: limit == null ? null : ' / $limit',
              note: hidden > 0
                  ? marketTextN(context, 'bannerHidden', hidden)
                  : null,
            ),
          if (c.favorites.isNotEmpty)
            _Stat(
              label: marketText(context, 'watchTab'),
              value: '${c.favorites.length}',
              note: c.watchChanged > 0
                  ? marketTextN(context, 'watchChangedN', c.watchChanged)
                  : null,
            ),
          if (medium)
            _Stat(
              label: marketText(context, 'bannerReputation'),
              value: point == null ? '—' : '★ $point',
              note: done == null
                  ? null
                  : marketTextN(context, 'bannerDone', done),
            ),
          if (wide) ...[
            if (profile != null)
              _Stat(
                label: marketText(context, 'bannerWindow'),
                value: open == null
                    ? marketText(context, 'tradeWindowUnset')
                    : marketText(
                        context,
                        open ? 'tradeOpenNow' : 'tradeClosedNow',
                      ),
                dot: open,
                note: open == null ? null : windowText,
                small: true,
              ),
          ],
        ];
        final canPublish = c.myListingsSupported;
        return Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [MarketplacePalette.bannerTop, MarketplacePalette.bannerBottom]
                  : [t.surfaces.raised.fill, t.surfaces.panel.fill],
            ),
            border: Border(bottom: BorderSide(color: t.surfaces.panel.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // SCM plate: the data source, Star Citizen's own trade market.
              ClipPath(
                clipper: const MarketPlateClipper(),
                child: CustomPaint(
                  foregroundPainter: const MarketPlateStripe(_scmOrange),
                  child: Container(
                    width: medium ? 250 : 190,
                    padding: const EdgeInsets.only(left: 22, right: 54),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [MarketplacePalette.plateTop, MarketplacePalette.plateBottom],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          label: 'SCM',
                          image: true,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                              MarketplacePalette.plateInk,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              'assets/brand/scm_wordmark.png',
                              height: medium ? 28 : 22,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text(
                                'SCM',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          marketText(context, 'scmMarket'),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 11.5,
                            letterSpacing: 1,
                            color: MarketplacePalette.plateSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(-44, 0),
                child: const MarketGlassSlabs(),
              ),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(-44, 0),
                  // A figure that does not fit goes whole, the last ones first:
                  // it wraps to a second line this clip hides, never half cut.
                  child: Wrap(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (final stat in stats)
                        SizedBox(
                          // The bottom border takes one pixel.
                          height: height - 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const MarketSlantDivider(height: 46),
                              // Alone wider than the room: fits, clipped by its own text.
                              Flexible(child: stat),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 18, left: 8),
                child: Row(
                  children: [
                    if (canPublish)
                      GuideAnchor(
                        id: 'market.publish',
                        child: MarketHoverCard(
                        lift: false,
                        alignEnd: true,
                        drawerWidth: 240,
                        color: t.colors.textPrimary,
                        drawerKey: const ValueKey('market-publish-drawer'),
                        drawer: (drawer) => marketPublishDrawer(drawer, c),
                        child: marketButtonAction(
                        key: const ValueKey('market-publish'),
                        hoverFace: false,
                        FilledButton.icon(
                        style: tradePrimaryStyle(context).copyWith(
                          minimumSize: const WidgetStatePropertyAll(
                            Size(0, 38),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => openMarketPublish(context, c),
                        icon: const MarketplaceIcon(
                          MarketplaceGlyph.add,
                          size: 16,
                        ),
                        label: Text(marketText(context, 'publishListing')),
                      )),
                      ),
                      ),
                    if (medium && c.trades.supported) ...[
                      const SizedBox(width: 8),
                      MarketHoverCard(
                        lift: false,
                        alignEnd: true,
                        drawerWidth: 240,
                        color: t.colors.textPrimary,
                        drawerKey: const ValueKey('market-trades-drawer'),
                        drawer: (drawer) => marketTradesDrawer(drawer, c),
                        child: marketButtonAction(
                        key: const Key('market-banner-trades'),
                        hoverFace: false,
                        OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: t.colors.textPrimary,
                          side: BorderSide(color: t.surfaces.panel.border),
                          shape: const RoundedRectangleBorder(),
                        ),
                        onPressed: () => c.tab(3),
                        child: Text('${marketText(context, 'mine')} →'),
                      )),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Banner colours that are not tokens: SCM money gold and the open/closed dot.
abstract final class MarketplaceSurfaceColors {
  static const gold = MarketplacePalette.gold;
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.suffix,
    this.note,
    this.valueColor,
    this.dot,
    this.small = false,
  });
  final String label, value;
  final String? suffix, note;
  final Color? valueColor;
  final bool? dot;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final open = dot == true;
    final color = dot == null
        ? valueColor ?? t.colors.textPrimary
        : open
        ? t.colors.success
        : t.colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                if (dot != null) TextSpan(text: open ? '● ' : '○ '),
                TextSpan(text: value),
                if (suffix != null)
                  TextSpan(
                    text: suffix,
                    style: TextStyle(
                      fontSize: 12,
                      color: t.colors.textSecondary,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            style: TextStyle(
              fontSize: small ? 15 : 20,
              height: 1.1,
              fontWeight: FontWeight.w600,
              fontFamily: small ? null : t.typography.monoFamily,
              color: color,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 3),
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                color: t.colors.textSecondary.withValues(alpha: .8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabsBar extends StatelessWidget {
  const _TabsBar(this.c, {required this.search, required this.onRefresh});
  final MarketplaceController c;
  final Widget search;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 关注 (tab index 5) sits after 市场 (G3, 0.7.2); indices of the other
    // tabs are unchanged so existing links (c.tab(3) …) keep working.
    const keys = [(0, 'hall'), (1, 'market'), (5, 'watchTab'), (2, 'contracts'), (3, 'mine'), (4, 'storage')];
    final changed = c.favorites.isEmpty ? 0 : c.watchChanged;
    final tabs = [
      for (final (n, (i, key)) in keys.indexed) ...[
        if (n > 0) const MarketSlantDivider(height: 20),
        GuideAnchor(
          id: i == 3 ? 'market.trades' : 'market.tab.$i',
          child: _Tab(
          label: marketText(context, key),
          leading: i == 5
              ? const FavoriteIcon(selected: true, size: 13, color: MarketplacePalette.heart)
              : null,
          selected: c.mainTab == i,
          badge: i == 3 && c.trades.todo.isNotEmpty
              ? c.trades.todo.length
              : i == 5 && changed > 0
              ? changed
              : null,
          onTap: () => c.tab(i),
        ),
        ),
      ],
    ];
    final tools = [
      Expanded(
        child: SizedBox(
          height: 34,
          child: GuideAnchor(id: 'market.search', child: search),
        ),
      ),
      // The item page carries its own refresh next to its figures.
      if (!c.hasItem) ...[
        const SizedBox(width: 8),
        StarBridgeNativeIconAction(
          controlKey: const Key('market-refresh'),
          label: marketText(context, 'refresh'),
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          padding: EdgeInsets.zero,
          onActivate: onRefresh == null ? null : (_) => onRefresh!(),
          icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
        ),
      ],
      const SizedBox(width: 4),
      StarBridgeNativeIconAction(
        controlKey: const Key('market-display-settings'),
        label: marketText(context, 'displaySettings'),
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        padding: EdgeInsets.zero,
        onActivate: (_) => showMarketDisplaySettings(context, c),
        icon: const StarBridgeIcon(StarBridgeIconSemantic.settings),
      ),
    ];
    final decoration = BoxDecoration(
      color: dark ? MarketplacePalette.tabsBar : t.surfaces.panel.fill,
      border: Border(bottom: BorderSide(color: t.surfaces.panel.border)),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 980
          // Narrow: tabs on one row, search on the next, so nothing is squeezed.
          ? Container(
              padding: const EdgeInsets.only(left: 8, right: 12, bottom: 6),
              decoration: decoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 42,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: tabs),
                    ),
                  ),
                  Row(children: tools),
                ],
              ),
            )
          : Container(
              height: 46,
              padding: const EdgeInsets.only(left: 8, right: 12),
              decoration: decoration,
              child: Row(
                children: [
                  ...tabs,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Row(children: tools),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
    this.leading,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;
  final Widget? leading;
  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = widget.label, selected = widget.selected, badge = widget.badge;
    // The tab keeps its own hover (text colour and slanted preview line), so
    // the shared target adds press/focus feedback only.
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: StarBridgeActionRow(
        controlKey: ValueKey(('market-tab', label)),
        inheritContentStyle: true,
        hoverFace: false,
        semanticSelected: selected,
        baseRadius: 0,
        onActivate: (_, _) => widget.onTap(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.leading case final leading?) ...[
                    leading,
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected || hover
                          ? t.colors.textPrimary
                          : t.colors.textSecondary,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MarketplaceSurfaceColors.gold,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: t.typography.monoFamily,
                          color: MarketplacePalette.onGold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              // Hover previews the selection line, slanted at the hall's angle.
              ClipPath(
                clipper: const _SlantTailClipper(),
                child: AnimatedContainer(
                duration: t.motion.surfaceExit,
                height: 2,
                width: selected ? 26 : hover ? 20 : 0,
                decoration: BoxDecoration(
                  color: selected
                      ? t.colors.accent
                      : t.colors.textSecondary.withValues(alpha: .6),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: t.colors.accent.withValues(alpha: .6),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cuts the right end of a thin line along the hall's slant.
class _SlantTailClipper extends CustomClipper<Path> {
  const _SlantTailClipper();
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
  bool shouldReclip(_SlantTailClipper oldClipper) => false;
}

/// Section heading: slanted mark, title, optional meta and a trailing action,
/// closed by a hairline that fades to the right.
class MarketSectionHeading extends StatelessWidget {
  const MarketSectionHeading(this.title, {this.meta, this.trailing, super.key});
  final String title;
  final Widget? meta, trailing;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.only(bottom: 9),
      foregroundDecoration: _FadingHairline(t.colors.textSecondary),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const MarketHeadingMark(),
          const SizedBox(width: 9),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: t.colors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          // Meta takes the free space so the actions always sit on the right
          // edge; actions shrink (never overflow) when the row is narrow.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: meta == null
                          ? const SizedBox.shrink()
                          : DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: 12,
                                color: t.colors.textSecondary,
                              ),
                              child: meta!,
                            ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (box.maxWidth * .7).clamp(0, double.infinity),
                      ),
                      child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FadingHairline extends Decoration {
  const _FadingHairline(this.color);
  final Color color;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _HairlinePainter(color);
}

class _HairlinePainter extends BoxPainter {
  _HairlinePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy + size.height - 1,
      size.width,
      1,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: .38),
            color.withValues(alpha: .10),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
  }
}
