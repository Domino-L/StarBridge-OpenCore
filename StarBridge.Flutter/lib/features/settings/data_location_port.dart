/// Device-owned location, fetched only when its settings detail is opened.
final class DataLocation {
  const DataLocation({required this.path, required this.exists});
  final String path;
  final bool exists;
}

abstract interface class DataLocationPort {
  Future<DataLocation> read();
  Future<void> open();
}

final class DataLocationMigrationChoice {
  const DataLocationMigrationChoice({
    required this.ticket,
    required this.source,
    required this.destination,
  });
  final String ticket;
  final String source;
  final String destination;
}

abstract interface class DataLocationMigrationPort implements DataLocationPort {
  bool get migrationAvailable;
  Future<DataLocationMigrationChoice?> chooseMigration();
  Future<void> confirmMigration(String ticket);
}

final class UnavailableDataLocation implements DataLocationPort {
  const UnavailableDataLocation();

  @override
  Future<DataLocation> read() => Future.error(StateError('unavailable'));

  @override
  Future<void> open() => Future.error(StateError('unavailable'));
}
