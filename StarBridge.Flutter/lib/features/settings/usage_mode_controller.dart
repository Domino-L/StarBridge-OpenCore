import 'dart:async';

import 'package:flutter/foundation.dart';

import '../onboarding/onboarding_models.dart';
import '../onboarding/onboarding_port.dart';
import '../onboarding/online_review_controller.dart';
import '../onboarding/online_review_port.dart';
import '../onboarding/online_installation_port.dart';

enum UsageModeStep { login, log, names, installation }

/// Presentation over the existing Host owners. Progress is saved separately
/// from historical setup completion; this controller never calls finish.
class UsageModeController extends ChangeNotifier {
  UsageModeController(
    this.port,
    this.review,
    this.installation, {
    this.onModeChanged,
  });
  final Future<void> Function()? onModeChanged;
  final OnboardingPort port;
  final OnlineReviewController review;
  final OnlineInstallationPort installation;
  OnboardingReply? reply;
  UsageModeStep? step;
  bool busy = false, failed = false, switched = false, _disposed = false;
  int? _installRevision;
  OnlineInstallationSnapshot? installationObservation;
  OnlineInstallationFailure? get failure => installationObservation?.failure;
  bool get recoveryRequired =>
      review.value.snapshot.modeState ==
          OnlineReviewModeState.recoveryRequired ||
      installationObservation?.modeState == 'recoveryRequired';
  Future<void>? _running;

  /// UI disposal does not retire an already submitted Host installation.
  Future<void> get settled => _running ?? Future<void>.value();
  bool get completed => reply?.canUseUsageMode == true;
  bool get online => reply?.facts.activeMode == OnboardingMode.online;
  bool get modeKnown =>
      reply?.facts.available == true &&
      (online ||
          reply?.facts.activeMode == OnboardingMode.local &&
              reply?.facts.publicationSuspended == true);

  /// Online, but the installed account's game identity is not bound (for
  /// example after a sign-in, or a changed log source): the existing review
  /// is shown so the user can confirm it here.
  bool get installedIdentityReview {
    final snapshot = review.value.snapshot;
    return online &&
        snapshot.revision != null &&
        snapshot.modeState == OnlineReviewModeState.online &&
        !snapshot.identityConfirmed;
  }

  bool get usableLog =>
      reply?.facts.hasCandidate == true &&
      reply?.facts.localIdentityConfirmed == true &&
      reply?.facts.requiresFreshEvidence == false &&
      reply?.facts.logSetupPending == false;

