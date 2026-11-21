import 'dart:async';

import 'package:flutter/foundation.dart';

import 'marketplace_hall_lists.dart';
import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';

/// SCM contracts (0.7.2 G1): the public list with filters, the member's own
/// (created / participated) and one open detail. Every action is sent once;
/// afterwards the detail and lists are read again from SCM.
class MarketplaceContractsController extends ChangeNotifier {
  MarketplaceContractsController(this.port);
  final MarketplaceContractsPort port;

  final public = MarketRecordList();
  final created = MarketRecordList();
  final participated = MarketRecordList();
  String? type; // BOUNTY | SERVICE | COOPERATION
  int? status = 1; // recruiting by default, like the preview
  String keyword = '';

  int? openId;
  MarketRow? detail;
  bool detailLoading = false, detailFailed = false;
  String? acting; // the action in flight
  String? actionError;
  bool _disposed = false;
  int _epoch = 0;

  bool get supported => port.contractsSupported;

  /// Count contracts with an available action, never cumulative applications.
  int get attention => [...created.rows, ...participated.rows]
      .where((row) => row['attention'] == true).map((row) => row['id']).toSet().length;
  bool get attentionIncomplete => [created, participated].any((list) =>
      list.page == 0 || list.more || list.failed ||
      list.rows.any((row) => row['attentionComplete'] != true));
  bool resultUnknown = false;
  // The contract whose write result is unknown (0 = a create). Only a fresh
  // read of THAT contract clears it, and only it is locked (C review P2).
  int? _reconcileId;
  bool get needsReconcile =>
      _reconcileId == 0 || (_reconcileId != null && _reconcileId == openId);

  Future<void> refreshDetail() async {
    final id = openId;
    await _loadDetail();
    if (!detailFailed && detail != null && id == openId &&
        (_reconcileId == 0 || _reconcileId == id)) {
      _reconcileId = null;
      _notify();
    }
  }

  bool _live(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadPublic({bool more = false}) {
    final epoch = _epoch;
    return loadHallPage(
      public,
      (page) => port.contracts('list', {
        'page': page,
        'type': ?type,
        'status': ?status,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      }),
      more: more,
      live: () => _live(epoch),
      notify: _notify,
    );
  }

  Future<void> filter({String? type, int? status, String? keyword}) {
    this.type = type;
    this.status = status;
    if (keyword != null) this.keyword = keyword;
    return loadPublic();
  }

  Future<void> loadMine(String scope, {bool more = false}) {
    final epoch = _epoch;
    return loadHallPage(
      scope == 'participated' ? participated : created,
      (page) => port.contracts('mine', {'scope': scope, 'page': page}),
      more: more,
      live: () => _live(epoch),
      notify: _notify,
    );
  }

  Future<void> open(int id) async {
    openId = id;
    detail = null;
    actionError = null;
    await _loadDetail();
  }

  void close() {
    openId = null;
    detail = null;
    actionError = null;
    _notify();
  }

  Future<void> _loadDetail() async {
    final id = openId;
    if (id == null) return;
    final epoch = _epoch;
    detailLoading = true;
    detailFailed = false;
    _notify();
    try {
      final data = await port.contracts('detail', {'id': id});
      if (!_live(epoch) || openId != id) return;
      detail = data;
    } on Object {
      if (!_live(epoch) || openId != id) return;
      detailFailed = true;
    } finally {
      if (_live(epoch) && openId == id) {
        detailLoading = false;
        _notify();
      }
    }
  }

  /// apply / quit / start / complete / cancel / dispute / review on the open
  /// contract, or create (with `contract`). True when SCM confirmed.
  Future<bool> act(String operation, [MarketRow input = const {}]) async {
    if (acting != null || needsReconcile) return false;
    final epoch = _epoch, target = openId ?? 0;
    acting = operation;
    resultUnknown = false;
    actionError = null;
    _notify();
    var confirmed = false;
    try {
      final data = await port.contracts(operation, {
        if (operation != 'create' && openId != null) 'id': openId,
        ...input,
      });
      confirmed = data['confirmed'] == true || data['id'] != null;
      if (!confirmed) actionError = 'marketplace.unavailable';
    } on MarketplaceTradeError catch (error) {
      actionError = error.code;
    } on Object {
      actionError = 'marketplace.unavailable';
    } finally {
      if (_live(epoch)) {
        resultUnknown = !confirmed && !const {
          'marketplace.reauthorize_required', 'marketplace.invalid_request',
          'marketplace.offline',
        }.contains(actionError);
        if (resultUnknown) _reconcileId = target;
        acting = null;
        _notify();
        await Future.wait([
          _loadDetail(),
          loadMine('created'),
          loadMine('participated'),
          if (public.page > 0) loadPublic(),
        ]);
      }
    }
    return confirmed;
  }

  /// A new account starts empty.
  void reset() {
    _epoch++;
    for (final list in [public, created, participated]) {
      clearHallList(list);
    }
    openId = null;
    detail = null;
    detailLoading = detailFailed = false;
    acting = actionError = null;
    resultUnknown = false;
    _reconcileId = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
