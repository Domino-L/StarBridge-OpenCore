import 'dart:async';

import 'package:flutter/foundation.dart';

import 'marketplace_hall_lists.dart';
import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';

/// The member's own SCM warehouse, read only (0.7.2 G2): spaces with totals,
/// the selected space's inventory, the ledger and listing escrow. Transfers,
/// counts and stock-out stay on the SCM site for this version.
class MarketplaceWarehouseController extends ChangeNotifier {
  MarketplaceWarehouseController(this.port);
  final MarketplaceWarehousePort port;

  List<MarketRow> spaces = const [];
  MarketRow? summary;
  bool spacesLoading = false, spacesFailed = false;
  int? spaceId; // null = every space
  String keyword = '';
  bool onlyAvailable = false;
  final inventory = MarketRecordList();
  final ledger = MarketRecordList();
  List<MarketRow> escrow = const [];
  int? _escrowNext;
  bool escrowMore = false, escrowLoading = false, escrowFailed = false;
  bool _disposed = false;
  int _epoch = 0;

  bool get supported => port.warehouseSupported;
  bool _live(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadSpaces() async {
    final epoch = _epoch;
    spacesLoading = true;
    spacesFailed = false;
    _notify();
    try {
      final results = await Future.wait([
        port.warehouse('spaces'),
        port.warehouse('summary'),
      ]);
      if (!_live(epoch)) return;
      spaces = hallRows(results[0]);
      summary = results[1];
    } on Object {
      if (!_live(epoch)) return;
      spacesFailed = true;
    } finally {
      if (_live(epoch)) {
        spacesLoading = false;
        _notify();
      }
    }
  }

  Future<void> select(int? space) {
    spaceId = space;
    return Future.wait([loadInventory(), loadLedger()]).then((_) {});
  }

  Future<void> search({String? keyword, bool? onlyAvailable}) {
    if (keyword != null) this.keyword = keyword;
    if (onlyAvailable != null) this.onlyAvailable = onlyAvailable;
    return loadInventory();
  }

  Future<void> loadInventory({bool more = false}) {
    final epoch = _epoch;
    return loadHallPage(
      inventory,
      (page) => port.warehouse('inventory', {
        'page': page,
        'spaceId': ?spaceId,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        if (onlyAvailable) 'available': true,
      }),
      more: more,
      live: () => _live(epoch),
      notify: _notify,
    );
  }

  Future<void> loadLedger({bool more = false}) {
    final epoch = _epoch;
    return loadHallPage(
      ledger,
      (page) => port.warehouse('ledger', {'page': page, 'spaceId': ?spaceId}),
      more: more,
      live: () => _live(epoch),
      notify: _notify,
    );
  }

  Future<void> loadEscrow({bool more = false}) async {
    if (escrowLoading || more && !escrowMore) return;
    final epoch = _epoch;
    escrowLoading = true;
    escrowFailed = false;
    _notify();
    try {
      final data = await port.warehouse('escrow', {
        if (more) 'after': ?_escrowNext,
      });
      if (!_live(epoch)) return;
      final rows = hallRows(data);
      escrow = more ? [...escrow, ...rows] : rows;
      _escrowNext = (data['next'] as num?)?.toInt();
      escrowMore = data['more'] == true && _escrowNext != null;
    } on Object {
      if (!_live(epoch)) return;
      escrowFailed = true;
    } finally {
      if (_live(epoch)) {
        escrowLoading = false;
        _notify();
      }
    }
  }

  /// A new account starts empty.
  void reset() {
    _epoch++;
    spaces = escrow = const [];
    summary = null;
    spaceId = null;
    keyword = '';
    onlyAvailable = spacesLoading = spacesFailed = false;
    escrowMore = escrowLoading = escrowFailed = false;
    _escrowNext = null;
    clearHallList(inventory);
    clearHallList(ledger);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
