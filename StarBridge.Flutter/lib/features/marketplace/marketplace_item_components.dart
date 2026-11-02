import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_market_filters.dart' show pickMarketLocation;
import 'marketplace_surfaces.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/remote_image.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart' show MarketTraderProfileLink;
import 'marketplace_widgets.dart' show MarketSlantFace;
import 'marketplace_port.dart';
import 'marketplace_states.dart' show marketButtonAction;

Widget itemKv(
  BuildContext context,
  String label,
  String value, {
  String? tooltip,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Expanded(
        child: Tooltip(
          message: tooltip ?? '',
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: context.tokens.colors.textSecondary,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontFamily: context.tokens.typography.monoFamily,
          ),
        ),
      ),
    ],
  ),
);

/// One column grid for the offer header and rows, so both always line up.
class ItemOfferColumns extends StatelessWidget {
  const ItemOfferColumns({
    super.key,
    required this.cells,
    required this.quality,
    required this.action,
  });

  /// avatar, trader, location, hours, quality, quantity, price, action.
  final List<Widget> cells;
  final bool quality, action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 42,
        child: Align(alignment: Alignment.centerLeft, child: cells[0]),
      ),
      Expanded(flex: 3, child: cells[1]),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: cells[2]),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: cells[3]),
      if (quality)
        SizedBox(
          width: 64,
          child: Align(alignment: Alignment.centerLeft, child: cells[4]),
        ),
      SizedBox(width: 44, child: cells[5]),
      const SizedBox(width: 16),
      SizedBox(
        width: 150,
        child: Align(alignment: Alignment.centerRight, child: cells[6]),
      ),
      if (action) ...[
        const SizedBox(width: 12),
        SizedBox(
          width: 84,
          child: Align(alignment: Alignment.centerRight, child: cells[7]),
        ),
      ],
    ],
  );
}

