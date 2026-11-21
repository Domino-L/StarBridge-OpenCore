import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../onboarding/connection_mode_port.dart';
import 'catalog_port.dart';

final class MissionRecordsFailure implements Exception {
  const MissionRecordsFailure([
    this.code = 'missionRecords.unavailable',
    this.reason,
  ]);
  final String code;
  final String? reason;
}

abstract interface class MissionRecordsPort implements Listenable {
  bool get supported;
  bool get readable;
  bool get importSupported;
  Future<CatalogRow> request(String operation, [CatalogRow input = const {}]);
  void dispose();
}

/// These RPCs read local Host storage; they never use the catalogue budget.
final class BridgeMissionRecordsPort extends ChangeNotifier
    implements MissionRecordsPort {
  BridgeMissionRecordsPort(this.session, this.mode) {
    _removeGeneration = session.observeGenerationChanges((_, _) => _retire());
    _capabilityKey = _currentCapabilityKey;
    _capabilities = session.capabilitiesChanged.listen((_) {
      final key = _currentCapabilityKey;
      if (_capabilityKey == key) return;
      _capabilityKey = key;
      _retire();
    });
    _modeKey = _currentModeKey;
    mode?.addListener(_modeChanged);
    _removeMode = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          _paused = true;
          _retire();
          await _draining;
        },
        reconcile: () async {
          _paused = false;
          _retire();
        },
      ),
    );
  }
  final BridgeClientSession session;
  final ConnectionModeControl? mode;
  final _pending = <BridgeRequestOperation>{};
  late final void Function() _removeGeneration, _removeMode;
  late final StreamSubscription<void> _capabilities;
  bool _disposed = false, _paused = false;
  int _revision = 0;
  BridgeAccountContext? _owner;
  bool _ownerResolved = false;
  Object? _modeKey, _capabilityKey;
  Object get _currentCapabilityKey => (
    session.hostCapabilities.contains('missionRecords.read'),
    session.hostCapabilities.contains('missionRecords.import'),
  );
  Future<void> _draining = Future<void>.value();
  Object get _currentModeKey => (
    mode?.allowsOnlineTraffic,
    mode?.busy,
    mode?.failed,
    mode?.snapshot.state,
    mode?.snapshot.scope,
    mode?.snapshot.revision,
  );

  void _modeChanged() {
    final key = _currentModeKey;
    if (_modeKey == key) return;
    _modeKey = key;
    _retire();
  }

  @override
  bool get supported =>
      !_disposed &&
      !session.isClosed &&
      session.hostCapabilities.contains('missionRecords.read');
  @override
  bool get readable =>
      supported &&
      !_paused &&
      !session.connectionModeChanging &&
      (mode?.allowsOnlineTraffic == true ||
          mode?.snapshot.state == ConnectionModeState.local);
  @override
  bool get importSupported =>
      readable && session.hostCapabilities.contains('missionRecords.import');

  void _retire() {
    if (_disposed) return;
    _revision++;
    _owner = null;
    _ownerResolved = false;
    _draining = Future.wait(
      _pending.toList().map((work) async {
        try {
          await work.cancel();
        } catch (_) {
          /* Retired locally regardless. */
        }
      }),
    ).then((_) {});
    notifyListeners();
  }

  @override
  Future<CatalogRow> request(
    String operation, [
    CatalogRow input = const {},
  ]) async {
    if (!readable ||
        (operation != 'summary' && !importSupported) ||
        !const {
          'summary',
          'importStart',
          'importRead',
          'importCancel',
        }.contains(operation)) {
      throw const MissionRecordsFailure();
    }
    final generation = session.activeGeneration,
        revision = _revision,
        modeRevision = session.connectionModeRevision;
    BridgeRequestOperation? work;
    try {
      if (!_ownerResolved) {
        // Same owner resolution as gameplay time. Never infer an owner from UI
        // profile fields; the Host supplies the current account context.
        final current = session.beginRequest(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
        );
        _pending.add(current);
        try {
          final snapshot = await current.future;
          if (!readable ||
              revision != _revision ||
              generation != snapshot.sessionGeneration ||
              generation != session.activeGeneration ||
              snapshot.payload['schemaVersion'] != 1) {
            throw const MissionRecordsFailure('missionRecords.accountChanged');
          }
          _owner = snapshot.accountContext;
          _ownerResolved = true;
        } finally {
          _pending.remove(current);
        }
      }
      work = session.beginRequest(
        'missionRecords.$operation',
        accountContext: _owner,
        payload: {'schemaVersion': 1, ...input},
        timeout: const Duration(seconds: 22),
      );
      _pending.add(work);
      final response = await work.future;
      // Host 073 versions summary only; import replies are unwrapped objects.
      // Accept an absent version there, but reject any explicit wrong version.
      if (!readable ||
          revision != _revision ||
          modeRevision != session.connectionModeRevision ||
          generation != session.activeGeneration ||
          generation != response.sessionGeneration ||
          response.accountContext?.environment != _owner?.environment ||
          response.accountContext?.authority != _owner?.authority ||
          response.accountContext?.subject != _owner?.subject ||
          response.status != 'ok' ||
          (response.payload['schemaVersion'] != 1 &&
              (operation == 'summary' ||
                  response.payload.containsKey('schemaVersion')))) {
        throw const MissionRecordsFailure('missionRecords.accountChanged');
      }
      return response.payload;
    } on BridgeRemoteException catch (error) {
      throw MissionRecordsFailure(error.code);
    } on MissionRecordsFailure {
      rethrow;
    } catch (_) {
      throw const MissionRecordsFailure();
    } finally {
      _pending.remove(work);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    for (final work in _pending.toList()) {
      unawaited(work.cancel().catchError((_) {}));
    }
    notifyListeners();
    mode?.removeListener(_modeChanged);
    _removeGeneration();
    _removeMode();
    unawaited(_capabilities.cancel());
    super.dispose();
  }
}
