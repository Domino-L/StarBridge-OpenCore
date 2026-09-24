enum GameplayExportOutcome {
  saved,
  cancelled,
  unavailable,
  accountChanged,
  dataUnavailable,
  fileExists,
  invalidDestination,
  busy,
  failed,
  unknown,
}

abstract interface class GameplayDataExportPort {
  Future<GameplayExportOutcome> export(String locale);
  void cancel();
}

final class UnavailableGameplayDataExport implements GameplayDataExportPort {
  const UnavailableGameplayDataExport();
  @override
  Future<GameplayExportOutcome> export(String locale) async =>
      GameplayExportOutcome.unavailable;
  @override
  void cancel() {}
}
