import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_profile_port.dart';
import 'community_profile_rules.dart';
import 'community_gameplay_tags.dart';
import 'legacy_community_tag_catalog.dart';
import 'community_activity_time.dart';

/// One editor for one organization/account. Never persists drafts or retries POST.
final class CommunityProfileController extends ChangeNotifier {
  CommunityProfileController(this.port, this.targetRef) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityProfilePort port;
  final String targetRef;
  late final StreamSubscription<void> _subscription;
  CommunityEditingProfile? profile;
  Map<String, Object?> _changes = const {};
  Map<String, Object?> get changes => _changes;
  Map<String, Object?> get fields =>
      Map.unmodifiable({...?profile?.fields, ..._changes});
  CommunityProfileOutcome? outcome;
  String? error;
  bool loading = false, submitting = false, invalidated = false;
  bool needsRefresh = false;
  bool _closed = false;
  int _epoch = 0;
  bool get dirty => _changes.isNotEmpty;
  bool get locked =>
      _closed || invalidated || loading || submitting || needsRefresh;
  bool get canSave => !locked && profile != null && dirty;

  bool _renewing = false;
  Future<void> refreshLease() async {
    final before = profile;
    if (locked || _renewing || before == null) return;
    final epoch = _epoch;
    _renewing = true;
    try {
      final fresh = await port.readProfile(targetRef: targetRef);
      if (!_current(epoch) || submitting) return;
      if (fresh.targetRef != targetRef || fresh.code != before.code) {
        throw const CommunityFailure('dataInvalid');
      }
      if (_changes.keys.any(
        (key) =>
            !fresh.permits(key) ||
            !communityProfileEqual(before.fields[key], fresh.fields[key]),
      )) {
        error = 'conflict';
        needsRefresh = true;
      } else {
        profile =
            fresh; // Keep the user's unsaved changes, renew only the baseline.
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
    final previous = profile;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final value = await port.readProfile(
        // Manual refresh obtains a new edit lease; the previous write lease
        // may have expired while the user was reading another section.
        targetRef: targetRef,
      );
      if (!_current(epoch)) return;
      if (value.targetRef != targetRef ||
          (previous != null && value.code != previous.code)) {
        throw const CommunityFailure('dataInvalid');
      }
      if (outcome?.status == 'accepted' &&
          value.revision < outcome!.revision!) {
        throw const CommunityFailure('refreshAfterSave');
      }
      profile = value;
      _changes = const {};
      needsRefresh = false;
      outcome = null;
    } catch (failure) {
      if (_current(epoch)) _handleReadFailure(failure);
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  bool update(String field, Object? value) {
    if (locked || profile == null || !profile!.permits(field)) return false;
    if (fields['recruitingEnabled'] == true &&
        ((field == 'publicListingEnabled' && value == false) ||
            (field == 'joinPolicy' && value == 'Invite'))) {
      return false;
    }
    try {
      value = communityProfileChange(field, value);
    } on FormatException {
      return false;
    }
    final next = {..._changes};
    if (communityProfileEqual(profile!.fields[field], value) ||
        ((field == 'clearLogoImage' || field == 'clearBannerImage') &&
            value == false)) {
      next.remove(field);
    } else {
      next[field] = value;
    }
    if (field == 'logoImageData') next.remove('clearLogoImage');
    if (field == 'clearLogoImage' && value == true) {
      next.remove('logoImageData');
    }
    _changes = Map.unmodifiable(next);
    if (field == 'recruitingEnabled' && value == true) {
      final recruitment = {..._changes};
      if (profile!.fields['publicListingEnabled'] != true) {
        recruitment['publicListingEnabled'] = true;
      } else {
        recruitment.remove('publicListingEnabled');
      }
      if (fields['joinPolicy'] == 'Invite') {
        recruitment['joinPolicy'] = 'Approval';
      }
      _changes = Map.unmodifiable(recruitment);
    }
    error = null;
    outcome = null;
    notifyListeners();
    return true;
  }

  void discard() {
    if (locked) return;
    _changes = const {};
    error = null;
    outcome = null;
    notifyListeners();
  }

  Future<void> save() async {
    if (!canSave) return;
    for (final entry in _changes.entries) {
      if (entry.value is String &&
          !communityProfileTextFits(entry.key, entry.value as String)) {
        error = entry.key == 'name' ? 'nameInvalid' : 'textTooLong';
        notifyListeners();
        return;
      }
    }
    if (_changes.containsKey('activityWindows') &&
        (fields['activityWindows'] as List).any(
          (row) => !communityWindowFits(Map<String, Object?>.from(row as Map)),
        )) {
      error = 'windowInvalid';
      notifyListeners();
      return;
    }
    if (_changes.containsKey('type')) {
      final names = communityTagNames(fields['type'] as String)
          .map((s) => s.toLowerCase())
          .toSet();
      final tags = LegacyCommunityTagCatalog.tags
          .where(
            (tag) =>
                names.contains(tag.id.toLowerCase()) ||
                names.contains(tag.name.toLowerCase()),
          )
          .toList();
      if (tags.length != names.length ||
          !CommunityTagQuota(
            tags.map((tag) => tag.id),
            LegacyCommunityTagCatalog.tags,
          ).valid) {
        error = 'quotaHelp';
        notifyListeners();
        return;
      }
    }
    final epoch = ++_epoch;
    final baseline = profile!;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.saveProfile(id, baseline.editRef, _changes);
      if (!_current(epoch)) return;
      outcome = result;
      if (result.status == 'accepted' &&
          result.revision != null &&
          result.revision! > baseline.revision) {
        needsRefresh = true;
        try {
          final refreshed = await port.readProfile(editRef: baseline.editRef);
          if (!_current(epoch)) return;
          if (refreshed.targetRef != targetRef ||
              refreshed.code != baseline.code ||
              refreshed.revision < result.revision!) {
            throw const CommunityFailure('refreshAfterSave');
          }
          profile = refreshed;
          _changes = const {};
          needsRefresh = false;
        } catch (failure) {
          if (_current(epoch)) _handleReadFailure(failure, afterSave: true);
        }
      } else if (result.status == 'rejected') {
        error = result.error ?? 'unavailable';
        needsRefresh = const {'conflict', 'refreshRequired'}.contains(error);
        if (error == 'notAllowed' || error == 'identityUnavailable') {
          invalidate(error!);
        }
      } else {
        outcome = const CommunityProfileOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
        error = 'outcomeUnknown';
        needsRefresh = true;
      }
    } catch (_) {
      if (_current(epoch)) {
        outcome = const CommunityProfileOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
        error = 'outcomeUnknown';
        needsRefresh = true;
      }
    } finally {
      if (_current(epoch)) {
        submitting = false;
        notifyListeners();
      }
    }
  }

  void _handleReadFailure(Object failure, {bool afterSave = false}) {
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

  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;
  void invalidate([String code = 'identityUnavailable']) {
    if (_closed || invalidated) return;
    _epoch++;
    invalidated = true;
    profile = null;
    _changes = const {};
    outcome = null;
    loading = submitting = needsRefresh = false;
    error = code;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    profile = null;
    _changes = const {};
    outcome = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