/// The trader's initials, covered by their RSI avatar when the Host passed a
/// validated RSI address (CX-T18). Rows build it as the list builds them
/// (with the list's cache extent); the shared remote-image loader caches,
/// pools and merges the downloads. Redirects are not followed, so a vetted
/// RSI address can never lead the client to another host (CX-T19).
class ItemTraderAvatar extends StatelessWidget {
  const ItemTraderAvatar(this.name, {this.avatar, super.key});
  final String? name;
  final String? avatar;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final letters = (name ?? '').replaceAll(
      RegExp(r'[^A-Za-z0-9\u4e00-\u9fff]'),
      '',
    );
    final initials = letters.isEmpty
        ? '?'
        : letters.length == 1
        ? letters.toUpperCase()
        : '${letters[0]}${letters[letters.length - 1]}'.toUpperCase();
    final source = avatar;
    final box = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: t.surfaces.raised.fill,
        border: Border.all(color: t.surfaces.panel.border),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: t.colors.textSecondary,
        ),
      ),
    );
    if (source == null || !source.startsWith('https://')) return box;
    return Stack(
      children: [
        box,
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: RemoteImage(
            source,
            key: const ValueKey('market-trader-avatar-image'),
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            cacheWidth: 64,
            kind: RemoteImageResourceKind.avatar,
            followRedirects: false,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// An offer row's trader square; it opens their personal page when it can.
class ItemTraderCell extends StatelessWidget {
  const ItemTraderCell(this.row, {super.key});
  final MarketRow row;
  @override
  Widget build(BuildContext context) => MarketTraderProfileLink(
    row,
    child: ItemTraderAvatar(
      row['seller'] as String?,
      avatar: row['avatar'] as String?,
    ),
  );
}

class ItemRelatedRow extends StatelessWidget {
  const ItemRelatedRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final MarketplaceGlyph icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return StarBridgeActionRow(
      inheritContentStyle: true,
      baseRadius: 0,
      onActivate: onTap == null ? null : (_, _) => onTap!(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: marketLine(context))),
        ),
        child: Row(
          children: [
            MarketplaceIcon(icon, size: 16, color: t.colors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            MarketplaceIcon(
              MarketplaceGlyph.next,
              size: 18,
              color: t.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Offer filter row: presence, minimum quality, location and price direction.
/// Every choice is sent to SCM; nothing is filtered on the loaded page alone.
class ItemOfferFilters extends StatelessWidget {
  const ItemOfferFilters(this.c, {super.key});
  final MarketplaceController c;
  @override
  Widget build(BuildContext context) {
    final status = c.offerFilters['creatorStatus'];
    final quality = c.offerFilters['minQuality'];
    Widget menu(
      String label, {
      required bool active,
      required List<(String, String)> items,
      required ValueChanged<String> onSelected,
    }) => Semantics(
      container: true,
      child: StarBridgeMenuAnchor(
        semanticLabel: label,
        consumeOutsideTaps: true,
        entries: [
          for (final (value, text) in items)
            StarBridgeMenuEntry(
              id: ('market-quality', value),
              controlKey: ValueKey(('market-quality', value)),
              label: text,
              onActivate: (source) => unawaited(
                runStarBridgeActivation<void>(
                  source,
                  () async => onSelected(value),
                ),
              ),
              // Native PopupMenuItem: 112 x 48 with 12 inset.
              child: SizedBox(
                width: 88,
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ),
        ],
        builder: (context, controller, focus, toggle) => ItemFilterChip(
          key: const Key('market-quality-menu'),
          label: label,
          active: active,
          menu: true,
          focusNode: focus,
          onSourceTap: toggle,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (value, key) in [
            ('', 'allTraders'),
            ('1', 'online'),
            ('2', 'game'),
          ])
            ItemFilterChip(
              label: marketText(context, key),
              active: (status ?? '') == value,
              onTap: () => c.setOfferFilter(
                'creatorStatus',
                // Activating the active status again clears it back to 全部 (user 10-29).
                value.isEmpty || (status ?? '') == value ? null : value,
              ),
            ),
          menu(
            quality == null
                ? marketText(context, 'qualityAtLeast')
                : '${marketText(context, 'qualityAtLeast')} $quality',
            active: quality != null,
            items: [
              ('', marketText(context, 'anyQuality')),
              for (final q in ['200', '400', '600', '800']) (q, '≥ $q'),
            ],
            onSelected: (v) =>
                c.setOfferFilter('minQuality', v.isEmpty ? null : v),
          ),
          ItemFilterChip(
            label: c.offerLocation == null
                ? marketText(context, 'allLocations')
                : marketName(
                    c.offerLocation!,
                    marketLocale(context),
                    field: 'name',
                  ),
            active: c.offerLocation != null,
            menu: true,
            onTap: () async {
              final picked = await pickMarketLocation(context, c.port);
              if (picked == null) return;
              final all = picked['id'] == 0;
              await c.setOfferFilter(
                'locationId',
                all ? null : '${picked['id']}',
                location: all ? null : picked,
              );
            },
          ),
          if (c.offerFilters.isNotEmpty || c.offerSortField != 'price')
            marketButtonAction(
              key: const Key('market-offer-clear-filters'),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontSize: 12),
                ),
                onPressed: c.clearOfferFilters,
                child: Text(marketText(context, 'clearFilters')),
              ),
            ),
        ],
      ),
    );
  }
}

/// A sortable column header: one active column at a time; tapping the
/// active one flips its direction.
class ItemSortHeader extends StatelessWidget {
  const ItemSortHeader({
    super.key,
    required this.label,
    required this.active,
    required this.desc,
    required this.onTap,
    this.right = false,
  });
  final String label;
  final bool active, desc, right;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? t.colors.accent : t.colors.textSecondary;
    return StarBridgeActionRow(
      inheritContentStyle: true,
      semanticSelected: active,
      baseRadius: 4,
      onActivate: (_, _) => onTap(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        // Narrow columns (数量 is 44px) shrink the label instead of overflowing.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : null,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                active ? (desc ? '↓' : '↑') : '↕',
                style: TextStyle(
                  color: active
                      ? color
                      : t.colors.textSecondary.withValues(alpha: .5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemFilterChip extends StatelessWidget {
  const ItemFilterChip({
    super.key,
    required this.label,
    required this.active,
    this.menu = false,
    this.icon,
    this.onTap,
    this.onSourceTap,
    this.focusNode,
  });
  final String label;
  final bool active, menu;
  final MarketplaceGlyph? icon;
  final VoidCallback? onTap;

  /// Source-aware activation (a menu anchor's toggle) with its focus node.
  final ValueChanged<InteractionSource>? onSourceTap;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? t.colors.accent : t.colors.textSecondary;
    // The hall's slanted option face; the target and menu wiring are unchanged.
    final content = MarketSlantFace(
      selected: active,
      restBorder: t.surfaces.panel.border,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            MarketplaceIcon(icon!, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? t.colors.textPrimary : color,
            ),
          ),
          if (menu) ...[
            const SizedBox(width: 2),
            MarketplaceIcon(MarketplaceGlyph.expand, size: 14, color: color),
          ],
        ],
      ),
      ),
    );
    final face = Material(
      color: Colors.transparent,
      // A menu chip (no onTap) is only the face of its PopupMenuButton, which
      // owns the target; it must stay hit-testable and unfocusable.
      child: onTap == null && onSourceTap == null
          ? content
          : StarBridgeActionRow(
              inheritContentStyle: true,
              semanticSelected: active,
              baseRadius: 0,
              // The slanted face draws hover; no rectangular suite face.
              hoverFace: false,
              focusNode: focusNode,
              onActivate: (_, source) =>
                  onSourceTap != null ? onSourceTap!(source) : onTap!(),
              child: content,
            ),
    );
    return onTap == null && onSourceTap == null
        ? Semantics(selected: active, button: true, child: face)
        : face;
  }
}

class ItemRelatedChip extends StatelessWidget {
  const ItemRelatedChip({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final MarketplaceGlyph icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: t.surfaces.panel.border),
      ),
      child: StarBridgeActionRow(
        inheritContentStyle: true,
        baseRadius: 6,
        onActivate: onTap == null ? null : (_, _) => onTap!(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 5, 6, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MarketplaceIcon(icon, size: 14, color: t.colors.textSecondary),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              MarketplaceIcon(
                MarketplaceGlyph.next,
                size: 16,
                color: t.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
