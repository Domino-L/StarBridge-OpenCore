import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_logs_port.dart';

final class CommunityLogsController extends ChangeNotifier {
  CommunityLogsController(this.port, this.targetRef) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityLogsPort port;
  final String targetRef;
  late final StreamSubscription<void> _subscription;
  CommunityLogPage? snapshot;
  CommunityLogEntry? pendingDeletion;
  String type = 'All', query = '';
  String? error, lastOutcome;
  bool loading = false,
      submitting = false,
      invalidated = false,
      _closed = false;
  int _epoch = 0;
  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;
  bool get canDelete =>
      !_closed &&
      !invalidated &&
      !loading &&
      !submitting &&
      port.logDeletionAvailable &&
      snapshot?.canDelete == true;

  Future<void> load({
    String? filter,
    String? search,
    int offset = 0,
    bool quiet = false,
  }) async {
    if (_closed || invalidated || submitting) return;
    if (quiet && (loading || pendingDeletion != null)) return;
    final previous = snapshot;
    final epoch = ++_epoch;
    type = filter ?? type;
    query = (search ?? query).trim();
    if (!quiet) snapshot = null;
    pendingDeletion = null;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!port.logsAvailable) throw const CommunityFailure('unavailable');
      final result = await port.readLogs(targetRef, type, query, offset);
      if (!_current(epoch)) return;
      if (result.targetRef != targetRef ||
          result.type != type ||
          result.query != query ||
          result.offset != offset) {
        throw const CommunityFailure('dataInvalid');
      }
      snapshot = result;
    } catch (e) {
      if (_current(epoch)) {
        _failure(e is CommunityFailure ? e.code : 'unavailable');
        if (quiet && error == 'unavailable') snapshot = previous;
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void selectForDeletion(CommunityLogEntry entry) {
    if (!canDelete || !snapshot!.items.contains(entry)) return;
    pendingDeletion = entry;
    notifyListeners();
  }

  void cancelDeletion() {
    if (_closed || submitting) return;
    pendingDeletion = null;
    notifyListeners();
  }

  Future<void> confirmDeletion() async {
    if (!canDelete || pendingDeletion == null) return;
    final entry = pendingDeletion!;
    final epoch = ++_epoch;
    submitting = true;
    error = lastOutcome = null;
    notifyListeners();
    try {
      final result = await port.deleteLog(targetRef, entry.logRef);
      if (!_current(epoch)) return;
      lastOutcome = result.status;
      if (result.status != 'accepted') {
        _failure(result.error ?? 'outcomeUnknown');
      }
    } catch (_) {
      if (_current(epoch)) {
        lastOutcome = 'unknown';
        _failure('outcomeUnknown');
      }
    } finally {
      if (_current(epoch)) {
        // The Host consumes this reference on send. Re-read and explicitly select before any new attempt.
        submitting = false;
        pendingDeletion = null;
        snapshot = null;
        notifyListeners();
      }
    }
    if (_current(epoch) && lastOutcome == 'accepted') await load();
  }

  void _failure(String code) {
    error = code;
    if ({'identityUnavailable', 'notAllowed', 'notFound'}.contains(code)) {
      invalidated = true;
      snapshot = null;
      pendingDeletion = null;
      query = '';
      loading = submitting = false;
      notifyListeners();
    }
  }

  void invalidate() {
    if (_closed) return;
    _epoch++;
    invalidated = true;
    snapshot = null;
    pendingDeletion = null;
    query = '';
    error = 'identityUnavailable';
    lastOutcome = null;
    loading = submitting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    snapshot = null;
    pendingDeletion = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
