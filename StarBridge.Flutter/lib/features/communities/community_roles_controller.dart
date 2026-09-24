import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Characters;

import 'communities_module.dart';
import 'community_roles_port.dart';
import 'community_profile_port.dart' show CommunityProfileOutcome;

final class CommunityRolesController extends ChangeNotifier {
  CommunityRolesController(this.port, this.targetRef) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityRolesPort port;
  final String targetRef;
  late final StreamSubscription<void> _subscription;
  CommunityEditingRoles? snapshot;
  List<CommunityRole> _roles = const [];
  List<CommunityRole> get roles => _roles;
  String? selectedKey, error;
  CommunityProfileOutcome? outcome;
  bool loading = false,
      submitting = false,
      invalidated = false,
      needsRefresh = false;
  int? _uncertainRevision;
  int _epoch = 0;
  bool _closed = false;
  CommunityRole? get selected =>
      roles.where((r) => r.key == selectedKey).firstOrNull;
  bool get dirty =>
      snapshot != null && _encoded(roles) != _encoded(snapshot!.roles);
  bool get locked =>
      _closed || invalidated || loading || submitting || needsRefresh;
  bool get requiresRetryConfirmation =>
      _uncertainRevision == snapshot?.revision && _uncertainRevision != null;
  bool get canSave =>
      !locked && dirty && roles.every((r) => r.name.trim().isNotEmpty);
  static String _encoded(List<CommunityRole> roles) => jsonEncode(
    roles
        .map(
          (r) => {
            ...r.toDraft(),
            'permissions':
                r.permissions.map((id) => id.toLowerCase()).toSet().toList()
                  ..sort(),
          },
        )
        .toList(),
  );
  static String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;

  bool _renewing = false;
  Future<void> refreshLease() async {
    final before = snapshot;
    if (locked || _renewing || before == null) return;
    final epoch = _epoch;
    _renewing = true;
    try {
      final fresh = await port.readRoles(targetRef: targetRef);
      if (!_current(epoch) || submitting) return;
      if (fresh.targetRef != targetRef) {
        throw const CommunityFailure('dataInvalid');
      }
      if (dirty && _encoded(before.roles) != _encoded(fresh.roles)) {
        error = 'conflict';
        needsRefresh = true;
      } else {
        final keepDraft = dirty;
        snapshot = fresh;
        if (!keepDraft) _roles = fresh.roles;
      }
    } catch (failure) {
      if (_current(epoch) &&
          failure is CommunityFailure &&
          const {'identityUnavailable', 'notAllowed'}.contains(failure.code)) {
        invalidate(failure.code);
      }
    } finally {
      _renewing = false;
      if (_current(epoch)) notifyListeners();
    }
  }

  Future<void> load({bool discardChanges = false}) async {
    if (_closed ||
        invalidated ||
        loading ||
        submitting ||
        (dirty && !discardChanges)) {
      return;
    }
    final epoch = ++_epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final old = snapshot;
      final result = await port.readRoles(targetRef: targetRef);
      if (!_current(epoch)) return;
      _validateRead(
        result,
        old,
        outcome?.status == 'accepted' ? outcome!.revision : null,
      );
      _adopt(result);
      outcome = null;
    } catch (failure) {
      if (_current(epoch)) _readError(failure);
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _validateRead(
    CommunityEditingRoles result,
    CommunityEditingRoles? old,
    int? minimumRevision,
  ) {
    if (result.targetRef != targetRef ||
        (old != null && result.code != old.code)) {
      throw const CommunityFailure('dataInvalid');
    }
    if (minimumRevision != null && result.revision < minimumRevision) {
      throw const CommunityFailure('refreshAfterSave');
    }
  }

  void _adopt(CommunityEditingRoles result) {
    snapshot = result;
    _roles = result.roles;
    if (!roles.any((r) => r.key == selectedKey)) {
      selectedKey = roles.firstOrNull?.key;
    }
    needsRefresh = false;
    if (_uncertainRevision != result.revision) _uncertainRevision = null;
  }

  void select(String key) {
    if (locked || !roles.any((r) => r.key == key)) return;
    selectedKey = key;
    notifyListeners();
  }

  bool update({String? name, String? description, String? color}) {
    final role = selected;
    if (locked ||
        role == null ||
        (name != null && Characters(name).length > communityRoleNameLimit) ||
        (description != null &&
            Characters(description).length > communityRoleDescriptionLimit) ||
        (color != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color))) {
      return false;
    }
    _replace(role.copy(name: name, description: description, color: color));
    return true;
  }

