import 'dart:async';

import 'package:flutter/foundation.dart';

import 'catalog_port.dart';
import 'mission_records_port.dart';

final class MissionRecordGroup {
  MissionRecordGroup(CatalogRow row)
    : key = row['key'] as String,
      definitionId = row['definitionId'] as String?,
      contractCode = row['contractCode'] as String?,
      count = (row['count'] as num).toInt(),
      fastestSeconds = (row['fastestSeconds'] as num?)?.toDouble(),
      soloFastestSeconds = (row['soloFastestSeconds'] as num?)?.toDouble(),
      teamFastestSeconds = (row['teamFastestSeconds'] as num?)?.toDouble(),
      joinedFullFastestSeconds = (row['joinedFullFastestSeconds'] as num?)
          ?.toDouble(),
      joinedPartialFastestSeconds = (row['joinedPartialFastestSeconds'] as num?)
          ?.toDouble(),
      lastCompletedAt = DateTime.parse(row['lastCompletedAt'] as String);
  final String key;
  final String? definitionId, contractCode;
  final int count;

  /// Best of the contracts you took yourself (solo or team).
  /// Seconds keep the summary's precision; only display rounds them.
  final double? fastestSeconds;
  final double? soloFastestSeconds, teamFastestSeconds;
  final double? joinedFullFastestSeconds, joinedPartialFastestSeconds;
  final DateTime lastCompletedAt;

  /// Whether the summary splits times by role (newer hosts).
  bool get hasRoles =>
      soloFastestSeconds != null ||
      teamFastestSeconds != null ||
      joinedFullFastestSeconds != null ||
      joinedPartialFastestSeconds != null;

  /// Fastest joined contract and whether it was joined from the start.
  ({double seconds, bool full})? get joinedFastest {
    final full = joinedFullFastestSeconds,
        partial = joinedPartialFastestSeconds;
    if (full == null && partial == null) return null;
    if (partial == null || (full != null && full <= partial)) {
      return (seconds: full!, full: true);
    }
    return (seconds: partial, full: false);
  }

  /// Sort key for "fastest": your own best, else the joined best (the card
  /// itself lists every timed role).
  double? get shownFastestSeconds => fastestSeconds ?? joinedFastest?.seconds;
}

enum MissionRecordsSort { count, fastest, recent }

List<MissionRecordGroup> sortedMissionRecords(
  List<MissionRecordGroup> groups,
  MissionRecordsSort sort,
) => [...groups]
  ..sort((a, b) {
    final comparison = switch (sort) {
      MissionRecordsSort.count => b.count.compareTo(a.count),
      MissionRecordsSort.fastest =>
        (a.shownFastestSeconds ?? double.infinity).compareTo(
          b.shownFastestSeconds ?? double.infinity,
        ),
      MissionRecordsSort.recent => b.lastCompletedAt.compareTo(
        a.lastCompletedAt,
      ),
    };
    return comparison == 0 ? a.key.compareTo(b.key) : comparison;
  });

/// One route owns one summary and scan. Retiring its port clears account data.
final class MissionRecordsController extends ChangeNotifier {
  MissionRecordsController(this.port, {this.onImported}) {
    port?.addListener(_retire);
  }
  final MissionRecordsPort? port;
  final void Function()? onImported;
  List<MissionRecordGroup> groups = [];
  bool loaded = false, loading = false, busy = false, cancelling = false;
  bool importAvailable = false;

  /// Timed records saved before roles were tracked; a reimport classifies them.
  int unclassified = 0;
  String? reason, error, scanId;
  CatalogRow? progress, result;
  Timer? _poll;
  int _epoch = 0, _readEpoch = 0;
  bool _disposed = false;

  bool get visible => !_disposed && port?.readable == true;
  bool get importSupported => visible && port?.importSupported == true;
  bool get canImport =>
      visible &&
      loaded &&
      importAvailable &&
      port?.importSupported == true &&
      !busy;

  MissionRecordGroup? forDefinition(Object? guid) {
    if (!visible || guid == null) return null;
    for (final group in groups) {
      if (group.definitionId?.toLowerCase() == guid.toString().toLowerCase()) {
        return group;
      }
    }
    return null;
  }

  void _retire() {
    if (_disposed) return;
    _epoch++;
    _readEpoch++;
    _poll?.cancel();
    groups = [];
    unclassified = 0;
    loaded = loading = busy = cancelling = importAvailable = false;
    reason = error = scanId = null;
    progress = result = null;
    notifyListeners();
    if (visible) unawaited(load());
  }

