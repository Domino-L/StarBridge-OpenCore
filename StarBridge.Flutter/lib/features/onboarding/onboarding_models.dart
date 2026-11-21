import 'package:flutter/foundation.dart';

enum OnboardingMode { online, local }

enum OnboardingStep {
  welcome,
  log,
  identity,
  mode,
  local,
  online,
  verify,
  summary,
}

enum OnboardingEligibility { firstUse, returning, unknown }

enum OnboardingEvidence {
  unavailable,
  checking,
  candidate,
  missing,
  conflict,
  failed,
}

enum OnboardingEvidenceOrigin { current, history, freshSession, confirmedLocal }

enum OnboardingAction {
  applyMode,
  prepareLog,
  login,
  cancelLogin,
  selectLog,
  locateLogs,
  skipLog,
  refresh,
  confirmHandle,
  finishLogSetup,
  reviewLocalSettings,
  reviewOnlineChoices,
}

@immutable
final class OnboardingLogCandidate {
  const OnboardingLogCandidate(this.path, this.version);
  final String path, version;
}

/// Host observations, not claims inferred from navigation or an SCM profile.
/// Source/evidence keys are opaque revisions: never paths, GEIDs or account IDs.
/// `logCandidates` is the one exception: Host shows the full local paths it
/// found so the user can recognise them; choosing one sends only its index.
@immutable
final class OnboardingFacts {
  const OnboardingFacts({
    this.eligibility = OnboardingEligibility.unknown,
    this.available = false,
    this.canSave = false,
    this.sourceKey,
    this.evidenceKey,
    this.version,
    this.logReady = false,
    this.logCandidates,
    this.logDeferred = false,
    this.logSearchBlocked = false,
    this.evidence = OnboardingEvidence.unavailable,
    this.origin,
    this.handle,
    this.observedAt,
    this.scopeChecked = false,
    this.requiresFreshEvidence = false,
    this.localIdentityConfirmed = false,
    this.logSetupPending = false,
    this.localSettingsReady = false,
    this.signedIn = false,
    this.onlineIdentityMatched = false,
    this.onlineChoicesReviewed = false,
    this.activeMode,
    this.publicationSuspended = false,
    this.onlineSetupPending = false,
  });

  final OnboardingEligibility eligibility;

  /// Null before discovery; empty after a completed search with no safe result.
  final List<OnboardingLogCandidate>? logCandidates;

  /// The last search did not finish because a disk call was still blocked.
  /// It is not "nothing found"; earlier candidates are kept.
  final bool logSearchBlocked;
  final bool available, canSave, logReady, scopeChecked, logDeferred;
  final String? sourceKey, evidenceKey, version, handle;
  final DateTime? observedAt;
  final OnboardingEvidence evidence;
  final OnboardingEvidenceOrigin? origin;
  final bool requiresFreshEvidence, localIdentityConfirmed, localSettingsReady;
  final bool logSetupPending;
  final bool signedIn, onlineIdentityMatched, onlineChoicesReviewed;
  final OnboardingMode? activeMode;
  final bool publicationSuspended;
  final bool onlineSetupPending;

  bool get hasCandidate =>
      available &&
      logReady &&
      sourceKey?.isNotEmpty == true &&
      evidenceKey?.isNotEmpty == true &&
      evidence == OnboardingEvidence.candidate &&
      origin != null &&
      (origin != OnboardingEvidenceOrigin.history || scopeChecked) &&
      observedAt != null &&
      handle?.trim().isNotEmpty == true;
}

/// Only UI progress. No identity authority, consent or domain settings live here.
@immutable
final class OnboardingCheckpoint {
  const OnboardingCheckpoint({
    this.step = OnboardingStep.welcome,
    this.mode,
    this.sourceKey,
    this.evidenceKey,
  });
  final OnboardingStep step;
  final OnboardingMode? mode;
  final String? sourceKey, evidenceKey;

  @override
  bool operator ==(Object other) =>
      other is OnboardingCheckpoint &&
      step == other.step &&
      mode == other.mode &&
      sourceKey == other.sourceKey &&
      evidenceKey == other.evidenceKey;

  @override
  int get hashCode => Object.hash(step, mode, sourceKey, evidenceKey);
}

final class OnboardingReply {
  const OnboardingReply({
    required this.facts,
    this.restored,
    this.saved,
    this.completed,
  });

  /// Presentation policy only; this does not grant online or completion authority.
  bool get canUseUsageMode =>
      completed != null || facts.eligibility == OnboardingEligibility.returning;

  final OnboardingFacts facts;
  final OnboardingCheckpoint? restored, saved, completed;
}

@immutable
final class OnboardingView {
  const OnboardingView({
    this.step = OnboardingStep.welcome,
    this.mode,
    this.facts = const OnboardingFacts(),
    this.busy = false,
    this.error = false,
    this.saved = false,
    this.completed = false,
    this.needsFreshEvidence = false,
    this.errorCode,
  });
  final OnboardingStep step;
  final OnboardingMode? mode;
  final OnboardingFacts facts;
  final bool busy, error, saved, completed, needsFreshEvidence;
  final String? errorCode;
  bool get withoutLog =>
      mode == OnboardingMode.local && facts.logDeferred && !facts.logReady;
  bool get localSetupReady => identityReady || withoutLog;

  bool get identityReady =>
      facts.hasCandidate &&
      facts.localIdentityConfirmed &&
      !needsFreshEvidence &&
      !facts.logSetupPending;

  bool get onlineIdentityReady => facts.signedIn && facts.onlineIdentityMatched;

  bool get modeApplied =>
      mode != null &&
      (mode == OnboardingMode.online && facts.onlineSetupPending
          ? facts.activeMode == OnboardingMode.local &&
                facts.publicationSuspended
          : facts.activeMode == mode &&
                !facts.onlineSetupPending &&
                (mode != OnboardingMode.local || facts.publicationSuspended));

  bool get readyToFinish =>
      facts.available &&
      facts.canSave &&
      modeApplied &&
      localSetupReady &&
      facts.localSettingsReady &&
      mode != null &&
      (mode == OnboardingMode.local ||
          onlineIdentityReady && facts.onlineChoicesReviewed);

  OnboardingCheckpoint get checkpoint => OnboardingCheckpoint(
    step: step,
    mode: mode,
    sourceKey: facts.sourceKey,
    evidenceKey: facts.evidenceKey,
  );

  List<OnboardingStep> get steps => [
    OnboardingStep.welcome,
    OnboardingStep.log,
    if (!withoutLog) OnboardingStep.identity,
    OnboardingStep.mode,
    OnboardingStep.local,
    if (mode == OnboardingMode.online) OnboardingStep.online,
    if (!withoutLog) OnboardingStep.verify,
    OnboardingStep.summary,
  ];
}
