enum OnlineInstallationPhase { idle, running, completed }

// Original physical task observations, not account authority or guide completion.
final class OnlineInstallationSnapshot {
  const OnlineInstallationSnapshot({
    required this.revision,
    required this.phase,
    required this.controlGeneration,
    required this.modeRevision,
    required this.modeState,
    this.failure,
  });
  final int revision, controlGeneration, modeRevision;
  final OnlineInstallationPhase phase;
  final String modeState;
  final OnlineInstallationFailure? failure;
  bool get online =>
      phase == OnlineInstallationPhase.completed && modeState == 'online';
}

/// Finite diagnostic facts, never authentication or installation authority.
final class OnlineInstallationFailure {
  const OnlineInstallationFailure(this.stage, this.kind);
  final String stage, kind;
  String get code => '$stage/$kind';
}

abstract interface class OnlineInstallationPort {
  bool get supported;
  Future<OnlineInstallationSnapshot> read(int revision);
  Future<OnlineInstallationSnapshot> install(int revision);
}
