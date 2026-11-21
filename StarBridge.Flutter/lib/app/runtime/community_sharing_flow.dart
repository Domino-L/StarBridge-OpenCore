import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import '../../features/settings/community_sharing.dart';
import '../../features/communities/community_hangar_sharing_port.dart';
import '../../features/settings/community_join_hangar_choice.dart';
import '../../features/settings/community_sharing_dialog.dart';
import '../../features/settings/event_sharing_controller.dart';
import '../../features/settings/event_scope_editor.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../features/settings/local_privacy_controller.dart';
import 'startup_prompt_queue.dart';

/// Membership discovery also observes admissions completed on another client.
/// A roster is not consent; only the dialog action persists a scope.
final class CommunitySharingFlow {
  CommunitySharingFlow({
    required this.privacy,
    required this.queue,
    required this.ready,
    this.membershipChanges,
    this.hangarSharing,
    BridgeClientSession? eventSession,
  }) : _discoveryScopeEpoch = privacy.scopeEpoch,
       _events =
           eventSession?.hostCapabilities.contains('eventSharing.settings') ==
               true
           ? EventSharingController(eventSession!)
           : null {
    privacy.addListener(_changed);
    _events?.addListener(_changed);
    membershipChanges?.addListener(_membershipChanged);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _poll());
  }
  final LocalPrivacyController privacy;
  final StartupPromptQueue queue;
  final bool Function() ready;
  final Listenable? membershipChanges;
  final CommunityHangarSharingPort? hangarSharing;
  final EventSharingController? _events;
  final Object _key = Object();
  late final Timer _timer;
  Timer? _membershipRefresh;
  bool _discovering = false;
  bool _discoveryPending = false;
  int _discoveryScopeEpoch;
  bool _disposed = false, _showing = false;
  StarBridgeDialogRoute<void>? _route;
  CommunitySharingTarget? _target;
  int? _epoch;
  bool get _eligible =>
      !_disposed &&
      ready() &&
      (_events == null || _events.canEdit) &&
      privacy.communitySharingSupported &&
      privacy.canEdit &&
      !privacy.dirty &&
      privacy.publicationView.firstUseRequired == false &&
      const {
        'applied',
        'pending',
        'publishing',
        'identityRequired',
        'reconnecting',
        'inactive',
        'withdrawn',
      }.contains(privacy.publicationView.state);

  List<CommunitySharingTarget> get _pending => privacy.communityTargetsFailed
      ? const []
      : privacy.draft?.communities == null
      ? privacy.communityTargets?.communities ?? const []
      : privacy.unconfirmedCommunities;

  void _membershipChanged() {
    if (_disposed) return;
    _syncDiscoveryScope();
    _membershipRefresh?.cancel();
    if (_discovering) {
      // Remember the event now, even if this round ends before debounce expires.
      unawaited(_poll());
      return;
    }
    _membershipRefresh = Timer(const Duration(milliseconds: 100), _poll);
  }

  void _syncDiscoveryScope() {
    if (_discoveryScopeEpoch == privacy.scopeEpoch) return;
    _discoveryScopeEpoch = privacy.scopeEpoch;
    _discoveryPending = false;
    _membershipRefresh?.cancel();
  }

  Future<void> _poll() async {
    if (_disposed || !ready()) return;
    _syncDiscoveryScope();
    if (_discovering) {
      _discoveryPending = true;
      return;
    }
    final epoch = privacy.scopeEpoch;
    _discovering = true;
    try {
      await privacy.refreshCommunityTargets();
      if (_disposed || epoch != privacy.scopeEpoch) return;
      await privacy.refreshPublication();
      _changed();
    } finally {
      _discovering = false;
      _syncDiscoveryScope();
      if (_discoveryPending) {
        // A boolean coalesces all requests during this round into one reread.
        _discoveryPending = false;
        unawaited(_poll());
      }
    }
  }

  void _changed() {
    if (_disposed) return;
    _syncDiscoveryScope();
    if (_epoch != null &&
        (_epoch != privacy.scopeEpoch ||
            !ready() ||
            privacy.communityTargetsFailed ||
            !(privacy.communityTargets?.communities.any(
                  (t) =>
                      t.code == _target?.code &&
                      t.joinedAt == _target?.joinedAt,
                ) ??
                false))) {
      _dismiss();
    }
    if (!_eligible || _showing || _pending.isEmpty) {
      return;
    }
    queue.enqueue(
      _key,
      priority: 150,
      eligible: () => _eligible && !_showing && _pending.isNotEmpty,
      show: _show,
    );
  }

  Future<void> _show() async {
    if (!_eligible) return;
    final navigator = queue.navigator;
    if (navigator == null) return;
    _showing = true;
    try {
      await privacy.refreshCommunityTargets();
      if (!_eligible || _pending.isEmpty || !navigator.mounted) {
        return;
      }
      final target = _target = _pending.first;
      final epoch = _epoch = privacy.scopeEpoch;
      bool current() =>
          !_disposed &&
          ready() &&
          epoch == privacy.scopeEpoch &&
          !privacy.communityTargetsFailed &&
          (privacy.communityTargets?.communities.any(
                (t) => t.code == target.code && t.joinedAt == target.joinedAt,
              ) ??
              false);
      await _events?.refresh();
      if (!current() || !navigator.mounted) return;
      await showStarBridgeDialog<void>(
        navigator.context,
        source: InteractionSource.programmatic,
        onRouteCreated: (route) => _route = route,
        barrierDismissible: false,
        builder: (_) => CommunitySharingDialog(
          target: target,
          legacyTransition: privacy.draft?.communities == null,
          sharingEnabled: privacy.draft?.publicationEnabled == true,
          initialEvents:
              _events != null &&
                  _events.canEdit &&
                  _events.hasCommunityChoice(target)
              ? _events.choice(target.code)
              : const EventSharingChoice(
                  enabled: true,
                  selectedTypes: EventSharingChoice.allTypes,
                ),
          onSaveEvents: _events == null
              ? null
              : (choice) async {
                  if (!current()) return false;
                  await privacy.refreshCommunityTargets();
                  if (!current()) return false;
                  final saved = await _events.saveJoinedCommunityChoice(
                    target,
                    choice,
                  );
                  return saved && current();
                },
          onSaveHangar: hangarSharing?.hangarSharingAvailable == true
              ? (share) => saveJoinedCommunityHangarChoice(
                  port: hangarSharing!,
                  target: target,
                  share: share,
                  membershipCurrent: () async {
                    if (!current()) return false;
                    await privacy.refreshCommunityTargets();
                    return current() && privacy.canEdit;
                  },
                )
              : null,
          onSave: (scope) async {
            if (!current() || !privacy.canEdit) return false;
            await privacy.refreshCommunityTargets();
            if (!current() || !privacy.canEdit) return false;
            // Only this explicit dialog choice converts legacy scopes. Preserve
            // their explicitly associated audience, never grant all memberships.
            if (privacy.draft?.communities == null) {
              privacy.enableCommunityChoices();
            }
            privacy.editCommunity(scope);
            if (!privacy.canSave) return false;
            // Confirming a new audience is not changing the master switch.
            final saved = await privacy.save(refreshStatus: false);
            if (saved) await privacy.refreshPublication();
            if (!saved && current() && privacy.needsReload) {
              await privacy.refresh();
            }
            return saved && current();
          },
        ),
      );
    } finally {
      _route = null;
      _target = null;
      _epoch = null;
      _showing = false;
      _changed();
    }
  }

  void _dismiss() {
    final route = _route;
    _route = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    _discoveryPending = false;
    _timer.cancel();
    _membershipRefresh?.cancel();
    membershipChanges?.removeListener(_membershipChanged);
    privacy.removeListener(_changed);
    _events?.removeListener(_changed);
    _events?.dispose();
    queue.cancel(_key);
    _dismiss();
  }
}
