import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_port.dart';

// Synthetic, non-personal fixtures. Never used by product composition.
OnboardingFacts facts({
  OnboardingEligibility eligibility = OnboardingEligibility.firstUse,
  bool available = true,
  bool canSave = true,
  bool logReady = true,
  String source = 'fixture-live-1',
  String? evidenceKey = 'fixture-evidence-1',
  OnboardingEvidence evidence = OnboardingEvidence.candidate,
  OnboardingEvidenceOrigin origin = OnboardingEvidenceOrigin.current,
  bool scopeChecked = true,
  bool requiresFresh = false,
  bool confirmed = false,
  bool localReady = true,
  bool signedIn = true,
  bool matched = true,
  bool onlineReviewed = true,
  OnboardingMode? activeMode = OnboardingMode.local,
  bool publicationSuspended = true,
  bool onlineSetupPending = false,
}) => OnboardingFacts(
  eligibility: eligibility,
  available: available,
  canSave: canSave,
  logReady: logReady,
  sourceKey: source,
  evidenceKey: evidenceKey,
  version: source.contains('ptu') ? 'PTU' : 'LIVE',
  evidence: evidence,
  origin: origin,
  handle: evidence == OnboardingEvidence.candidate ? 'Pilot-Example' : null,
  observedAt: DateTime.utc(2026, 1, 1, 12),
  scopeChecked: scopeChecked,
  requiresFreshEvidence: requiresFresh,
  localIdentityConfirmed: confirmed,
  localSettingsReady: localReady,
  signedIn: signedIn,
  onlineIdentityMatched: matched,
  onlineChoicesReviewed: onlineReviewed,
  activeMode: activeMode,
  publicationSuspended: publicationSuspended,
  onlineSetupPending: onlineSetupPending,
);

class FakeOnboardingPort implements OnboardingPort {
  FakeOnboardingPort(this.facts);
  OnboardingFacts facts;
  Stream<void> events = const Stream.empty();
  @override
  Stream<void> get invalidations => events;
  OnboardingCheckpoint? restored;
  bool saveReceipt = true, finishReceipt = true, readThrows = false;
  int reads = 0, saves = 0, finishes = 0;
  final actions = <OnboardingAction>[];
  Future<OnboardingReply> Function(OnboardingAction, OnboardingCheckpoint)?
  onAction;
  OnboardingCheckpoint Function(OnboardingCheckpoint)? alterReceipt;

  @override
  Future<OnboardingReply> read() async {
    reads++;
    if (readThrows) throw StateError('synthetic read failure');
    return OnboardingReply(facts: facts, restored: restored);
  }

  @override
  Future<OnboardingReply> execute(
    OnboardingAction action,
    OnboardingCheckpoint checkpoint,
  ) async {
    actions.add(action);
    if (action == OnboardingAction.applyMode && onAction == null) {
      final f = facts;
      facts = OnboardingFacts(
        eligibility: f.eligibility,
        available: f.available,
        canSave: f.canSave,
        sourceKey: f.sourceKey,
        evidenceKey: f.evidenceKey,
        version: f.version,
        logReady: f.logReady,
        evidence: f.evidence,
        origin: f.origin,
        handle: f.handle,
        observedAt: f.observedAt,
        scopeChecked: f.scopeChecked,
        requiresFreshEvidence: f.requiresFreshEvidence,
        localIdentityConfirmed: f.localIdentityConfirmed,
        localSettingsReady: f.localSettingsReady,
        signedIn: f.signedIn,
        onlineIdentityMatched: f.onlineIdentityMatched,
        onlineChoicesReviewed: f.onlineChoicesReviewed,
        activeMode: checkpoint.mode,
        publicationSuspended: checkpoint.mode == OnboardingMode.local,
        onlineSetupPending: f.onlineSetupPending,
      );
    }
    return onAction?.call(action, checkpoint) ?? OnboardingReply(facts: facts);
  }

  @override
  Future<OnboardingReply> save(OnboardingCheckpoint checkpoint) async {
    saves++;
    return OnboardingReply(
      facts: facts,
      saved: saveReceipt ? alterReceipt?.call(checkpoint) ?? checkpoint : null,
    );
  }

  @override
  Future<OnboardingReply> finish(OnboardingCheckpoint checkpoint) async {
    finishes++;
    return OnboardingReply(
      facts: facts,
      completed: finishReceipt
          ? alterReceipt?.call(checkpoint) ?? checkpoint
          : null,
    );
  }
}
