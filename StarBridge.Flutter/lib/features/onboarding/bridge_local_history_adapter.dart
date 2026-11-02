import '../../platform/bridge/bridge_client_session.dart';
import 'local_history_port.dart';

final class BridgeLocalHistoryAdapter implements LocalHistoryPort {
  BridgeLocalHistoryAdapter(this.session);
  static const capability = 'onboarding.localStatistics.history.v1';
  static const resetCapability = 'onboarding.localStatistics.reset.v1';
  final BridgeClientSession session;
  int _epoch = 0;

  bool get supported => session.hostCapabilities.contains(capability);

  @override
  Stream<void> get invalidations => session.events
      .where(
        (event) => const {
          'account.changed',
          'bootstrap.invalidated',
          'onboarding.changed',
          'gameLog.changed',
          'onboarding.localStatistics.changed',
        }.contains(event.name),
      )
      .map((_) {
        _epoch++;
      });

  @override
  Future<LocalHistorySnapshot> read() =>
      _request('onboarding.localStatistics.historyRead', const {});
  @override
  Future<LocalHistorySnapshot> startScan() =>
      _request('onboarding.localStatistics.historyScanStart', const {});
  @override
  Future<LocalHistorySnapshot> readScan(String scanId) => _request(
    'onboarding.localStatistics.historyScanRead',
    {'scanId': _id(scanId)},
  );
  @override
  Future<LocalHistorySnapshot> cancelScan(String scanId) => _request(
    'onboarding.localStatistics.historyScanCancel',
    {'scanId': _id(scanId)},
  );
  @override
  Future<LocalHistorySnapshot> confirm(String previewId) => _request(
    'onboarding.localStatistics.historyConfirm',
    {'previewId': _id(previewId)},
  );

  @override
  bool get resetSupported =>
      supported && session.hostCapabilities.contains(resetCapability);

  @override
  Future<LocalResetSnapshot> previewReset() =>
      _reset('onboarding.localStatistics.resetPreview', const {});
  @override
  Future<LocalResetSnapshot> confirmReset(String resetId) => _reset(
    'onboarding.localStatistics.resetConfirm',
    {'resetId': _id(resetId)},
  );

  Future<LocalResetSnapshot> _reset(
    String name,
    Map<String, Object?> payload,
  ) async {
    if (!resetSupported) return const LocalResetSnapshot('inactive');
    final epoch = _epoch;
    final generation = session.activeGeneration;
    final response = await session.request(
      name,
      payload: {'schemaVersion': 1, ...payload},
      timeout: const Duration(seconds: 30),
    );
    final raw = response.payload;
    if (epoch != _epoch ||
        generation != session.activeGeneration ||
        response.sessionGeneration != generation ||
        response.status != 'ok' ||
        response.error != null ||
        raw.length != 5 ||
        raw['schemaVersion'] != 1 ||
        raw['state'] is! String) {
      throw StateError('Local reset state is not current.');
    }
    final id = raw['resetId'], seconds = raw['seconds'];
    final history = raw['historicalSeconds'];
    final ready = raw['state'] == 'ready';
    if (ready != (id is String && LocalHistoryWire.id.hasMatch(id)) ||
        seconds != null && (seconds is! int || seconds < 0) ||
        history != null && (history is! int || history < 0)) {
      throw const FormatException('Invalid local reset projection.');
    }
    return LocalResetSnapshot(
      raw['state']! as String,
      resetId: id as String?,
      seconds: seconds as int?,
      historicalSeconds: history as int?,
    );
  }

  static String _id(String value) => LocalHistoryWire.id.hasMatch(value)
      ? value
      : throw ArgumentError.value(value, 'id');

  Future<LocalHistorySnapshot> _request(
    String name,
    Map<String, Object?> payload,
  ) async {
    if (!supported) {
      return const LocalHistorySnapshot(state: LocalHistoryState.inactive);
    }
    final epoch = _epoch;
    final generation = session.activeGeneration;
    final response = await session.request(
      name,
      payload: {'schemaVersion': 1, ...payload},
      timeout: const Duration(seconds: 30),
    );
    if (epoch != _epoch ||
        generation != session.activeGeneration ||
        response.sessionGeneration != generation ||
        !supported ||
        response.status != 'ok' ||
        response.error != null) {
      throw StateError('Local history import state is not current.');
    }
    return LocalHistoryWire.parse(response.payload);
  }
}

abstract final class LocalHistoryWire {
  static final id = RegExp(r'^[0-9a-f]{32}$');
  static const _fields = {
    'schemaVersion',
    'state',
    'scanId',
    'phase',
    'processedFiles',
    'totalFiles',
    'readBytes',
    'totalBytes',
    'previewId',
    'seconds',
    'sessions',
    'incompleteSessions',
    'skippedFiles',
    'importedSeconds',
    'importedAt',
  };

  static LocalHistorySnapshot parse(Map<String, Object?> raw) {
    if (raw.length != _fields.length ||
        raw.keys.toSet().difference(_fields).isNotEmpty ||
        raw['schemaVersion'] != 1) {
      _bad();
    }
    final state = LocalHistoryState.values
        .where((s) => s.name == raw['state'])
        .singleOrNull;
    int count(String key) => switch (raw[key]) {
      final int value when value >= 0 => value,
      _ => _bad(),
    };
    int? optional(String key) => switch (raw[key]) {
      null => null,
      final int value when value >= 0 => value,
      _ => _bad(),
    };
    String? token(String key) => switch (raw[key]) {
      null => null,
      final String value when id.hasMatch(value) => value,
      _ => _bad(),
    };
    final importedAtRaw = raw['importedAt'];
    final importedAt = importedAtRaw == null
        ? null
        : importedAtRaw is String
        ? DateTime.tryParse(importedAtRaw) ?? _bad()
        : _bad();
    final phase = raw['phase'];
    if (state == null || phase != null && phase is! String) _bad();
    final snapshot = LocalHistorySnapshot(
      state: state,
      scanId: token('scanId'),
      phase: phase as String?,
      processedFiles: count('processedFiles'),
      totalFiles: count('totalFiles'),
      previewId: token('previewId'),
      seconds: optional('seconds'),
      sessions: count('sessions'),
      incompleteSessions: count('incompleteSessions'),
      skippedFiles: count('skippedFiles'),
      importedSeconds: optional('importedSeconds'),
      importedAt: importedAt,
    );
    count('readBytes');
    count('totalBytes');
    // Each state carries exactly its own facts; anything else is rejected.
    final scanning = state == LocalHistoryState.scanning;
    final preview = state == LocalHistoryState.preview;
    final imported = state == LocalHistoryState.imported;
    if (scanning != (snapshot.scanId != null) ||
        scanning != (phase != null) ||
        preview != (snapshot.previewId != null) ||
        preview != (snapshot.seconds != null) ||
        imported != (snapshot.importedSeconds != null) ||
        imported != (importedAt != null) ||
        snapshot.processedFiles > snapshot.totalFiles) {
      _bad();
    }
    return snapshot;
  }

  static Never _bad() =>
      throw const FormatException('Invalid local history projection.');
}
