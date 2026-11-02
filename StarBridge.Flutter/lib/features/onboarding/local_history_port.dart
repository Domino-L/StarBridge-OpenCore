import 'package:flutter/foundation.dart';

/// Host-observed state of the one-time history import for the confirmed local
/// profile. Terminal scan results (empty/path/limit/cancelled/...) are reported
/// once; a later read returns the durable state again.
enum LocalHistoryState {
  inactive,
  unavailable,
  needsIdentity,
  recordingRequired,
  available,
  scanning,
  preview,
  imported,
  empty,
  path,
  limit,
  cancelled,
  previewExpired,
  contextChanged,
}

/// Aggregate numbers only: never a path, file name, Handle or profile ID.
@immutable
final class LocalHistorySnapshot {
  const LocalHistorySnapshot({
    this.state = LocalHistoryState.unavailable,
    this.scanId,
    this.phase,
    this.processedFiles = 0,
    this.totalFiles = 0,
    this.previewId,
    this.seconds,
    this.sessions = 0,
    this.incompleteSessions = 0,
    this.skippedFiles = 0,
    this.importedSeconds,
    this.importedAt,
  });
  final LocalHistoryState state;
  final String? scanId, phase, previewId;
  final int processedFiles, totalFiles, sessions, incompleteSessions;
  final int skippedFiles;
  final int? seconds, importedSeconds;
  final DateTime? importedAt;
}

/// Reset preview / result for the confirmed local profile's play time.
@immutable
final class LocalResetSnapshot {
  const LocalResetSnapshot(
    this.state, {
    this.resetId,
    this.seconds,
    this.historicalSeconds,
  });

  /// ready, empty, reset, previewExpired, contextChanged, unavailable, inactive...
  final String state;
  final String? resetId;
  final int? seconds, historicalSeconds;
}

/// Nothing here imports automatically. A scan only previews; confirm is the
/// single explicit write and the Host never adds an existing import again.
abstract interface class LocalHistoryPort {
  Stream<void> get invalidations;
  Future<LocalHistorySnapshot> read();
  Future<LocalHistorySnapshot> startScan();
  Future<LocalHistorySnapshot> readScan(String scanId);
  Future<LocalHistorySnapshot> cancelScan(String scanId);
  Future<LocalHistorySnapshot> confirm(String previewId);

  /// Explicit reset (WPF parity): preview writes nothing; confirm clears live
  /// and imported time, restores one import and keeps consent.
  bool get resetSupported;
  Future<LocalResetSnapshot> previewReset();
  Future<LocalResetSnapshot> confirmReset(String resetId);
}
