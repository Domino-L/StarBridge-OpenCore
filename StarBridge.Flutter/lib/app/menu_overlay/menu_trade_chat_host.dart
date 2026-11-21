import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/marketplace/marketplace_chat_controller.dart';
import '../../features/marketplace/marketplace_trade_chat_view.dart';
import '../localization/app_strings.dart';

/// In the client, 私信对方 and 联系卖家 open the messages window. The menu has
/// none, so the same trade-chat view opens as a dialog inside the hall panel.
class MenuTradeChatHost extends StatefulWidget {
  const MenuTradeChatHost({required this.chat, required this.child, super.key});
  final MarketplaceChatController? chat;
  final Widget child;

  @override
  State<MenuTradeChatHost> createState() => _MenuTradeChatHostState();
}

class _MenuTradeChatHostState extends State<MenuTradeChatHost> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.chat?.requests.addListener(_requested);
  }

  @override
  void didUpdateWidget(MenuTradeChatHost old) {
    super.didUpdateWidget(old);
    if (identical(old.chat, widget.chat)) return;
    old.chat?.requests.removeListener(_requested);
    widget.chat?.requests.addListener(_requested);
  }

  @override
  void dispose() {
    widget.chat?.requests.removeListener(_requested);
    super.dispose();
  }

  /// An open view takes the request itself; only a closed one opens here.
  void _requested() {
    final chat = widget.chat;
    if (_open || chat == null || !mounted) return;
    _open = true;
    unawaited(
      showStarBridgeDialog<void>(
        context,
        useRootNavigator: false,
        builder: (context) => _TradeChatDialog(chat),
      ).whenComplete(() => _open = false),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TradeChatDialog extends StatelessWidget {
  const _TradeChatDialog(this.chat);
  final MarketplaceChatController chat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final strings = AppStrings.of(context);
    final size = MediaQuery.sizeOf(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.text('menu.overlay.window.tradeChat'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          StarBridgeNativeIconAction(
            controlKey: const Key('menu-trade-chat-close'),
            label: strings.text('menu.overlay.window.tradeChatClose'),
            onActivate: (source) =>
                dismissStarBridgeDialog<void>(context, source: source),
            consumeHintEscape: false,
            icon: MarketplaceIcon(MarketplaceGlyph.close, size: 18),
          ),
        ],
      ),
    );
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          key: const Key('menu-trade-chat'),
          width: (size.width - 64).clamp(320, 980).toDouble(),
          height: (size.height - 64).clamp(320, 680).toDouble(),
          decoration: BoxDecoration(
            color: t.surfaces.panel.fill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.surfaces.panel.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: MarketplaceTradeChatView(
            chat,
            header: header,
            recentOrders: chat.recentOrders,
          ),
        ),
      ),
    );
  }
}