  OnboardingCheckpoint _checkpoint(
    OnboardingStep target, [
    OnboardingMode mode = OnboardingMode.online,
  ]) => OnboardingCheckpoint(
    step: target,
    mode: mode,
    sourceKey: reply?.facts.sourceKey,
    evidenceKey: reply?.facts.evidenceKey,
  );

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    failed = false;
    final completion = Completer<void>();
    _running = completion.future;
    notifyListeners();
    try {
      await work();
    } on Object {
      failed = true;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
      _running = null;
      completion.complete();
    }
  }

  Future<void> refresh() => _run(() async {
    reply = await port.read();
    if (!completed) {
      step = null;
      return;
    }
    await review.refresh();
    if (recoveryRequired) {
      step = null;
      final revision = _installRevision ?? review.value.snapshot.revision;
      if (revision != null) {
        installationObservation = await installation.read(revision);
      }
      return;
    }
    if (!modeKnown) throw StateError('Mode unavailable.');
    if (online) {
      step = null;
      await onModeChanged?.call();
      return;
    }
    final progress = reply!.restored;
    step =
        progress?.mode == OnboardingMode.online &&
            reply!.facts.onlineSetupPending
        ? switch (progress?.step) {
            OnboardingStep.log => UsageModeStep.log,
            OnboardingStep.identity => UsageModeStep.names,
            OnboardingStep.online => UsageModeStep.installation,
            _ => UsageModeStep.login,
          }
        : null;
    if (step != null &&
        step != UsageModeStep.installation &&
        !reply!.facts.signedIn) {
      await _save(UsageModeStep.login);
    } else if (step == UsageModeStep.names && !usableLog ||
        step == UsageModeStep.installation && reply!.facts.logSetupPending) {
      // Pending local setup must finish before restoring any later step,
      // including the path that only observes an existing installation.
      await _save(UsageModeStep.log);
    }
    if (step == UsageModeStep.log && usableLog) {
      await _save(UsageModeStep.names);
    }
    if (step == UsageModeStep.names &&
        usableLog &&
        reply!.facts.onlineIdentityMatched &&
        review.value.snapshot.identityConfirmed) {
      await _save(UsageModeStep.installation);
    }
    // Rejoin only the original installation; a read never replays a write.
    if (step == UsageModeStep.installation) {
      _installRevision ??= review.value.snapshot.revision;
      if (_installRevision case final revision?) {
        final observed = installationObservation = await installation.read(
          revision,
        );
        if (observed.phase == OnlineInstallationPhase.completed &&
            observed.modeState == 'online') {
          reply = await port.read();
          switched = online;
          step = null;
          await onModeChanged?.call();
        } else if (observed.phase == OnlineInstallationPhase.idle &&
            (!reply!.facts.signedIn ||
                !usableLog ||
                !review.value.snapshot.identityConfirmed)) {
          await _save(
            !reply!.facts.signedIn
                ? UsageModeStep.login
                : usableLog
                ? UsageModeStep.names
                : UsageModeStep.log,
          );
        }
      }
    }
  });

  Future<void> _save(UsageModeStep next) async {
    reply = await port.read();
    reply = await port.save(
      _checkpoint(switch (next) {
        UsageModeStep.login => OnboardingStep.mode,
        UsageModeStep.log => OnboardingStep.log,
        UsageModeStep.names => OnboardingStep.identity,
        UsageModeStep.installation => OnboardingStep.online,
      }),
    );
    step = next;
  }

  Future<void> begin() => _run(() async {
    reply = await port.read();
    if (!completed || online) return;
    _installRevision = null;
    installationObservation = null;
    reply = await port.execute(
      OnboardingAction.applyMode,
      _checkpoint(OnboardingStep.mode),
    );
    await _save(UsageModeStep.login);
    await review.refresh();
  });

  Future<void> accountConfirmed() => _run(() async {
    reply = await port.read();
    if (!reply!.facts.signedIn) return;
    await _save(usableLog ? UsageModeStep.names : UsageModeStep.log);
  });

  Future<void> logConfirmed() => _run(() async {
    reply = await port.read();
    if (usableLog) {
      await _save(UsageModeStep.names);
    }
  });

  Future<void> namesConfirmed() => _run(() async {
    reply = await port.read();
    if (usableLog &&
        review.value.snapshot.identityConfirmed &&
        reply!.facts.onlineIdentityMatched) {
      await _save(UsageModeStep.installation);
    }
  });

  Future<void> install() => _run(() async {
    reply = await port.read();
    if (!usableLog ||
        !reply!.facts.onlineIdentityMatched ||
        step != UsageModeStep.installation) {
      throw StateError('Identity confirmation required.');
    }
    _installRevision ??= review.value.snapshot.revision;
    final revision = _installRevision;
    if (revision == null) {
      throw StateError('Installation revision unavailable.');
    }
    final observed = await installation.read(revision);
    final result = observed.phase == OnlineInstallationPhase.idle
        ? await installation.install(revision)
        : observed;
    installationObservation = result;
    if (result.phase != OnlineInstallationPhase.completed ||
        result.modeState != 'online') {
      throw StateError('Installation unconfirmed.');
    }
    reply = await port.read();
    if (!online) throw StateError('Mode unconfirmed.');
    step = null;
    switched = true;
    await onModeChanged?.call();
  });

  Future<void> cancel() => _run(() async {
    await review.refresh();
    if (recoveryRequired) {
      if (review.value.snapshot.canCancel || review.canCancelLogin) {
        await review.execute(OnlineReviewAction.cancel);
      }
      // applyMode(local) is the guide's existing explicit recovery action. It
      // drains/retires original owners; no renderer reset or installation replay.
      reply = await port.read();
      reply = await port.execute(
        OnboardingAction.applyMode,
        _checkpoint(OnboardingStep.mode, OnboardingMode.local),
      );
      if (!modeKnown || online || reply!.facts.onlineSetupPending) {
        throw StateError('Recovery unconfirmed.');
      }
      await review.refresh();
      installationObservation = null;
      step = null;
      _installRevision = null;
      switched = false;
      await onModeChanged?.call();
      return;
    }
    if (review.value.snapshot.canCancel || review.canCancelLogin) {
      await review.execute(OnlineReviewAction.cancel);
    }
    reply = await port.read();
    if (reply!.facts.onlineSetupPending) {
      reply = await port.execute(
        OnboardingAction.cancelLogin,
        _checkpoint(OnboardingStep.mode),
      );
    }
    if (reply!.facts.activeMode != OnboardingMode.local ||
        !reply!.facts.publicationSuspended) {
      throw StateError('Cancellation unconfirmed.');
    }
    reply = await port.execute(
      OnboardingAction.applyMode,
      _checkpoint(OnboardingStep.mode, OnboardingMode.local),
    );
    step = null;
    _installRevision = null;
    installationObservation = null;
    await onModeChanged?.call();
  });

  /// After the installed identity review changed, read the mode again so the
  /// main window picks up the bound identity.
  Future<void> installedIdentityChanged() => _run(() async {
    reply = await port.read();
    await review.refresh();
    if (review.value.snapshot.identityConfirmed) await onModeChanged?.call();
  });

  Future<void> enterLocal() => _run(() async {
    reply = await port.read();
    if (!completed || !online) return;
    reply = await port.execute(
      OnboardingAction.applyMode,
      _checkpoint(OnboardingStep.mode, OnboardingMode.local),
    );
    if (online || !reply!.facts.publicationSuspended) {
      throw StateError('Mode unconfirmed.');
    }
    step = null;
    switched = false;
    _installRevision = null;
    installationObservation = null;
    await onModeChanged?.call();
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
