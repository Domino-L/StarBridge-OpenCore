import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_ownership_exit_port.dart';

final class CommunityOwnershipExitController extends ChangeNotifier {
  CommunityOwnershipExitController(this.port, this.targetRef, this.memberRef) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityOwnershipExitPort port;
  final String targetRef, memberRef;
  late final StreamSubscription<void> _subscription;
  CommunityOwnershipExit? snapshot;
  String? error;
  bool loading = false,
      submitting = false,
      invalidated = false,
      needsRefresh = false,
      left = false,
      requiresRetryConfirmation = false,
      _closed = false;
  int _epoch = 0;
  bool get canLeave =>
      !_closed &&
      !invalidated &&
      !loading &&
      !submitting &&
      !needsRefresh &&
      !left &&
      port.ownershipExitAvailable &&
      snapshot?.canLeave == true;
  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;

  Future<void> load() async {
    if (_closed || invalidated || loading || submitting || left) return;
    if (!port.ownershipExitAvailable) {
      _failure('unavailable');
      notifyListeners();
      return;
    }
    final epoch = ++_epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.readOwnershipExit(
        targetRef: snapshot == null ? targetRef : null,
        memberRef: snapshot == null ? memberRef : null,
        editRef: snapshot?.editRef,
      );
      if (!_current(epoch)) return;
      if (result.targetRef != targetRef || result.memberRef != memberRef) {
        throw const CommunityFailure('dataInvalid');
      }
      snapshot = result;
      needsRefresh = false;
    } catch (e) {
      if (_current(epoch)) {
        _failure(e is CommunityFailure ? e.code : 'unavailable');
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _failure(String code) {
    error = code;
    needsRefresh = true;
    if (const {
      'identityUnavailable',
      'notAllowed',
      'refreshRequired',
      'notFound',
    }.contains(code)) {
      snapshot = null;
      invalidated = true;
      loading = submitting = false;
      notifyListeners();
    }
  }

  Future<void> leave({bool confirmUncertainRetry = false}) async {
    if (!canLeave || requiresRetryConfirmation && !confirmUncertainRetry) {
      return;
    }
    final epoch = ++_epoch;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final random = Random.secure();
      final requestId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final result = await port.leaveWithSuccessor(
        requestId,
        snapshot!.editRef,
        confirmUncertainRetry: confirmUncertainRetry,
      );
      if (!_current(epoch)) return;
      if (result.status == 'accepted') {
        left = true;
        requiresRetryConfirmation = false;
      } else {
        if (result.status == 'unknown') requiresRetryConfirmation = true;
        _failure(result.error ?? 'outcomeUnknown');
      }
    } catch (_) {
      if (_current(epoch)) {
        requiresRetryConfirmation = true;
        _failure('outcomeUnknown');
      }
    } finally {
      if (_current(epoch)) {
        submitting = false;
        notifyListeners();
      }
    }
  }

  void invalidate() {
    if (_closed) return;
    _epoch++;
    invalidated = true;
    snapshot = null;
    error = 'identityUnavailable';
    loading = submitting = left = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    snapshot = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
