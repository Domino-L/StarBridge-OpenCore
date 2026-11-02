import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/feature_registry.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_chat_controller.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_trades_controller.dart';

/// The sidebar's 交易大厅 count (0.7.2, approved option A + C): trades that
/// wait on me (approve, ship, receive, review) plus unread trade messages. It
/// reuses the hall's own trade list and the live chat unread total; nothing
/// polls for it alone.
class MarketplaceAttention extends ChangeNotifier
    implements ValueListenable<int> {
  MarketplaceAttention(this.market, [this.chat]) {
    market.trades.addListener(_recount);
    chat?.addListener(_recount);
  }
  final MarketplaceController market;
  final MarketplaceChatController? chat;

  int approve = 0, ship = 0, receive = 0, review = 0;
  int get messages => chat?.unread ?? 0;
  DateTime? updatedAt;
  int _value = 0;
  bool _signedIn = false, _unreadRead = false;
  bool _disposed = false;

  @override
  int get value => _value;

  void _recount() {
    var a = 0, s = 0, r = 0, v = 0;
    for (final row in market.trades.rows) {
      switch (tradeAction(row)) {
        case 'approve':
          a++;
        case 'ship':
          s++;
        case 'receive':
          r++;
        case 'review':
          v++;
      }
    }
    final next = a + s + r + v + messages;
    final changed =
        next != _value ||
        a != approve ||
        s != ship ||
        r != receive ||
        v != review;
    approve = a;
    ship = s;
    receive = r;
    review = v;
    _value = next;
    updatedAt = DateTime.now();
    if (changed && !_disposed) notifyListeners();
  }

  /// Whether an SCM account is signed in and online traffic is allowed.
  void follow({required bool signedIn}) {
    if (!signedIn || _signedIn != signedIn) {
      chat?.reset();
      _unreadRead = false;
    }
    _signedIn = signedIn;
    _recount();
  }

  /// The feature's prefetch: the trade list and the unread total, read once.
  /// The session warm-up queue schedules it after the first screens' reads
  /// (and cancels / repeats it per account); hovering the sidebar item may
  /// call it again, which costs nothing once started.
  Future<void> prefetch() async {
    if (_disposed || !_signedIn) return;
    final unread = _unreadRead ? null : chat?.loadUnread();
    _unreadRead = true;
    try {
      await Future.wait([market.trades.start(), ?unread]);
    } on Object {
      // The warm-up queue must never see a failure; the next read retries.
    }
  }

  String describe(BuildContext context) => _text(context, 'describe', {
    'a': '$approve',
    's': '$ship',
    'r': '$receive',
    'v': '$review',
    'm': '$messages',
  });

  /// The hover / focus card beside the sidebar item.
  AttentionDetail detail() => AttentionDetail(
    listenable: this,
    describe: describe,
    build: (context, open) => MarketplaceAttentionCard(
      this,
      open: () {
        market.activityTab = 0;
        market.tab(3);
        open();
      },
    ),
  );

  @override
  void dispose() {
    _disposed = true;
    market.trades.removeListener(_recount);
    chat?.removeListener(_recount);
    super.dispose();
  }
}

class MarketplaceAttentionCard extends StatelessWidget {
  const MarketplaceAttentionCard(this.a, {required this.open, super.key});
  final MarketplaceAttention a;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = [
      ('approve', a.approve),
      ('ship', a.ship),
      ('receive', a.receive),
      ('review', a.review),
      ('messages', a.messages),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(context, 'title'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.colors.textPrimary,
                  ),
                ),
              ),
              Text(
                _text(context, 'now'),
                style: TextStyle(fontSize: 11, color: t.colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (key, count) in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: t.surfaces.panel.border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _text(context, key),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: t.colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    key: ValueKey(('attention-count', key)),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: t.typography.monoFamily,
                      color: count > 0
                          ? t.colors.textPrimary
                          : t.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          StarBridgeActionRow(
            controlKey: const Key('market-attention-open'),
            inheritContentStyle: true,
            onActivate: (_, _) => open(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    _text(context, 'open'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.colors.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  MarketplaceIcon(
                    MarketplaceGlyph.next,
                    size: 14,
                    color: t.colors.accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _copy = <String, List<String>>{
  'title': ['交易大厅 · 待你处理', '交易大廳 · 待你處理', 'Trading hall · waiting on you'],
  'now': ['刚刚', '剛剛', 'just now'],
  'approve': ['待你同意', '待你同意', 'To approve'],
  'ship': ['待你发货', '待你發貨', 'To ship'],
  'receive': ['待你收货', '待你收貨', 'To receive'],
  'review': ['待你评价', '待你評價', 'To review'],
  'messages': ['交易私信未读', '交易私訊未讀', 'Unread trade messages'],
  'open': ['打开“我的交易”', '開啟「我的交易」', 'Open My trades'],
  'describe': [
    '待你同意 {a}，待你发货 {s}，待你收货 {r}，待你评价 {v}，交易私信未读 {m}',
    '待你同意 {a}，待你發貨 {s}，待你收貨 {r}，待你評價 {v}，交易私訊未讀 {m}',
    '{a} to approve, {s} to ship, {r} to receive, {v} to review, {m} unread trade messages',
  ],
};

String _text(
  BuildContext context,
  String key, [
  Map<String, String> args = const {},
]) {
  final locale = marketLocale(context);
  var text =
      _copy[key]![locale == 'en'
          ? 2
          : locale == 'hant'
          ? 1
          : 0];
  for (final e in args.entries) {
    text = text.replaceAll('{${e.key}}', e.value);
  }
  return text;
}
