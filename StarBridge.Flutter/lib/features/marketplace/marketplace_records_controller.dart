import 'dart:async';

import 'package:flutter/foundation.dart';

import 'marketplace_port.dart';
import 'marketplace_time.dart';

/// One paged record list in 我的交易 (reviews, reports or blocklist).
class MarketRecordList {
  List<MarketRow> rows = const [];
  int total = 0, page = 0;
  bool loading = false, failed = false;
  String? error;
  int? tradeTotal, contractTotal;
  bool get more => rows.length < total;
  bool get reviewsComplete => !loading && !failed &&
      tradeTotal != null && contractTotal != null &&
      rows.where((r) => r['sourceType'] == 'trade').length >= tradeTotal! &&
      rows.where((r) => r['sourceType'] == 'contract').length >= contractTotal!;
}

/// The member's own records (0.7.2 G5/G6/G7): reviews received, reports filed
/// and the blocklist with unblock. Reads only what is asked for; an unblock is
/// sent once and then the list is read again (never replayed).
class MarketplaceRecordsController extends ChangeNotifier {
  MarketplaceRecordsController(this.port);
  final MarketplaceRecordsPort port;

  final reviews = MarketRecordList();
  final reports = MarketRecordList();
  String reportKind = 'reports';
  final blocklist = MarketRecordList();
  final Set<String> unblocking = {};
  bool _disposed = false;
  int _epoch = 0;

  bool get supported => port.recordsSupported;

  MarketRecordList _list(String operation) => switch (operation) {
    'reviews' => reviews,
    'reports' => reports,
    _ => blocklist,
  };

  Future<void> load(String operation, {bool more = false}) async {
    final list = _list(operation);
    if (list.loading || more && !list.more) return;
    final epoch = _epoch;
    list
      ..loading = true
      ..failed = false
      ..error = null;
    notifyListeners();
    try {
      final page = more ? list.page + 1 : 1;
      final data = await port.records(operation, {'page': page});
      if (_disposed || epoch != _epoch) return;
      final rows = [
        for (final row in data['rows'] as List? ?? const [])
          if (row is Map) row.cast<String, Object?>(),
      ];
      list
        ..rows = more ? [...list.rows, ...rows] : rows
        ..total = (data['total'] as num?)?.toInt() ?? rows.length
        ..page = page;
      if (operation == 'reviews') {
        list.tradeTotal = (data['tradeTotal'] as num?)?.toInt();
        list.contractTotal = (data['contractTotal'] as num?)?.toInt();
        list.rows.sort((a, b) => (scmInstant(b['createTime'])?.millisecondsSinceEpoch ?? 0)
            .compareTo(scmInstant(a['createTime'])?.millisecondsSinceEpoch ?? 0));
      }
    } on MarketplaceTradeError catch (error) {
      if (_disposed || epoch != _epoch) return;
      list
        ..failed = true
        ..error = error.code;
    } on Object {
      if (_disposed || epoch != _epoch) return;
      list.failed = true;
    } finally {
      if (!_disposed && epoch == _epoch) {
        list.loading = false;
        notifyListeners();
      }
    }
  }

  /// Unblocks one person; true when SCM confirmed. The list is read again
  /// either way, so an uncertain answer shows the real state.
  Future<bool> unblock(String reference) async {
    if (!unblocking.add(reference)) return false;
    notifyListeners();
    var confirmed = false;
    try {
      final data = await port.records('unblock', {'ref': reference});
      confirmed = data['confirmed'] == true;
    } on Object catch (error) {
      blocklist.error = error is MarketplaceTradeError ? error.code : null;
    } finally {
      unblocking.remove(reference);
      if (!_disposed) await load('blocklist');
    }
    return confirmed;
  }

  /// A new account starts empty.
  void reset() {
    _epoch++;
    for (final list in [reviews, reports, blocklist]) {
      list
        ..rows = const []
        ..tradeTotal = null
        ..contractTotal = null
        ..total = 0
        ..page = 0
        ..loading = false
        ..failed = false
        ..error = null;
    }
    unblocking.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
