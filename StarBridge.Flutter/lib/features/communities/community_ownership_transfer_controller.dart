import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_ownership_transfer_port.dart';

final class CommunityOwnershipTransferController extends ChangeNotifier {
  CommunityOwnershipTransferController(
    this.port,
    this.targetRef,
    this.memberRef,
  ) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityOwnershipTransferPort port;
  final String targetRef, memberRef;
  late final StreamSubscription<void> _subscription;
  CommunityOwnershipTransfer? snapshot;
  String? error;
  bool loading = false,
      submitting = false,
      invalidated = false,
      needsRefresh = false,
      transferred = false,
      requiresRetryConfirmation = false,
      _closed = false;
  int _epoch = 0;
  bool get canTransfer =>
      !_closed &&
      !invalidated &&
      !loading &&
      !submitting &&
      !needsRefresh &&
      !transferred &&
      snapshot?.canTransfer == true;
  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;
  Future<void> load() async {
    if (_closed || invalidated || loading || submitting || transferred) return;
    final epoch = ++_epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.readOwnershipTransfer(
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

  Future<void> transfer({bool confirmUncertainRetry = false}) async {
    if (!canTransfer || requiresRetryConfirmation && !confirmUncertainRetry) {
      return;
    }
    final epoch = ++_epoch;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final outcome = await port.transferOwnership(
        id,
        snapshot!.editRef,
        confirmUncertainRetry: confirmUncertainRetry,
      );
      if (!_current(epoch)) return;
      if (outcome.status == 'accepted') {
        transferred = true;
        requiresRetryConfirmation = false;
      } else {
        if (outcome.status == 'unknown') requiresRetryConfirmation = true;
        _failure(outcome.error ?? 'outcomeUnknown');
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
    loading = submitting = transferred = false;
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
