import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design_system/interaction/starbridge_action_button.dart';
import '../design_system/styles/marketplace_palette.dart';
import '../design_system/tokens/starbridge_tokens.dart';

/// 交易消息 inside 好友与私信 (0.7.2 G9, approved preview trade-chat-preview).
/// The trading hall owns trade chat; the messages page only offers the slot,
/// so neither feature imports the other. The composition provides it.
class TradeChatSlot extends InheritedWidget {
  const TradeChatSlot({
    required this.unread,
    required this.requests,
    required this.build,
    required super.child,
    super.key,
  });

  /// Unread trade messages, shown on the 交易消息 group.
  final ValueListenable<int> unread;

  /// Changes when another surface asks to show a trade conversation; the
  /// messages page then switches to 交易消息.
  final Listenable requests;

  /// The trade-chat view. [header] is the 私信 / 交易消息 switch, drawn at the
  /// top of the view's own conversation list.
  final Widget Function(BuildContext context, Widget header) build;

  static TradeChatSlot? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TradeChatSlot>();

  @override
  bool updateShouldNotify(TradeChatSlot old) =>
      // [build] is derived from the same chat state, so these two decide.
      unread != old.unread || requests != old.requests;
}

/// The 私信 / 交易消息 switch at the top of either conversation list.
class TradeChatGroupSwitch extends StatelessWidget {
  const TradeChatGroupSwitch({
    required this.trade,
    required this.unread,
    required this.onChanged,
    super.key,
  });
  final bool trade;
  final ValueListenable<int> unread;
  final ValueChanged<bool> onChanged;

  static String _label(BuildContext context, bool trade) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode != 'zh') {
      return trade ? 'Trade messages' : 'Messages';
    }
    final hant =
        locale.scriptCode == 'Hant' ||
        locale.countryCode == 'TW' ||
        locale.countryCode == 'HK';
    return trade ? (hant ? '交易訊息' : '交易消息') : (hant ? '私訊' : '私信');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget tab(bool value, {int count = 0}) => StarBridgeActionButton(
      controlKey: ValueKey(('trade-chat-group', value)),
      kind: StarBridgeActionKind.quiet,
      hoverFace: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      onActivate: (_) => onChanged(value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _label(context, value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: trade == value ? FontWeight.w600 : FontWeight.w400,
              color: trade == value
                  ? t.colors.textPrimary
                  : t.colors.textSecondary,
              decoration: trade == value ? TextDecoration.underline : null,
              decorationColor: t.colors.accent,
              decorationThickness: 2,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MarketplacePalette.heart,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: t.typography.monoFamily,
                  color: MarketplacePalette.onHeart,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 2),
      child: ValueListenableBuilder<int>(
        valueListenable: unread,
        builder: (context, count, _) => Row(
          children: [
            tab(false),
            Text('/', style: TextStyle(color: t.colors.textDisabled)),
            tab(true, count: count),
          ],
        ),
      ),
    );
  }
}
