import 'dart:async';

import 'package:flutter/foundation.dart';

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
    await _saveOpeningCheckpoint();
    await _checkPendingIdentity();
  }

  bool _restored = false;

  /// A new user's setup must survive any exit, including tray Exit before the
  /// close button saves. Resumable Host progress outranks later device files,
  /// so record the opening checkpoint once. Failure stays silent: the regular
  /// close-time save still reports problems.
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
    _publish(mode: mode);
  }

  bool get canContinue {
    if (_disposed || value.busy || value.completed || value.error) return false;
    if (value.step.index > OnboardingStep.mode.index && !value.modeApplied) {
      return false;
    }
    final f = value.facts;
    return switch (value.step) {
      OnboardingStep.welcome => true,
      OnboardingStep.mode =>
        value.mode != null &&
            (value.mode == OnboardingMode.local || f.signedIn),
      OnboardingStep.log => f.available && f.logReady,
      OnboardingStep.identity =>
        f.hasCandidate &&
            !value.needsFreshEvidence &&
            (value.mode == OnboardingMode.local || value.onlineIdentityReady),
      OnboardingStep.local => value.identityReady && f.localSettingsReady,
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
    await _checkPendingIdentity();
  }

  void back() {
    if (_disposed || value.busy || value.completed) return;
    if (!canGoBack) return;
    final steps = value.steps;
    final index = steps.indexOf(value.step);
    if (index > 0) _publish(step: steps[index - 1]);
  }

  bool get canGoBack =>
      value.step != OnboardingStep.welcome &&
      !(skipWelcomeIntro && value.step == OnboardingStep.mode);

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
    if (action == OnboardingAction.applyMode &&
        (value.step != OnboardingStep.mode || value.mode == null)) {
      return;
    }
    if (action == OnboardingAction.login &&
        (value.step != OnboardingStep.mode ||
            value.mode != OnboardingMode.online)) {
      return;
    }
    if (action == OnboardingAction.selectLog &&
        value.step != OnboardingStep.log) {
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
    final checkpoint = value.checkpoint;
    _activeAction = action;
    await _request(() => _port.execute(action, checkpoint));
    if (_activeAction == action) _activeAction = null;
  }

  Future<void> refresh() => _request(_port.read);

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
          if (step.index > OnboardingStep.mode.index &&
              (checkpoint.sourceKey != f.sourceKey ||
                  checkpoint.evidenceKey != f.evidenceKey)) {
            step = OnboardingStep.log;
          }
        }
      }
      if (skipWelcomeIntro && step == OnboardingStep.welcome) {
        step = OnboardingStep.mode;
      }
      final fresh =
          f.requiresFreshEvidence ||
          source != null && _freshRequiredSources.contains(source);
      var next = OnboardingView(
        step: step,
        mode: mode,
        facts: f,
        needsFreshEvidence: fresh,
      );
      // A saved page is not proof of readiness. Clamp on changed or lost facts.
      if (mode == null && step.index > OnboardingStep.mode.index) {
        step = OnboardingStep.mode;
      } else if (step.index > OnboardingStep.mode.index && !next.modeApplied) {
        step = OnboardingStep.mode;
      } else if (mode == OnboardingMode.local &&
          step == OnboardingStep.online) {
        step = OnboardingStep.local;
      } else if (step.index > OnboardingStep.log.index &&
          (!f.available || !f.logReady)) {
        step = OnboardingStep.log;
      } else if (step.index > OnboardingStep.identity.index &&
          (!next.identityReady ||
              mode == OnboardingMode.online && !next.onlineIdentityReady)) {
        step = OnboardingStep.identity;
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
    } on Object {
      if (!_disposed && operation == _operation) {
        _publish(busy: false, error: true, saved: false);
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
  }) {
    value = OnboardingView(
      step: step ?? value.step,
      mode: mode ?? value.mode,
      facts: value.facts,
      busy: busy ?? value.busy,
      error: error ?? value.error,
      saved: saved ?? false,
      completed: value.completed,
      needsFreshEvidence: value.needsFreshEvidence,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    unawaited(_events.cancel());
    super.dispose();
  }
}
