import 'dart:async';

import 'package:flutter/foundation.dart';

import '../communities/communities_module.dart';
import 'organization_announcement_management_port.dart';

/// Account-own query presentation, never a second journal or mutation queue.
/// A full pending scan is a bounded UI observation, not an atomic store cursor.
final class OrganizationAnnouncementOutcomesController extends ChangeNotifier {
  OrganizationAnnouncementOutcomesController(this.port) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final OrganizationAnnouncementManagementPort port;
  late final StreamSubscription<void> _subscription;
  List<OrganizationAnnouncementPending> _items = const [];
  final _results = <String, OrganizationAnnouncementOutcome>{};
  List<OrganizationAnnouncementPending> get items => _items;
  Map<String, OrganizationAnnouncementOutcome> get results =>
      Map.unmodifiable(_results);
  int? get totalCount => complete ? _items.length : null;
  bool loading = false, complete = false, _closed = false;
  String? error, queryingRequestId;
  int _epoch = 0;

  Future<void> refresh() async {
    if (_closed || loading || queryingRequestId != null) return;
    final epoch = _epoch;
    loading = true;
    complete = false;
    error = null;
    notifyListeners();
    try {
      if (!port.outcomesAvailable) throw const CommunityFailure('unavailable');
      final rows = <OrganizationAnnouncementPending>[];
      final seen = <String>{};
      int? total;
      var offset = 0;
      for (var pageNumber = 0; pageNumber < 7; pageNumber++) {
        final page = await port.readPending(offset: offset);
        if (!_current(epoch)) return;
        if (page.offset != offset ||
            total != null && page.totalCount != total) {
          throw const FormatException();
        }
        total ??= page.totalCount;
        for (final row in page.items) {
          if (!seen.add(row.requestId)) throw const FormatException();
          rows.add(row);
        }
        if (rows.length > 128) throw const FormatException();
        if (page.next == null) {
          if (rows.length != total) throw const FormatException();
          _items = List.unmodifiable(rows);
          _results.removeWhere((id, _) => !seen.contains(id));
          complete = true;
          return;
        }
        if (page.next != offset + 20) throw const FormatException();
        offset = page.next!;
      }
      throw const FormatException();
    } catch (failure) {
      if (_current(epoch)) {
        error = failure is CommunityFailure ? failure.code : 'dataInvalid';
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  bool hasUnresolvedSource(String sourceRef) =>
      !complete ||
      _items.any(
        (row) =>
            row.sourceRef == sourceRef &&
            (_results[row.requestId]?.unresolved ?? true),
      );

  Future<OrganizationAnnouncementOutcome?> query(
    String requestId, {
    OrganizationAnnouncementIntent? original,
  }) async {
    if (_closed || loading || queryingRequestId != null) return null;
    OrganizationAnnouncementPending? pending;
    for (final row in _items) {
      if (row.requestId == requestId) pending = row;
    }
    if (original != null && original.requestId != requestId ||
        original == null && pending == null) {
      error = 'dataInvalid';
      notifyListeners();
      return null;
    }
    final source = original?.sourceRef ?? pending!.sourceRef;
    final action = original?.action ?? pending!.action;
    final epoch = _epoch;
    queryingRequestId = requestId;
    error = null;
    notifyListeners();
    try {
      if (!port.outcomesAvailable) throw const CommunityFailure('unavailable');
      final result = await port.query(
        requestId,
        expectedSourceRef: source,
        expectedAction: action,
      );
      if (!_current(epoch)) return null;
      if (result.requestId != requestId ||
          result.sourceRef != null && result.sourceRef != source ||
          result.action != null && result.action != action) {
        throw const FormatException();
      }
      // notFound remains an unknown observation. Neither queries nor refreshes
      // create an operation, replace an ID or restore a private editing ref.
      if (_items.any((row) => row.requestId == requestId)) {
        _results[requestId] = result;
      }
      return result;
    } catch (failure) {
      if (_current(epoch)) {
        error = failure is CommunityFailure ? failure.code : 'dataInvalid';
      }
      return null;
    } finally {
      if (_current(epoch)) {
        queryingRequestId = null;
        notifyListeners();
      }
    }
  }

  bool _current(int epoch) => !_closed && _epoch == epoch;
  void invalidate() {
    if (_closed) return;
    _epoch++;
    _items = const [];
    _results.clear();
    loading = complete = false;
    queryingRequestId = null;
    error = 'identityUnavailable';
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
