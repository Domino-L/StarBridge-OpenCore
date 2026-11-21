import 'dart:async';
import 'package:flutter/material.dart';
import '../../design_system/icons/favorite_icon.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';

/// The item identity's follow action, shared by wide and narrow layouts.
Widget marketItemFavorite(BuildContext context, MarketplaceController c, MarketRow? item) {
    final following = c.favorites.contains(c.itemId);
    // A followed item reads in red (user 2026-10-20); following confirms with
    // a way to the 关注 tab, unfollowing with an undo (G3, 0.7.2).
    return OutlinedButton.icon(
      key: const Key('market-item-follow'),
      style: OutlinedButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        foregroundColor: following
            ? MarketplacePalette.heart
            : context.tokens.colors.textPrimary,
        side: BorderSide(
          color: following
              ? MarketplacePalette.heart
              : context.tokens.surfaces.panel.border,
        ),
        shape: const RoundedRectangleBorder(),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      icon: FavoriteIcon(
        selected: following,
        size: 16,
        color: following ? MarketplacePalette.heart : null,
      ),
      onPressed: c.savingPreferences || c.preferencesFailed
          ? null
          : () async {
              final id = c.itemId!;
              final name = item == null
                  ? marketText(context, 'thisItem')
                  : marketName(item, marketLocale(context));
              final snapshot = c.watchSnapshot(id);
              final messenger = ScaffoldMessenger.of(context);
              final added = marketTextN(context, 'watchAdded', name);
              final removed = marketTextN(context, 'watchRemoved', name);
              final view = marketText(context, 'watchView');
              final undo = marketText(context, 'watchUndo');
              final limit = marketText(context, 'watchLimit');
              await c.toggleFavorite(id);
              if (!context.mounted) return;
              if (c.favoriteLimitReached) {
                messenger.showOnly(starBridgeTimedSnackBar(content: Text(limit)));
                return;
              }
              final now = c.favorites.contains(id);
              messenger.showOnly(
                // QualityPass ②: 2.5 s, paused while pointed at so 撤销 stays reachable.
                starBridgeTimedSnackBar(
                  content: Text(now ? added : removed),
                  action: SnackBarAction(
                    label: now ? view : undo,
                    onPressed: now
                        ? () => c.tab(5)
                        : () => unawaited(
                            c.toggleFavorite(id, snapshot: snapshot),
                          ),
                  ),
                ),
              );
            },
      label: Text(
        marketText(
          context,
          c.savingPreferences
              ? 'saving'
              : following
              ? 'unfollow'
              : 'follow',
        ),
      ),
    );
}
