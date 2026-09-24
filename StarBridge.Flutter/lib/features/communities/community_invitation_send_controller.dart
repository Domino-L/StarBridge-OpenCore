import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_invitation_send_port.dart';

enum InvitationRecoveryAction { check, continueSending, retryDelivery }

/// One account-bound dialog. Host owns persistence and all remote retry policy.
/// Opening or refreshing this controller only reads the protected outbox.
final class CommunityInvitationSendController extends ChangeNotifier {
  CommunityInvitationSendController(this.port, {String Function()? createId})
    : _createId = createId ?? _newId {
    _subscription = port.invalidations.listen((_) => invalidate());
  }

  final CommunityInvitationSendPort port;
  final String Function() _createId;
  late final StreamSubscription<void> _subscription;
  List<CommunityInvitationOperation> _items = const [];
  List<CommunityInvitationOperation> get items => _items;
  CommunityInvitationProgress? progress;
  String? error;
  String? activeOperationId;
  bool busy = false, loaded = false, invalidated = false;
  bool _closed = false;
  int _epoch = 0;

  bool get locked => _closed || invalidated || busy;
  bool get canStart =>
      !locked &&
      port.invitationSendingAvailable &&
      loaded &&
      error == null &&
      activeOperationId == null;

  Future<void> load() async {
    if (locked) return;
    if (!port.invitationSendingAvailable) {
      error = 'unavailable';
      notifyListeners();
      return;
    }
    final epoch = ++_epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!_current(epoch)) return;
      final value = await port.readInvitationOutbox();
      if (!_current(epoch)) return;
      _items = List.unmodifiable(value);
      loaded = true;
    } catch (failure) {
      if (_current(epoch)) {
        loaded = false;
        error = _readError(failure);
      }
    } finally {
      _finish(epoch);
    }
  }

  /// A second click never allocates another intent, even after an unknown reply.
  Future<void> start({
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) async {
    if (!canStart) return;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(organizationRef) ||
        !{'private', 'room'}.contains(channel) ||
        destinationRef.isEmpty ||
        destinationRef.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(destinationRef) ||
        (channel == 'private' &&
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(destinationRef)) ||
        maxUses < 1 ||
        maxUses > 50) {
      error = 'dataInvalid';
      notifyListeners();
      return;
    }
    final id = _createId();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        _items.any((item) => item.operationId == id)) {
      error = 'dataInvalid';
      notifyListeners();
      return;
    }
    activeOperationId = id;
    await _run(
      id,
      () => port.sendInvitation(
        operationId: id,
        organizationRef: organizationRef,
        channel: channel,
        destinationRef: destinationRef,
        maxUses: maxUses,
      ),
    );
  }

  Future<void> recover(
    String id, {
    InvitationRecoveryAction action = InvitationRecoveryAction.check,
    bool retryConfirmed = false,
  }) async {
    if (locked || !port.invitationSendingAvailable || !loaded) return;
    final rows = _items.where((item) => item.operationId == id);
    final row = rows.isEmpty ? null : rows.single;
    if (row == null && id != activeOperationId) return;
    if (progress?.operationId == id && progress?.status == 'sent') return;
    if (action == InvitationRecoveryAction.continueSending &&
        (row == null ||
            !{'prepared', 'generating', 'ready'}.contains(row.phase))) {
      return;
    }
    if (action == InvitationRecoveryAction.retryDelivery &&
        (!retryConfirmed || row?.phase != 'sending')) {
      return;
    }
    activeOperationId = id;
    await _run(
      id,
      () => port.resumeInvitation(
        id,
        action: switch (action) {
          InvitationRecoveryAction.check => 'check',
          InvitationRecoveryAction.continueSending => 'advance',
          InvitationRecoveryAction.retryDelivery => 'retryDelivery',
        },
      ),
    );
  }

  Future<void> _run(
    String id,
    Future<CommunityInvitationProgress> Function() operation,
  ) async {
    final epoch = ++_epoch;
    busy = true;
    error = null;
    progress = null;
    notifyListeners();
    try {
      if (!_current(epoch)) return;
      final result = await operation();
      if (!_current(epoch)) return;
      if (result.operationId != id ||
          !{'pending', 'unknown', 'rejected', 'sent'}.contains(result.status)) {
        throw const FormatException();
      }
      progress = result;
    } catch (failure) {
      if (!_current(epoch)) return;
      progress = CommunityInvitationProgress(
        id,
        'unknown',
        failure is CommunityFailure &&
                failure.code == 'localRecoveryUnavailable'
            ? 'localRecoveryUnavailable'
            : 'outcomeUnknown',
      );
    } finally {
      if (_current(epoch)) {
        // A failed list refresh must not erase the confirmed send outcome.
        try {
          final value = await port.readInvitationOutbox();
          if (_current(epoch)) _items = List.unmodifiable(value);
        } catch (failure) {
          if (_current(epoch)) error = _readError(failure);
        }
        _finish(epoch);
      }
    }
  }

  void invalidate() {
    if (_closed || invalidated) return;
    invalidated = true;
    _epoch++;
    busy = false;
    loaded = false;
    _items = const [];
    progress = null;
    error = null;
    activeOperationId = null;
    notifyListeners();
  }

  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;
  void _finish(int epoch) {
    if (!_current(epoch)) return;
    busy = false;
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

String _readError(Object failure) =>
    failure is CommunityFailure ? failure.code : 'unavailable';
String _newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
