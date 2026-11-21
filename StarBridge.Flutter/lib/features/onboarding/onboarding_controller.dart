import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';

import 'onboarding_models.dart';
import 'onboarding_port.dart';

/// One state owner for the linear UI. Completion always requires a Host receipt.
final class OnboardingController extends ValueNotifier<OnboardingView> {
  OnboardingController(this._port, {this.skipWelcomeIntro = false})
    : super(const OnboardingView()) {
    _events = _port.invalidations.listen((_) {
      if (_disposed || !_initialized || value.completed) return;
      if (value.busy) {
        _refreshPending = true;
      } else {
        unawaited(refresh());
      }
    });
  }

  final OnboardingPort _port;

  /// Only skips the obsolete feature introduction, never grants legal consent.
  final bool skipWelcomeIntro;
  late final StreamSubscription<void> _events;
  bool _refreshPending = false;
  bool _logSearchAttempted = false;
  final _openingReady = Completer<void>();
  final Set<String> _freshRequiredSources = {};
  bool _disposed = false, _initialized = false;
  int _operation = 0;
  OnboardingAction? _activeAction;

  bool get canCancelLogin =>
      !_disposed && value.busy && _activeAction == OnboardingAction.login;

  bool get canConfirmLocalIdentity =>
      !_disposed &&
      !value.busy &&
      !value.error &&
      value.step == OnboardingStep.identity &&
      value.modeApplied &&
      value.facts.hasCandidate &&
      !value.needsFreshEvidence &&
      !value.facts.localIdentityConfirmed;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    await _request(_port.read, restore: true);
    await _prepareLogStep();
    await _saveOpeningCheckpoint();
    await _checkPendingIdentity();
    if (!_openingReady.isCompleted) _openingReady.complete();
  }

  bool _restored = false;

  /// A new user's setup must survive any exit, including tray Exit before the
  /// close button saves. Resumable Host progress outranks later device files,
  /// so record the opening checkpoint once, including identity/mode recovered
  /// from domain facts after Host cleared stale UI progress. Failure stays
  /// silent: the regular close-time save still reports problems.
  Future<void> _saveOpeningCheckpoint() async {
    final view = value;
    if (_disposed ||
        _restored ||
        view.busy ||
        view.completed ||
        !view.facts.available ||
        !view.facts.canSave ||
        view.facts.eligibility != OnboardingEligibility.firstUse ||
        view.step.index > OnboardingStep.mode.index) {
      return;
    }
    try {
      await _port.save(view.checkpoint);
      _restored = true;
    } on Object {
      // Unknown result: the close-time save remains the visible confirmation.
    }
  }

  void chooseMode(OnboardingMode mode) {
    if (_disposed || value.busy || value.step != OnboardingStep.mode) return;
    if (mode == OnboardingMode.online && !value.identityReady) return;
    _publish(mode: mode);
  }

  // Reuse the original retirement handshake before the first file/identity
  // action. The durable mode is local; no new checkpoint/storage shape exists.
  // Opening or continuing setup only pauses a plain local session or prepares
  // a device that has no account yet (Host checks that and switches nothing
  // else). An online account or a pending online choice is never switched
  // without the user's own action.
  Future<void> _prepareLogStep({bool explicit = false}) async {
    if (_disposed || value.step != OnboardingStep.log) return;
    final f = value.facts;
    if (f.activeMode == OnboardingMode.local &&
        f.publicationSuspended &&
        !f.onlineSetupPending) {
      return;
    }
    if (f.onlineSetupPending && !explicit) {
      _publish(mode: OnboardingMode.online);
      return;
    }
    if (f.activeMode == OnboardingMode.online && !explicit) {
      _publish(mode: OnboardingMode.local);
      await run(OnboardingAction.prepareLog);
      if (_disposed) return;
      // Still online: a real account stays as it is.
      if (!value.modeApplied) _publish(mode: OnboardingMode.online);
      return;
    }
    _publish(mode: OnboardingMode.local);
    await run(OnboardingAction.applyMode);
    if (!value.modeApplied) _publish(error: true);
  }

  /// Online without an account installed here cannot pick a log. Only the
  /// user's own click switches to local mode for it.
  bool get canUseLocalForLog =>
      !_disposed &&
      !value.busy &&
      value.step == OnboardingStep.log &&
      value.facts.available &&
      value.facts.activeMode == OnboardingMode.online &&
      !value.facts.onlineSetupPending &&
      !value.facts.signedIn;

  Future<void> useLocalForLog() async {
    if (!canUseLocalForLog) return;
    _publish(error: false);
    await _prepareLogStep(explicit: true);
    if (_disposed || value.error || !value.modeApplied) return;
    _logSearchAttempted = true;
    await run(OnboardingAction.locateLogs);
  }

  bool get canContinue {
    if (_disposed || value.busy || value.completed || value.error) return false;
    if (value.step != OnboardingStep.welcome &&
        value.step != OnboardingStep.mode &&
        !value.modeApplied) {
      return false;
    }
    final f = value.facts;
    return switch (value.step) {
      OnboardingStep.welcome => true,
      OnboardingStep.mode =>
        value.mode != null &&
            value.localSetupReady &&
            (value.mode == OnboardingMode.local ||
                value.identityReady && value.onlineIdentityReady),
      OnboardingStep.log => f.available && (f.logReady || value.withoutLog),
      OnboardingStep.identity =>
        f.hasCandidate && !value.needsFreshEvidence && !f.logSetupPending,
      OnboardingStep.local => value.localSetupReady && f.localSettingsReady,
      OnboardingStep.online =>
        value.identityReady &&
            value.onlineIdentityReady &&
            f.onlineChoicesReviewed,
      // Optional check: continuing without a pass is an honest skip.
      OnboardingStep.verify =>
        value.identityReady &&
            f.localSettingsReady &&
            (value.mode == OnboardingMode.local || f.onlineChoicesReviewed),
      OnboardingStep.summary => value.readyToFinish,
    };
  }

  Future<void> next() async {
    if (!canContinue) return;
    if (value.step == OnboardingStep.mode && !value.modeApplied) {
      final requestedMode = value.mode;
      await run(OnboardingAction.applyMode);
      if (_disposed) return;
      if (value.step != OnboardingStep.mode || value.mode != requestedMode) {
        return;
      }
      if (!value.modeApplied) {
        _publish(error: true);
        return;
      }
      if (!canContinue) return;
    }
    if (value.step == OnboardingStep.summary) {
      final checkpoint = value.checkpoint;
      await _request(() => _port.finish(checkpoint), finish: checkpoint);
      return;
    }
    if (value.step == OnboardingStep.identity &&
        !value.facts.localIdentityConfirmed) {
      final checkpoint = value.checkpoint;
      await run(OnboardingAction.confirmHandle);
      if (_disposed) return;
      if (value.checkpoint != checkpoint) return;
      if (!canContinue || !value.identityReady) return;
    }
    final steps = value.steps;
    _publish(step: steps[steps.indexOf(value.step) + 1]);
    await _prepareLogStep();
    await _checkPendingIdentity();
  }

  void back() {
    if (_disposed || value.busy || value.completed) return;
    if (!canGoBack) return;
    final steps = value.steps;
    final index = steps.indexOf(value.step);
    if (index > 0) _publish(step: steps[index - 1]);
  }

  void returnToMode() {
    if (!_disposed && !value.busy && !value.completed) {
      _publish(step: OnboardingStep.mode);
    }
  }

  bool get canGoBack =>
      value.step != OnboardingStep.welcome &&
      !(skipWelcomeIntro && value.step == OnboardingStep.log);

  Future<void> run(OnboardingAction action) async {
    if (action == OnboardingAction.cancelLogin && canCancelLogin) {
      _operation++;
      _activeAction = OnboardingAction.cancelLogin;
      _publish(busy: false);
      final checkpoint = value.checkpoint;
      await _request(() => _port.execute(action, checkpoint));
      _activeAction = null;
      return;
    }
    if (_disposed || value.busy || value.completed) return;
    if (!value.facts.available) return;
    // Returning from online review to the log step must still let the user
    // explicitly defer the log. Retire the pending candidate through the same
    // local handshake before asking Host to save a no-log choice.
    if (action == OnboardingAction.skipLog &&
        value.step == OnboardingStep.log &&
        (value.mode != OnboardingMode.local || !value.modeApplied)) {
      if (value.facts.activeMode == OnboardingMode.online) return;
      _publish(mode: OnboardingMode.local, error: false);
      await _prepareLogStep(explicit: true);
      if (_disposed || value.busy || value.error || !value.modeApplied) return;
    }
    if (action == OnboardingAction.applyMode &&
        (value.mode == null ||
            value.step != OnboardingStep.mode &&
                !(value.step == OnboardingStep.log &&
                    value.mode == OnboardingMode.local) ||
            value.mode == OnboardingMode.online && !value.identityReady)) {
      return;
    }
    if (action == OnboardingAction.login &&
        (value.step != OnboardingStep.mode ||
            value.mode != OnboardingMode.online ||
            !value.identityReady)) {
      return;
    }
    if ((action == OnboardingAction.selectLog ||
            action == OnboardingAction.locateLogs ||
            action == OnboardingAction.prepareLog) &&
        value.step != OnboardingStep.log) {
      return;
    }
    if (action == OnboardingAction.skipLog &&
        (value.step != OnboardingStep.log ||
            value.mode != OnboardingMode.local ||
            !value.modeApplied)) {
      return;
    }
    if (action == OnboardingAction.reviewLocalSettings &&
        value.step != OnboardingStep.local) {
      return;
    }
    if (action == OnboardingAction.reviewOnlineChoices &&
        value.step != OnboardingStep.online) {
      return;
    }
    if (action == OnboardingAction.confirmHandle &&
        (value.step != OnboardingStep.identity ||
            !value.modeApplied ||
            !value.facts.hasCandidate ||
            value.needsFreshEvidence)) {
      return;
    }
    if (action == OnboardingAction.finishLogSetup &&
        (value.step != OnboardingStep.identity ||
            !value.modeApplied ||
            !value.facts.localIdentityConfirmed ||
            !value.facts.logSetupPending ||
            value.needsFreshEvidence)) {
      return;
    }
    final checkpoint = value.checkpoint;
    _activeAction = action;
    await _request(() => _port.execute(action, checkpoint));
    if (value.error &&
        (action == OnboardingAction.confirmHandle ||
            action == OnboardingAction.finishLogSetup)) {
      await refresh();
    }
    if (_activeAction == action) _activeAction = null;
  }

  Future<void> refresh() => _request(_port.read);

  Future<void> searchLogsOnEntry() async {
    if (!_initialized || _disposed) return;
    // Opening progress and discovery share the Host state-key lane.
    await _openingReady.future;
    if (_logSearchAttempted ||
        _disposed ||
        value.busy ||
        value.step != OnboardingStep.log ||
        !value.facts.available ||
        value.facts.activeMode != OnboardingMode.local ||
        !value.facts.publicationSuspended) {
      return;
    }
    _logSearchAttempted = true;
    await run(OnboardingAction.locateLogs);
  }

  Future<void> selectLogCandidate(int index) async {
    if (_disposed ||
        value.busy ||
        value.completed ||
        value.step != OnboardingStep.log ||
        value.facts.activeMode != OnboardingMode.local ||
        index < 0 ||
        index >= (value.facts.logCandidates?.length ?? 0) ||
        _port is! OnboardingLogCandidatePort) {
      return;
    }
    final checkpoint = value.checkpoint;
    await _request(
      () => (_port as OnboardingLogCandidatePort).selectLogCandidate(
        index,
        checkpoint,
      ),
    );
  }

  Future<void> retryLogSetup() async {
    await refresh();
    await _prepareLogStep();
    if (!value.busy &&
        !value.error &&
        value.step == OnboardingStep.log &&
        value.facts.activeMode == OnboardingMode.local) {
      _logSearchAttempted = true;
      await run(OnboardingAction.locateLogs);
    }
  }

  Future<void> _checkPendingIdentity() async {
    if (!_disposed &&
        value.step == OnboardingStep.identity &&
        value.facts.evidence == OnboardingEvidence.checking) {
      await checkEvidence();
    }
  }

  /// Entering identity or explicitly retrying requests a bounded Native scan.
  /// Passive invalidation reads stay side-effect-free. Renew the observation
  /// first because Native evidence keys expire while a page remains open.
  Future<void> checkEvidence() async {
    if (_disposed ||
        value.busy ||
        value.completed ||
        value.step != OnboardingStep.identity ||
        !value.modeApplied) {
      return;
    }
    final source = value.facts.sourceKey;
    final mode = value.mode;
    if (source == null) return;
    await _request(() async {
      final observed = await _port.read();
      if (_disposed) return observed;
      final fresh = OnboardingView(
        step: OnboardingStep.identity,
        mode: mode,
        facts: observed.facts,
      );
      if (!fresh.modeApplied ||
          !fresh.facts.available ||
          !fresh.facts.logReady ||
          fresh.facts.sourceKey != source) {
        return observed;
      }
      return _port.execute(OnboardingAction.refresh, fresh.checkpoint);
    });
  }

  Future<bool> save() async {
    if (_disposed || value.busy || !value.facts.canSave) return false;
    final checkpoint = value.checkpoint;
    await _request(() => _port.save(checkpoint), save: checkpoint);
    return !_disposed && value.saved && value.checkpoint == checkpoint;
  }

  Future<void> _request(
    Future<OnboardingReply> Function() request, {
    bool restore = false,
    OnboardingCheckpoint? save,
    OnboardingCheckpoint? finish,
  }) async {
    if (_disposed || value.busy || value.completed) return;
    final operation = ++_operation;
    _publish(busy: true, error: false);
    try {
      final reply = await request();
      if (_disposed || operation != _operation) return;
      final f = reply.facts;
      final source = f.sourceKey;
      if (source != null) {
        if (f.requiresFreshEvidence ||
            f.scopeChecked && f.evidence == OnboardingEvidence.missing) {
          _freshRequiredSources.add(source);
        }
        // Only a real, fresh, source-scoped identity observation clears the gate.
        if (f.hasCandidate &&
            f.origin == OnboardingEvidenceOrigin.freshSession &&
            !f.requiresFreshEvidence) {
          _freshRequiredSources.remove(source);
        }
      }
      var step = value.step;
      var mode = value.mode;
      if (restore) {
        if (reply.restored case final checkpoint?) {
          _restored = true;
          step = checkpoint.step;
          mode = checkpoint.mode;
          if (checkpoint.sourceKey != null &&
              step != OnboardingStep.mode &&
              (checkpoint.sourceKey != f.sourceKey ||
                  checkpoint.evidenceKey != f.evidenceKey)) {
            step = OnboardingStep.log;
          }
        }
      }
      if (skipWelcomeIntro && step == OnboardingStep.welcome) {
        step = OnboardingStep.log;
      }
      // log/identity checkpoints retain the old non-null mode contract.
      // This implicit local bootstrap is not an online selection.
      if (mode == null && step.index <= OnboardingStep.identity.index) {
        mode = OnboardingMode.local;
      }
      final fresh =
          f.requiresFreshEvidence ||
          source != null && _freshRequiredSources.contains(source);
      // Selecting a new source or confirming a new identity clears stale UI
      // progress on Host. Recover from real domain state even after tray Exit.
      if (restore &&
          reply.restored == null &&
          skipWelcomeIntro &&
          f.available &&
          f.eligibility == OnboardingEligibility.firstUse) {
        final recovered = OnboardingView(
          mode: mode,
          facts: f,
          needsFreshEvidence: fresh,
        );
        if (recovered.modeApplied) {
          if (recovered.localSetupReady) {
            step = OnboardingStep.mode;
          } else if (f.logReady) {
            step = OnboardingStep.identity;
          }
        }
      }
      var next = OnboardingView(
        step: step,
        mode: mode,
        facts: f,
        needsFreshEvidence: fresh,
      );
      // A saved page is not proof of readiness. Clamp on changed or lost facts.
      if (step.index > OnboardingStep.log.index &&
          (!f.available || !f.logReady && !next.withoutLog)) {
        step = OnboardingStep.log;
        mode = OnboardingMode.local;
      } else if (step.index > OnboardingStep.identity.index &&
          !next.localSetupReady) {
        step = OnboardingStep.identity;
        mode = OnboardingMode.local;
      } else if (step.index > OnboardingStep.mode.index &&
          (mode == null ||
              !next.modeApplied ||
              mode == OnboardingMode.online && !next.onlineIdentityReady)) {
        step = OnboardingStep.mode;
      } else if (mode == OnboardingMode.local &&
          step == OnboardingStep.online) {
        step = OnboardingStep.local;
      } else if (step.index > OnboardingStep.local.index &&
          !f.localSettingsReady) {
        step = OnboardingStep.local;
      } else if ((step == OnboardingStep.summary ||
              step == OnboardingStep.verify) &&
          mode == OnboardingMode.online &&
          !f.onlineChoicesReviewed) {
        step = OnboardingStep.online;
      }
      next = OnboardingView(
        step: step,
        mode: mode,
        facts: f,
        needsFreshEvidence: fresh,
      );
      final saved =
          save != null && reply.saved == save && next.checkpoint == save;
      final completed =
          finish != null &&
          reply.completed == finish &&
          next.checkpoint == finish &&
          next.readyToFinish &&
          (mode != OnboardingMode.online ||
              f.activeMode == OnboardingMode.online && !f.onlineSetupPending);
      value = OnboardingView(
        step: step,
        mode: mode,
        facts: f,
        needsFreshEvidence: fresh,
        saved: saved,
        completed: completed,
        error: save != null && !saved || finish != null && !completed,
      );
    } on Object catch (error) {
      if (!_disposed && operation == _operation) {
        _publish(
          busy: false,
          error: true,
          saved: false,
          errorCode: error is BridgeClientException ? error.code : null,
        );
      }
    } finally {
      if (!_disposed && operation == _operation && _refreshPending) {
        _refreshPending = false;
        // A saved/completed reply already includes its committed observation;
        // do not replace that receipt before the caller can consume it.
        if (save == null && finish == null) unawaited(refresh());
      }
    }
  }

  void _publish({
    OnboardingStep? step,
    OnboardingMode? mode,
    bool? busy,
    bool? error,
    bool? saved,
    String? errorCode,
  }) {
    if (step != null && step != OnboardingStep.log) {
      _logSearchAttempted = false;
    }
    value = OnboardingView(
      step: step ?? value.step,
      mode: mode ?? value.mode,
      facts: value.facts,
      busy: busy ?? value.busy,
      error: error ?? value.error,
      saved: saved ?? false,
      completed: value.completed,
      needsFreshEvidence: value.needsFreshEvidence,
      errorCode: errorCode,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_openingReady.isCompleted) _openingReady.complete();
    _operation++;
    unawaited(_events.cancel());
    super.dispose();
  }
}
