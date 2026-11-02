import 'dart:async';


import '../account/account_login_dialog.dart';
import '../../app/feature_registry.dart';
import '../../design_system/appearance/appearance_scope.dart';
import '../account/account_module.dart';
import '../onboarding/connection_mode_port.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'marketplace_attention.dart';
import 'marketplace_chat_controller.dart';
import 'marketplace_controller.dart';
import 'marketplace_page.dart';
import 'marketplace_port.dart';

/// The hall's single controller. The composition creates it once so other
/// surfaces (the profile's trade strip) read the same trade profile.
MarketplaceController createMarketplaceController(
  BridgeClientSession? session,
  ConnectionModeControl? mode, {
  MarketplacePort? port,
}) => MarketplaceController(
  port ??
      (session == null
          ? UnavailableMarketplacePort()
          : BridgeMarketplacePort(session, mode)),
);

/// The feature owns [shared] (or the controller it creates) and disposes it.
FeatureDescriptor createMarketplaceFeature(
  AccountModule account,
  BridgeClientSession? session,
  ConnectionModeControl? mode, {
  MarketplacePort? port,
  MarketplaceController? shared,
  MarketplaceChatController? chat,
}) {
  final controller =
      shared ?? createMarketplaceController(session, mode, port: port);
  controller.login = (context) => showAccountLoginDialog(context, account);
  if (session != null) {
    controller.openScm = (_) async {
      await session.request(
        'helpSupport.openScm',
        payload: {'schemaVersion': 1},
      );
    };
  }
  // 0.7.2: the sidebar count (trades waiting on me + unread trade messages),
  // and the app-wide trade-chat state its live pushes keep current.
  // The composition owns the app-wide one; tests may leave it out.
  final ownsChat = chat == null;
  final hallPort = controller.port;
  chat ??= hallPort is MarketplaceChatPort
      ? MarketplaceChatController(hallPort as MarketplaceChatPort)
      : null;
  controller.tradeChat = chat;
  chat?.recentOrders = () => [
    for (final row in controller.trades.rows)
      if ((row['orderId'] as num?)?.toInt() case final id? when id > 0)
        MarketChatAttachment(
          id,
          '${row['itemsName'] ?? ''} ×${row['number'] ?? 1} · #${row['transactionNumber'] ?? ''}',
        ),
  ];
  if (session != null) {
    chat?.openScm = () => unawaited(
      session.request('helpSupport.openScm', payload: {'schemaVersion': 1}),
    );
  }
  final attention = MarketplaceAttention(controller, chat);
  var generation = account.projection.value.generation;
  var state = account.projection.value.sessionState;
  var online = mode?.allowsOnlineTraffic;
  void follow() => attention.follow(
    signedIn:
        account.projection.value.isSignedIn &&
        mode?.allowsOnlineTraffic != false,
  );

  follow();
  void changed() {
    final next = account.projection.value;
    if (generation == next.generation &&
        state == next.sessionState &&
        online == mode?.allowsOnlineTraffic) {
      return;
    }
    generation = next.generation;
    state = next.sessionState;
    online = mode?.allowsOnlineTraffic;
    controller.contextChanged();
    follow();
  }

  account.projection.addListener(changed);
  mode?.addListener(changed);
  return FeatureDescriptor(
    id: 'marketplace',
    route: '/marketplace',
    labelKey: 'navigation.marketplace',
    descriptionKey: 'navigation.marketplace.description',
    icon: StarBridgeIconSemantic.marketplace,
    navigationRegion: NavigationRegion.primary,
    order: 40,
    buildDestination: (_) => HolidayColorExempt(
      restoreGround: true,
      child: MarketplacePage(controller),
    ),
    attentionCount: attention,
    // Scheduled by the session warm-up queue (after communities), not a timer.
    prefetch: attention.prefetch,
    // 通知中心 → 交易: 我的交易.
    openSection: (section) {
      if (section == 'trades') controller.tab(3);
      // A trade reminder (CX-T23): 我的交易, then that transaction's sheet.
      if (section.startsWith('trade:')) {
        controller.tab(3);
        controller.trades.requestOpen(section.substring(6));
      }
    },
    attentionDetail: attention.detail(),
    // Only Ctrl+K lands in the search box; entering from the sidebar does not.
    onSearchShortcut: controller.focusSearch,
    onDispose: () {
      account.projection.removeListener(changed);
      mode?.removeListener(changed);
      attention.dispose();
      if (ownsChat) chat?.dispose();
      controller.dispose();
    },
  );
}

final marketplaceFeature = FeatureDescriptor(
  id: 'marketplace',
  route: '/marketplace',
  labelKey: 'navigation.marketplace',
  descriptionKey: 'navigation.marketplace.description',
  icon: StarBridgeIconSemantic.marketplace,
  navigationRegion: NavigationRegion.primary,
  order: 40,
  availability: FeatureAvailability.comingSoon,
);
