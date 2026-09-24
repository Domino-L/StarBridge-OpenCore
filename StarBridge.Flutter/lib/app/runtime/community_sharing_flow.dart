import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/settings/community_sharing.dart';
import '../../features/settings/community_sharing_dialog.dart';
import '../../features/settings/local_privacy_controller.dart';
import 'startup_prompt_queue.dart';

/// Membership discovery also observes admissions completed on another client.
/// A roster is not consent; only the dialog action persists a scope.
final class CommunitySharingFlow {
  CommunitySharingFlow({
    required this.privacy,
    required this.queue,
    required this.ready,
  }) {
    privacy.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }
  final LocalPrivacyController privacy;
  final StartupPromptQueue queue;
  final bool Function() ready;
  final Object _key = Object();
  late final Timer _timer;
  bool _disposed = false, _showing = false;
  DialogRoute<void>? _route;
  CommunitySharingTarget? _target;
  int? _epoch;
  bool get _eligible =>
      !_disposed &&
      ready() &&
      privacy.communitySharingSupported &&
      privacy.canEdit &&
      !privacy.dirty &&
      privacy.draft?.publicationEnabled == true &&
      privacy.publicationView.firstUseRequired == false &&
      const {
        'applied',
        'pending',
        'publishing',
        'identityRequired',
        'reconnecting',
      }.contains(privacy.publicationView.state);

  Future<void> _poll() async {
    if (_disposed || !ready() || privacy.draft?.communities == null) return;
    await privacy.refreshCommunityTargets();
    if (_disposed) return;
    await privacy.refreshPublication();
    _changed();
  }

  void _changed() {
    if (_disposed) return;
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
    if (!_eligible || _showing || privacy.unconfirmedCommunities.isEmpty) {
      return;
    }
    queue.enqueue(
      _key,
      priority: 150,
      eligible: () =>
          _eligible && !_showing && privacy.unconfirmedCommunities.isNotEmpty,
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
      if (!_eligible ||
          privacy.unconfirmedCommunities.isEmpty ||
          !navigator.mounted) {
        return;
      }
      final target = _target = privacy.unconfirmedCommunities.first;
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
      final route = DialogRoute<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => CommunitySharingDialog(
          target: target,
          onSave: (scope) async {
            if (!current() || !privacy.canEdit) return false;
            await privacy.refreshCommunityTargets();
            if (!current() || !privacy.canEdit) return false;
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
      _route = route;
      await navigator.push(route);
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
    _timer.cancel();
    privacy.removeListener(_changed);
    queue.cancel(_key);
    _dismiss();
  }
}
