import 'dart:async';

import 'package:flutter/foundation.dart';

import 'marketplace_hall_lists.dart';
import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';

/// The notification-center category of one SCM notice. Colors are chosen per
/// category once the notify-badge preview is approved.
String marketNoticeCategory(MarketRow notice) {
  final type = (notice['type'] as num?)?.toInt();
  if (type == 0) return 'system';
  if (type == 2) return 'chat';
  return switch ((notice['subType'] as num?)?.toInt()) {
    1 => 'trade.request',
    2 => 'trade.approved',
    3 => 'trade.cancelled',
    4 || 5 => 'trade.delivery',
    6 => 'trade.review',
    7 => 'trade.timeout',
    _ => 'trade',
  };
}

/// SCM station messages (0.7.2 G8): unread counts and one page per filter.
/// Marks are sent once and then the page and counts are read again, the same
/// authoritative re-read the notification center uses for its own items.
class MarketplaceNoticesController extends ChangeNotifier {
  MarketplaceNoticesController(this.port) {
    final events = port;
    if (events is MarketplaceTradeEvents) {
      _changes = (events as MarketplaceTradeEvents).tradeChanges.listen((_) {
        if (_used) unawaited(_readChanged());
      });
    }
  }
  final MarketplaceNoticesPort port;

  int unreadTotal = 0, unreadStation = 0, unreadChat = 0;
  int? type; // null = all, 0 system, 1 trade, 2 chat fallback
  bool onlyUnread = false;
  final page = MarketRecordList();
  bool _disposed = false, _used = false, _refreshing = false, _pending = false;
  StreamSubscription<void>? _changes;

  Future<void> _readChanged() async {
    _pending = true;
    if (_refreshing || page.loading || _disposed) return;
    _refreshing = true;
    final epoch = _epoch;
    try {
      do {
        _pending = false;
        await Future.wait([load(), loadCounts()]);
      } while (_pending && _live(epoch));
    } finally {
      _refreshing = false;
    }
  }

  int _epoch = 0;

  bool get supported => port.noticesSupported;
  bool _live(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadCounts() async {
    _used = true;
    final epoch = _epoch;
    try {
      final data = await port.notices('unread');
      if (!_live(epoch)) return;
      unreadTotal = (data['total'] as num?)?.toInt() ?? 0;
      unreadStation = (data['station'] as num?)?.toInt() ?? 0;
      unreadChat = (data['chatFallback'] as num?)?.toInt() ?? 0;
      _notify();
    } on Object {
      // Counts keep their last value; the next read corrects them.
    }
  }

  Future<void> load({bool more = false}) async {
    _used = true;
    final epoch = _epoch;
    await loadHallPage(
      page,
      (n) => port.notices('page', {
        'page': n,
        'type': ?type,
        if (onlyUnread) 'unread': true,
      }),
      more: more,
      live: () => _live(epoch),
      notify: _notify,
    );
    if (_pending && !_refreshing && _live(epoch)) unawaited(_readChanged());
  }

  Future<void> filter({int? type, bool? onlyUnread}) {
    this.type = type;
    if (onlyUnread != null) this.onlyUnread = onlyUnread;
    return load();
  }

  Future<void> markRead(int id) => _mark('read', {'id': id});

  /// Marks every notice of the current filter's type read.
  Future<void> markAllRead() => _mark('readAll', {'type': ?type});

  Future<void> _mark(String operation, MarketRow input) async {
    final epoch = _epoch;
    try {
      await port.notices(operation, input);
    } on Object {
      // The re-read below shows what SCM actually holds.
    }
    if (!_live(epoch)) return;
    await Future.wait([load(), loadCounts()]);
  }

  /// A new account starts empty.
  void reset() {
    _epoch++;
    _used = _pending = false;
    unreadTotal = unreadStation = unreadChat = 0;
    type = null;
    onlyUnread = false;
    clearHallList(page);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