  bool setPermission(String id, bool allowed) {
    final role = selected;
    if (locked ||
        role == null ||
        role.owner ||
        id == 'broadcasts.publish' ||
        !communityRolePermissions.values.expand((v) => v).contains(id)) {
      return false;
    }
    final next = role.permissions
        .where((value) => value.toLowerCase() != id)
        .toList();
    if (allowed) next.add(id);
    _replace(role.copy(permissions: next));
    return true;
  }

  void _replace(CommunityRole role) {
    _roles = List.unmodifiable(
      roles.map((old) => old.key == role.key ? role : old),
    );
    error = null;
    outcome = null;
    notifyListeners();
  }

  void add(String name, {bool copySelected = false}) {
    if (locked ||
        snapshot == null ||
        roles.length >= 512 ||
        name.trim().isEmpty ||
        Characters(name).length > communityRoleNameLimit) {
      return;
    }
    final source = copySelected ? selected : null;
    if (copySelected && (source == null || source.owner)) return;
    final role = CommunityRole(
      key: 'custom_role_${_id()}',
      name: name,
      description: source?.description ?? '',
      color: source?.color ?? '#9B7BFF',
      sortOrder: 10 + roles.length,
      system: false,
      enabled: true,
      memberCount: 0,
      permissions:
          source?.permissions ?? const ['schema.announcements-manage.v1'],
    );
    _roles = List.unmodifiable([...roles, role]);
    selectedKey = role.key;
    error = null;
    outcome = null;
    notifyListeners();
  }

  void removeSelected() {
    final role = selected;
    if (locked || role == null || role.system || role.owner) return;
    _roles = List.unmodifiable(roles.where((r) => r.key != role.key));
    selectedKey = roles.firstOrNull?.key;
    error = null;
    outcome = null;
    notifyListeners();
  }

  void discard() {
    if (locked || snapshot == null) return;
    _adopt(snapshot!);
    error = null;
    outcome = null;
    notifyListeners();
  }

  Future<void> save({bool confirmUncertainRetry = false}) async {
    if (!canSave || (requiresRetryConfirmation && !confirmUncertainRetry)) {
      return;
    }
    final epoch = ++_epoch, baseline = snapshot!;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.saveRoles(
        _id(),
        baseline.editRef,
        roles,
        confirmUncertainRetry: confirmUncertainRetry,
      );
      if (!_current(epoch)) return;
      outcome = result;
      if (result.status == 'accepted' &&
          result.revision != null &&
          result.revision! > baseline.revision) {
        needsRefresh = true;
        try {
          final refreshed = await port.readRoles(editRef: baseline.editRef);
          if (!_current(epoch)) return;
          _validateRead(refreshed, baseline, result.revision);
          _adopt(refreshed);
        } catch (failure) {
          if (_current(epoch)) _readError(failure, afterSave: true);
        }
      } else if (result.status == 'rejected') {
        error = result.error ?? 'unavailable';
        needsRefresh = const {'conflict', 'refreshRequired'}.contains(error);
        if (const {'notAllowed', 'identityUnavailable'}.contains(error)) {
          invalidate(error!);
        }
      } else {
        _unknown(baseline.revision);
      }
    } catch (_) {
      if (_current(epoch)) _unknown(baseline.revision);
    } finally {
      if (_current(epoch)) {
        submitting = false;
        notifyListeners();
      }
    }
  }

  void _unknown(int revision) {
    outcome = const CommunityProfileOutcome('unknown', error: 'outcomeUnknown');
    error = 'outcomeUnknown';
    needsRefresh = true;
    _uncertainRevision = revision;
  }

  void _readError(Object failure, {bool afterSave = false}) {
    final code = failure is CommunityFailure ? failure.code : 'unavailable';
    if (const {
      'notAllowed',
      'identityUnavailable',
      'refreshRequired',
    }.contains(code)) {
      invalidate(code);
    } else {
      error = afterSave ? 'refreshAfterSave' : code;
    }
  }

  void invalidate([String code = 'identityUnavailable']) {
    if (_closed || invalidated) return;
    _epoch++;
    invalidated = true;
    snapshot = null;
    _roles = const [];
    selectedKey = null;
    outcome = null;
    _uncertainRevision = null;
    loading = submitting = needsRefresh = false;
    error = code;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    snapshot = null;
    _roles = const [];
    selectedKey = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
