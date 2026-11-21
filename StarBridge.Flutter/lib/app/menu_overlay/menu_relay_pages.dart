import 'package:flutter/widgets.dart';

import 'menu_communities_page.dart';
import 'menu_fleet_page.dart';
import 'menu_marketplace_page.dart';
import 'menu_page_relay.dart';

/// The client pages the menu shows through its page relay, kept across
/// openings for the surface's lifetime.
final class MenuRelayPages {
  MenuRelayPages(this.relay);
  final MenuPageRelay relay;
  late final _hall = MenuMarketplaceOwner(relay);
  late final _fleet = MenuFleetOwner(relay);
  late final _communities = MenuCommunitiesOwner(relay);

  /// Panel id → page; empty while the relay is not offered.
  Map<String, Widget Function()> get pages => !relay.enabled
      ? const {}
      : {
          'marketplace': () => MenuMarketplacePage(owner: _hall),
          'officialFleet': () => MenuFleetPage(owner: _fleet),
          'organizations': () => MenuCommunitiesPage(owner: _communities),
        };

  void dispose() {
    _communities.dispose();
    _fleet.dispose();
    _hall.dispose(); // Last: it also disposes the relay.
  }
}
