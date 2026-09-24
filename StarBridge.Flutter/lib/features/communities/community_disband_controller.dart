import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_disband_port.dart';

final class CommunityDisbandController extends ChangeNotifier {
  CommunityDisbandController(this.port, this.targetRef) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityDisbandPort port;
  final String targetRef;
  late final StreamSubscription<void> _subscription;
  CommunityDisbandPreview? preview;
  CommunityDisbandOutcome? outcome;
  String? error;
  bool loading = false, sending = false, invalidated = false, _closed = false;
  int _epoch = 0;
  bool _current(int epoch) => !_closed && !invalidated && _epoch == epoch;
  bool get canConfirm =>
      !loading &&
      !sending &&
      !invalidated &&
      !_closed &&
      port.disbandAvailable &&
      preview?.canDisband == true &&
      outcome?.status != 'accepted';
  Future<void> load() async {
    if (_closed || invalidated || sending || outcome?.status == 'accepted') {
      return;
    }
    final epoch = ++_epoch;
    loading = true;
    preview = null;
    error = null;
    notifyListeners();
    try {
      if (!port.disbandAvailable) throw const CommunityFailure('unavailable');
      final result = await port.readDisband(targetRef);
      if (!_current(epoch)) return;
      if (result.targetRef != targetRef) {
        throw const CommunityFailure('dataInvalid');
      }
      preview = result;
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

  Future<void> confirm(String password) async {
    if (!canConfirm ||
        !preview!.isExample &&
            (password.trim().isEmpty || password.length > 4096)) {
      return;
    }
    final selected = preview!;
    final epoch = ++_epoch;
    sending = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.disband(
        targetRef,
        selected.confirmationRef,
        selected.isExample ? 'example-only' : password,
      );
      if (!_current(epoch)) return;
      outcome = result;
      if (result.status != 'accepted') {
        _failure(result.error ?? 'outcomeUnknown');
      }
    } catch (_) {
      if (_current(epoch)) {
        outcome = const CommunityDisbandOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
        error = 'outcomeUnknown';
      }
    } finally {
      if (_current(epoch)) {
        sending = false;
        preview = null;
        notifyListeners();
      }
    }
  }

  void _failure(String code) {
    error = code;
    if ({'identityUnavailable', 'notAllowed', 'notFound'}.contains(code)) {
      invalidated = true;
      preview = null;
      loading = sending = false;
      notifyListeners();
    }
  }

  void invalidate() {
    if (_closed) return;
    _epoch++;
    invalidated = true;
    preview = null;
    outcome = null;
    error = 'identityUnavailable';
    loading = sending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    preview = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
