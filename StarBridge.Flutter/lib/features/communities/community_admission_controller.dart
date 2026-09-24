import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../settings/local_privacy_port.dart';
import '../settings/local_privacy_settings.dart';
import 'communities_module.dart';
import 'community_invite_port.dart';

/// Owns only the invitation flow's draft. No publication or implicit audience
/// expansion is performed; local persistence keeps the existing privacy owner.
final class CommunityAdmissionController extends ChangeNotifier {
  CommunityAdmissionController(
    this.invites,
    this.privacy, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _subscriptions.add(invites.invalidations.listen((_) => invalidate()));
    if (privacy != null) {
      _subscriptions.add(privacy!.invalidations.listen((_) => invalidate()));
    }
  }
  final CommunityInvitePort invites;
  final LocalPrivacyPort? privacy;
  final DateTime Function() _now;
  final _subscriptions = <StreamSubscription<void>>[];
  CommunityInvitePreview? preview;
  LocalPrivacySnapshot? baseline;
  LocalPrivacySettings? draft;
  CommunityInviteOutcome? outcome;
  String? error;
  bool busy = false,
      invalidated = false,
      sharing = false,
      acknowledged = false,
      savedChoices = false;
  bool _disposed = false;
  int _epoch = 0;
  final _random = Random.secure();
  bool get expired =>
      (preview?.expiresAt != null && !preview!.expiresAt!.isAfter(_now())) ||
      preview?.remainingUses == 0;
  bool get canJoin =>
      !busy &&
      !invalidated &&
      sharing &&
      draft != null &&
      acknowledged &&
      preview != null &&
      !preview!.alreadyMember &&
      !preview!.membershipConflict &&
      !expired &&
      outcome == null;
  bool _current(int epoch) => !_disposed && !invalidated && epoch == _epoch;

  void clearPreview() {
    if (_disposed || busy || invalidated || outcome?.status == 'unknown') {
      return;
    }
    _epoch++;
    preview = null;
    draft = null;
    baseline = null;
    outcome = null;
    sharing = false;
    acknowledged = false;
    error = null;
    notifyListeners();
  }

  void invalidate() {
    if (_disposed) return;
    _epoch++;
    invalidated = true;
    busy = false;
    preview = null;
    baseline = null;
    draft = null;
    outcome = null;
    notifyListeners();
  }

  Future<void> verify(String code) async {
    if (busy || invalidated || _disposed || outcome?.status == 'unknown') {
      return;
    }
    final epoch = ++_epoch;
    preview = null;
    draft = null;
    baseline = null;
    sharing = false;
    acknowledged = false;
    outcome = null;
    error = null;
    if (code.trim().isEmpty || code.length > 128) {
      error = 'enterCode';
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final value = await invites.previewInvite(code.trim());
      if (_current(epoch)) preview = value;
    } catch (failure) {
      if (_current(epoch)) {
        error = failure is CommunityFailure ? failure.code : 'unavailable';
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> reviewSharing() async {
    if (_disposed ||
        busy ||
        preview == null ||
        preview!.membershipConflict ||
        invalidated ||
        expired ||
        outcome?.status == 'unknown') {
      return;
    }
    if (privacy == null) {
      error = 'privacyUnavailable';
      notifyListeners();
      return;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final value = await privacy!.read();
      if (!_current(epoch)) return;
      baseline = value;
      final latest = value.settings ?? LocalPrivacySettings.editorDefaults;
      // Retry reloads the save lease without discarding the user's fleet choices.
      // Unrelated room fields and group IDs always come from the latest owner.
      draft = draft == null
          ? latest
          : latest.copyWith(
              publicationEnabled: draft!.publicationEnabled,
              fleetFields: draft!.fleetFields,
              fleetAdministratorsCanView: draft!.fleetAdministratorsCanView,
              fleetAllMembersCanView: draft!.fleetAllMembersCanView,
            );
      sharing = true;
      acknowledged = false;
    } catch (_) {
      if (_current(epoch)) error = 'privacyUnavailable';
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void edit(LocalPrivacySettings value) {
    if (_disposed || busy || invalidated || !sharing || outcome != null) return;
    draft = draft!.copyWith(
      publicationEnabled: value.publicationEnabled,
      fleetFields: value.fleetFields,
      fleetAdministratorsCanView: value.fleetAdministratorsCanView,
      fleetAllMembersCanView: value.fleetAllMembersCanView,
    );
    acknowledged = false;
    notifyListeners();
  }

  void acknowledge(bool value) {
    if (_disposed || busy || invalidated || !sharing || outcome != null) return;
    acknowledged = value;
    notifyListeners();
  }

  Future<void> join() async {
    if (!canJoin) return;
    final epoch = _epoch, selected = preview!;
    final submitted = draft!;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (baseline?.settings == null ||
          jsonEncode(baseline!.settings!.toJson()) !=
              jsonEncode(submitted.toJson())) {
        final saved = await privacy!.save(submitted);
        if (!_current(epoch)) return;
        if (saved.settings == null ||
            saved.revision <= baseline!.revision ||
            jsonEncode(saved.settings!.toJson()) !=
                jsonEncode(submitted.toJson())) {
          throw const FormatException('Unconfirmed settings save');
        }
        baseline = saved;
      }
      savedChoices = true;
    } catch (_) {
      if (_current(epoch)) {
        error = 'privacySaveFailed';
        busy = false;
        notifyListeners();
      }
      return;
    }
    if (!_current(epoch)) return;
    if (expired) {
      error = 'inviteInvalid';
      busy = false;
      notifyListeners();
      return;
    }
    final id = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    try {
      final result = await invites.acceptInvite(id, selected.previewRef);
      if (_current(epoch)) {
        outcome = result;
        error = result.error;
      }
    } catch (_) {
      if (_current(epoch)) {
        outcome = const CommunityInviteOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (privacy != null) unawaited(privacy!.close());
    draft = null;
    baseline = null;
    preview = null;
    super.dispose();
  }
}
