import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/account/account_models.dart';
import '../../features/account/account_module.dart';
import '../../features/settings/first_use_privacy_dialog.dart';
import '../../features/settings/local_privacy_controller.dart';
import '../../features/settings/local_privacy_settings.dart';
import 'startup_prompt_queue.dart';
import 'community_sharing_flow.dart';

/// Binds one composition's account to a remembered, Host-owned privacy choice.
/// No preference file is touched until the user chooses a dialog action.
final class FirstUsePrivacyFlow {
  FirstUsePrivacyFlow({
    required this.account,
    required this.privacy,
    required this.queue,
    required this.ready,
    required this.onAdjust,
  }) {
    account.projection.addListener(wake);
    privacy.addListener(_privacyChanged);
    _communities = CommunitySharingFlow(
      privacy: privacy,
      queue: queue,
      ready: () =>
          !_disposed &&
          ready() &&
          _signedIn &&
          !account.projection.value.isBusy &&
          !blocksOptionalPrompt,
    );
  }
  final AccountModule account;
  final LocalPrivacyController privacy;
  final StartupPromptQueue queue;
  final bool Function() ready;
  final VoidCallback onAdjust;
  final Object _key = Object();
  late final CommunitySharingFlow _communities;
  bool _disposed = false, _reading = false, _checked = false, _showing = false;
  int? _generation;
  int _readToken = 0;
  Timer? _retry;
  DialogRoute<bool>? _route;
  bool _adjusting = false;
  int? _dialogEpoch;

  bool get _signedIn => switch (account.projection.value.sessionState) {
    AccountSessionState.signedIn || AccountSessionState.legacySignedIn => true,
    _ => false,
  };
  bool get blocksOptionalPrompt =>
      privacy.publicationSupported &&
      _newAccount &&
      !privacy.hasSaved &&
      (!_checked ||
          _reading ||
          privacy.publicationView.firstUseRequired == true);

  bool get _newAccount =>
      account.projection.value.sessionState == AccountSessionState.signedIn;

  void _privacyChanged() {
    if (_dialogEpoch != null && _dialogEpoch != privacy.scopeEpoch) _dismiss();
    if (privacy.status == LocalPrivacyStatus.initial) _checked = false;
    wake();
  }

  void wake() {
    if (_disposed) return;
    final generation = account.projection.value.generation;
    if (_generation != generation) {
      _generation = generation;
      _adjusting = false;
      _checked = false;
      _reading = false;
      _readToken++;
      _dismiss();
    }
    if (!_signedIn) _dismiss();
    queue.wake();
    if (!ready() ||
        !_signedIn ||
        account.projection.value.isBusy ||
        !privacy.publicationSupported ||
        _reading ||
        _showing) {
      return;
    }
    if (!_checked &&
        !privacy.dirty &&
        !privacy.saving &&
        !privacy.publicationBusy &&
        privacy.status != LocalPrivacyStatus.loading) {
      unawaited(_read());
      return;
    }
    if (_newAccount &&
        !privacy.hasSaved &&
        privacy.publicationView.firstUseRequired == true) {
      queue.enqueue(
        _key,
        priority: 100,
        eligible: () =>
            !_disposed &&
            ready() &&
            _signedIn &&
            !account.projection.value.isBusy &&
            _checked &&
            !_showing &&
            !_adjusting &&
            privacy.canEdit &&
            !privacy.dirty &&
            privacy.publicationView.firstUseRequired == true,
        show: _show,
      );
    } else {
      queue.cancel(_key);
    }
  }

  Future<void> _read() async {
    final token = ++_readToken;
    _reading = true;
    await privacy.refresh();
    if (_disposed || token != _readToken) return;
    _reading = false;
    _checked = true;
    if (privacy.status != LocalPrivacyStatus.ready ||
        privacy.publicationView.state == 'failed') {
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 10), () {
        _checked = false;
        wake();
      });
    }
    wake();
  }

  Future<void> _show() async {
    final navigator = queue.navigator;
    if (navigator == null) return;
    _showing = true;
    final epoch = privacy.scopeEpoch;
    final generation = _generation;
    _dialogEpoch = epoch;
    bool current() =>
        !_disposed &&
        _signedIn &&
        _generation == generation &&
        privacy.scopeEpoch == epoch;
    final initial = (privacy.draft ?? LocalPrivacySettings.editorDefaults);
    final hadSavedChoices = privacy.hasSaved;
    final route = DialogRoute<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => FirstUsePrivacyDialog(
        organizationsPending: !hadSavedChoices,
        initial: hadSavedChoices
            ? initial
            : initial.copyWith(
                fleetFields: 0,
                roomFields: initial.roomFields & 15,
              ),
        onSave: (choice) async {
          if (!current() || !privacy.canEdit) return false;
          privacy.edit(
            privacy.bindCommunityChoices(
              choice,
              preserveExistingOrganizationChoice: hadSavedChoices,
            ),
          );
          if (privacy.canSave && !await privacy.save(refreshStatus: false)) {
            if (current() && privacy.needsReload) await privacy.refresh();
            return false;
          }
          if (!current()) return false;
          if (choice.publicationEnabled) {
            await privacy.applyPublication();
          } else {
            await privacy.refreshPublication();
          }
          if (!current()) return false;
          // A transport failure can hide the apply response after consent was
          // saved. Check the Host record, never infer a grant from local fields.
          if (privacy.publicationView.firstUseRequired == null) {
            await privacy.refreshPublication();
          }
          return current() && privacy.publicationView.firstUseRequired == false;
        },
      ),
    );
    _route = route;
    try {
      final adjust = await navigator.push(route);
      if (adjust == true && current()) {
        // Opening settings is neither acceptance nor refusal. Do not interrupt
        // that task with another automatic notice during this account session.
        _adjusting = true;
        onAdjust();
      }
    } finally {
      _route = null;
      _dialogEpoch = null;
      _showing = false;
      wake();
    }
  }

  void _dismiss() {
    final route = _route;
    if (route == null) return;
    _route = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    _communities.dispose();
    _retry?.cancel();
    _dismiss();
    queue.cancel(_key);
    account.projection.removeListener(wake);
    privacy.removeListener(_privacyChanged);
  }
}
