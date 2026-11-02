import 'dart:async';

import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'bridge_marketplace_listings_port.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_listing_errors.dart';
import 'marketplace_listing_editor.dart';
import 'marketplace_listing_publish.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_profile.dart';
import 'marketplace_details.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// Hall quick actions on one of my listings (hover drawer): 'edit' opens the
/// listing editor, 'visibility' hides (after a confirm) or relists it, and
/// 'copy' opens the publish wizard on step 3 with its content. Each uses a
/// short-lived listings controller, like the publish entry.
Future<void> openMarketListingAction(
  BuildContext context,
  MarketplaceController market,
  MarketRow row,
  String action,
) async {
  final port = market.port;
  if (port is! BridgeMarketplacePort) return;
  if (action == 'copy') {
    return openMarketPublish(
      context,
      market,
      draft: ListingDraft(
        item: {'id': row['itemId'], 'name': row['name']},
        side: row['side'] as String? ?? 'sell',
        price: '${row['price'] ?? ''}',
        quantity: '${row['quantity'] ?? 1}',
        location: '${row['location'] ?? ''}',
      ),
    );
  }
  final visible = row['visible'] == true;
  if (action == 'visibility' && visible) {
    final ok = await tradeMotionDialog<bool>(
      context,
      barrierDismissible: true,
      (ctx) => AlertDialog(
        title: Text(marketText(ctx, 'drawerHideTitle')),
        content: Text(marketText(ctx, 'drawerHideBody')),
        actions: [
          marketTextAction(
            key: const ValueKey('drawer-hide-cancel'),
            onPressed: () => dismissStarBridgeDialog<bool>(
              ctx,
              source: StarBridgeActivationOrigin.sourceOf(ctx),
              result: false,
            ),
            child: Text(marketText(ctx, 'drawerCancel')),
          ),
          marketButtonAction(
            key: const ValueKey('drawer-hide-confirm'),
            FilledButton(
              onPressed: () => dismissStarBridgeDialog<bool>(
                ctx,
                source: StarBridgeActivationOrigin.sourceOf(ctx),
                result: true,
              ),
              child: Text(marketText(ctx, 'drawerHide')),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }
  final listings = MarketplaceListingsController(BridgeMarketplaceListingsPort(port));
  try {
    if (action == 'edit') {
      unawaited(listings.refresh());
      await editListing(context, listings, row);
    } else if (action == 'visibility') {
      final done = await listings.write('visibility', {'id': row['id'], 'visible': !visible});
      if (!done && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showOnly(
          starBridgeTimedSnackBar(
            content: Text(
              listings.error == null
                  ? marketText(context, 'unavailable')
                  : listingErrorText(context, listings.errorCode, listings.error!),
            ),
          ),
        );
      }
    }
  } finally {
    listings.dispose();
    unawaited(market.refreshMyOrders());
  }
}

Future<void> openMarketPublish(BuildContext context, MarketplaceController market,
    {MarketRow? item, String side = 'sell', ListingDraft? draft}) async {
  final port = market.port;
  if (port is! BridgeMarketplacePort) return;
  final revision = market.contextRevision;
  final listings = MarketplaceListingsController(BridgeMarketplaceListingsPort(port))
    ..qualityTiers = market.qualityTiers;
  // Open at once: the wizard listens to the controller, shows its own load
  // error and retry, and step 1 needs no data. A click must never look dead.
  unawaited(listings.refresh());
  // Made once: the dialog route may call its builder again.
  final opened = draft ?? ListingDraft(item: item ?? const {}, side: side);
  try {
    await tradeMotionDialog<void>(context, (_) => ListingPublishDialog(listings,
      opened,
      initialStep: item == null && draft == null ? 0 : 2,
      editProfile: () async {
        final profile = await editTradeProfile(context, market);
        if (!context.mounted || market.contextRevision != revision || profile == null) return;
        listings.applyTradeProfile(profile, marketTradeTime(context, profile));
      }));
  } finally {
    listings.dispose();
    // A new listing must be recognised as yours right away.
    unawaited(market.refreshMyOrders());
  }
}