  Future<void> load() async {
    if (!visible) return;
    final epoch = _epoch, readEpoch = ++_readEpoch;
    loading = true;
    notifyListeners();
    try {
      final data = await port!.request('summary');
      if (!_current(epoch) || readEpoch != _readEpoch) return;
      if (data['groups'] is! List ||
          data['importAvailable'] is! bool ||
          (data['groups'] as List).any((g) => g is! Map) ||
          data['importUnavailableReason'] != null &&
              !const {
                'signedOut',
                'identityUnverified',
                'consentMissing',
                'localMode',
              }.contains(data['importUnavailableReason'])) {
        throw const FormatException('Invalid mission records summary');
      }
      final next = catalogRows(data['groups'])
          .map(MissionRecordGroup.new)
          .toList();
      groups = next;
      loaded = true;
      importAvailable = data['importAvailable'] == true;
      unclassified = switch (data['unclassified']) {
        final num n when n > 0 => n.toInt(),
        _ => 0,
      };
      reason = data['importUnavailableReason'] as String?;
      error = null;
    } catch (_) {
      if (_current(epoch) && readEpoch == _readEpoch) error = 'readError';
    } finally {
      if (_current(epoch) && readEpoch == _readEpoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch && visible;

  Future<void> startImport() async {
    if (!canImport) return;
    final epoch = _epoch;
    busy = true;
    cancelling = false;
    progress = {'phase': 'discovering', 'filesDone': 0, 'filesTotal': 0};
    result = null;
    error = null;
    notifyListeners();
    try {
      final data = await port!.request('importStart');
      if (!_current(epoch)) return;
      final id = data['scanId'];
      if (id is! String || id.isEmpty) throw const MissionRecordsFailure();
      scanId = id;
      if (cancelling) await _cancel(epoch);
      if (_current(epoch)) await _readProgress(epoch);
    } catch (failure) {
      if (!_current(epoch)) return;
      error =
          failure is MissionRecordsFailure &&
              failure.code == 'missionRecords.busy'
          ? 'busyError'
          : 'importError';
      busy = cancelling = false;
      progress = null;
      scanId = null;
      if (failure is MissionRecordsFailure &&
          failure.code == 'missionRecords.unavailable') {
        // BridgeRemoteException retains the code only. The local summary owns
        // the up-to-date gate reason, including consent changed after opening.
        await load();
      }
      if (_current(epoch)) notifyListeners();
    }
  }

  Future<void> _readProgress(int epoch) async {
    if (!_current(epoch) || scanId == null) return;
    try {
      final data = await port!.request('importRead', {'scanId': scanId});
      if (!_current(epoch)) return;
      final phase = data['phase'];
      if (!const {
        'discovering',
        'scanning',
        'done',
        'cancelled',
        'failed',
      }.contains(phase)) {
        throw const MissionRecordsFailure();
      }
      progress = data;
      if (phase == 'done' || phase == 'cancelled' || phase == 'failed') {
        busy = cancelling = false;
        scanId = null;
        progress = null;
        if (phase == 'done') {
          final imported = data['result'];
          if (imported is! Map) throw const MissionRecordsFailure();
          result = Map<String, Object?>.from(imported);
          onImported?.call();
          await load();
        } else if (phase == 'failed') {
          error = 'importError';
        } else {
          error = 'cancelled';
        }
      } else {
        _poll = Timer(const Duration(milliseconds: 400), () {
          unawaited(_readProgress(epoch));
        });
      }
    } catch (failure) {
      if (!_current(epoch)) return;
      if (!busy ||
          failure is MissionRecordsFailure &&
              const {
                'missionRecords.scanNotFound',
                'missionRecords.accountChanged',
                'missionRecords.invalidRequest',
              }.contains(failure.code)) {
        busy = cancelling = false;
        scanId = null;
        progress = null;
        error = 'importError';
        notifyListeners();
        return;
      }
      // The scan lives independently of a polling RPC. Retain its ID so the
      // user can cancel it; never start a second scan or replay importStart.
      error = 'importError';
      _poll = Timer(const Duration(seconds: 2), () {
        unawaited(_readProgress(epoch));
      });
    }
    if (_current(epoch)) notifyListeners();
  }

  Future<void> cancelImport() async {
    if (!busy || cancelling) return;
    cancelling = true;
    notifyListeners();
    if (scanId != null) await _cancel(_epoch);
  }

  Future<void> _cancel(int epoch) async {
    try {
      await port!.request('importCancel', {'scanId': scanId});
      // Read the authoritative terminal phase: a committed result wins a race
      // with cancellation. The existing serial poll continues to that phase.
    } catch (_) {
      if (_current(epoch)) {
        cancelling = false;
        error = 'importError';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _poll?.cancel();
    port?.removeListener(_retire);
    if (scanId != null && port?.importSupported == true) {
      unawaited(
        port!
            .request('importCancel', {'scanId': scanId})
            .catchError((_) => <String, Object?>{}),
      );
    }
    super.dispose();
  }
}
