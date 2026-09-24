import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_member_role_port.dart';

final class CommunityMemberRoleController extends ChangeNotifier {
  CommunityMemberRoleController(this.port, this.targetRef, this.memberRef) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityMemberRolePort port;
  final String targetRef, memberRef;
  late final StreamSubscription<void> _subscription;
  CommunityMemberRole? snapshot;
  String? selectedKey, error;
  bool loading = false,
      submitting = false,
      invalidated = false,
      needsRefresh = false,
      saved = false;
  bool requiresRetryConfirmation = false, _closed = false;
  int _epoch = 0;
  String? _acceptedRole;
  bool get dirty => snapshot != null && selectedKey != snapshot!.roleKey;
  bool get locked =>
      _closed || loading || submitting || invalidated || needsRefresh;
  bool get canSave =>
      !locked &&
      snapshot?.canAssign == true &&
      dirty &&
      (selectedKey == '' || snapshot!.roles.any((r) => r.key == selectedKey));
  bool _current(int epoch) => !_closed && !invalidated && _epoch == epoch;
  void _validate(CommunityMemberRole result) {
    if (result.targetRef != targetRef || result.memberRef != memberRef) {
      throw const CommunityFailure('dataInvalid');
    }
  }

  void _adopt(CommunityMemberRole result) {
    snapshot = result;
    selectedKey = result.roleKey;
    needsRefresh = false;
  }

  void select(String key) {
    if (locked ||
        snapshot?.canAssign != true ||
        key != '' && !snapshot!.roles.any((r) => r.key == key)) {
      return;
    }
    selectedKey = key;
    error = null;
    saved = false;
    notifyListeners();
  }

  Future<void> load({bool discardChanges = false}) async {
    if (_closed ||
        invalidated ||
        loading ||
        submitting ||
        dirty && !discardChanges) {
      return;
    }
    final epoch = ++_epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.readMemberRole(
        targetRef: snapshot == null ? targetRef : null,
        memberRef: snapshot == null ? memberRef : null,
        editRef: snapshot?.editRef,
      );
      if (!_current(epoch)) return;
      _validate(result);
      _adopt(result);
      if (_acceptedRole != null) {
        saved = result.roleKey == _acceptedRole;
        error = saved ? null : 'assignmentChanged';
        _acceptedRole = null;
      }
    } catch (e) {
      if (_current(epoch)) _failure(e);
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _failure(Object failure) {
    error = failure is CommunityFailure ? failure.code : 'unavailable';
    if (const {
      'notAllowed',
      'identityUnavailable',
      'refreshRequired',
    }.contains(error)) {
      snapshot = null;
      selectedKey = null;
      invalidated = true;
    } else {
      needsRefresh = true;
    }
  }

  Future<void> save({bool confirmUncertainRetry = false}) async {
    if (!canSave || requiresRetryConfirmation && !confirmUncertainRetry) return;
    final epoch = _epoch, before = snapshot!, chosen = selectedKey!;
    submitting = true;
    error = null;
    saved = false;
    notifyListeners();
    try {
      final id = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final outcome = await port.saveMemberRole(
        id,
        before.editRef,
        chosen,
        confirmUncertainRetry: confirmUncertainRetry,
      );
      if (!_current(epoch)) return;
      if (outcome.status == 'accepted') {
        _acceptedRole = chosen;
        requiresRetryConfirmation = false;
        needsRefresh = true;
        try {
          final result = await port.readMemberRole(editRef: before.editRef);
          if (!_current(epoch)) return;
          _validate(result);
          _adopt(result);
          saved = result.roleKey == chosen;
          error = saved ? null : 'assignmentChanged';
          _acceptedRole = null;
        } catch (e) {
          if (!_current(epoch)) return;
          _failure(e);
          if (!invalidated) error = 'assignmentRefreshFailed';
        }
      } else {
        error = outcome.error ?? 'outcomeUnknown';
        needsRefresh = true;
        if (outcome.status == 'unknown') requiresRetryConfirmation = true;
        if (const {
          'notAllowed',
          'identityUnavailable',
          'refreshRequired',
        }.contains(error)) {
          _failure(CommunityFailure(error!));
        }
      }
    } catch (_) {
      if (_current(epoch)) {
        error = 'outcomeUnknown';
        requiresRetryConfirmation = true;
        needsRefresh = true;
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
    selectedKey = null;
    error = 'identityUnavailable';
    saved = loading = submitting = false;
    _acceptedRole = null;
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
