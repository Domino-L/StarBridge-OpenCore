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

  /// Created contracts that wait on the member (recruiting with applicants,
  /// or running). Feeds the banner's "待我处理".
  int get attention => created.rows
      .where(
        (row) =>
            row['status'] == 1 && ((row['applications'] as num?) ?? 0) > 0 ||
            row['status'] == 2,
      )
      .length;

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
    if (acting != null) return false;
    final epoch = _epoch;
    acting = operation;
    actionError = null;
    _notify();
    var confirmed = false;
    try {
      final data = await port.contracts(operation, {
        if (operation != 'create' && openId != null) 'id': openId,
        ...input,
      });
      confirmed = data['confirmed'] == true || data['id'] != null;
    } on MarketplaceTradeError catch (error) {
      actionError = error.code;
    } on Object {
      actionError = 'marketplace.unavailable';
    } finally {
      if (_live(epoch)) {
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
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
