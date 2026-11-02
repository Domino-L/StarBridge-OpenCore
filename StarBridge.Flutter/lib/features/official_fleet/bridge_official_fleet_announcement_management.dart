import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../common/organization_announcement_management_port.dart';
import '../communities/communities_module.dart';
import '../communities/community_bridge_transport.dart';

/// Borrows the existing account transport and its request owner. Host retains
/// the only durable journal, private authority bindings and management writes.
final class BridgeOfficialFleetAnnouncementManagement
    implements OrganizationAnnouncementManagementPort {
  BridgeOfficialFleetAnnouncementManagement(this.transport) {
    _managementKey = _currentManagementKey;
    _outcomeKey = transport.supportsOfficialAnnouncementCommand(outcomeCommand);
    _transportEvents = transport.invalidations.listen((_) => _retireAccount());
    _capabilities = transport.session.capabilitiesChanged.listen((_) {
      if (_closed) return;
      final management = _currentManagementKey;
      final outcome = transport.supportsOfficialAnnouncementCommand(
        outcomeCommand,
      );
      if (management != _managementKey) {
        _managementKey = management;
        _retireManagement();
      }
      if (outcome != _outcomeKey) {
        _outcomeKey = outcome;
        _retireOutcomes();
      }
    });
    _unobserve = transport.session.observeGenerationChanges(
      (_, _) => _retireAccount(),
    );
    _removeNetwork = transport.session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async => _retireAccount(),
        reconcile: () async {},
      ),
    );
  }
  final CommunityBridgeTransport transport;
  static const editorCommand = 'officialFleet.readAnnouncementEditor';
  static const manageCommand = 'officialFleet.manageAnnouncements';
  static const outcomeCommand = 'officialFleet.readAnnouncementOutcome';
  static const callableNames = {editorCommand, manageCommand, outcomeCommand};
  final _changes = StreamController<void>.broadcast(sync: true);
  final _managementChanges = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<void> _transportEvents, _capabilities;
  late final void Function() _unobserve, _removeNetwork;
  bool _closed = false, _outcomeKey = false;
  String _managementKey = '';
  int _accountEpoch = 0,
      _managementEpoch = 0,
      _outcomeEpoch = 0,
      _editorRead = 0;

  String get _currentManagementKey => callableNames
      .where(transport.supportsOfficialAnnouncementCommand)
      .join('|');
  bool get hostAdvertisesManagement =>
      callableNames.every(transport.supportsOfficialAnnouncementCommand);
  bool get hostAdvertisesOutcomes =>
      transport.supportsOfficialAnnouncementCommand(outcomeCommand);
  bool get _admitted =>
      !_closed &&
      !transport.isClosed &&
      !transport.session.connectionModeChanging &&
      transport.onlineTrafficAllowed;
  @override
  bool get managementAvailable => _admitted && hostAdvertisesManagement;
  @override
  bool get outcomesAvailable => _admitted && hostAdvertisesOutcomes;
  @override
  Stream<void> get invalidations => _changes.stream;
  @override
  Stream<void> get managementInvalidations => _managementChanges.stream;

  void _retireManagement() {
    if (_closed) return;
    _managementEpoch++;
    _editorRead++;
    _managementChanges.add(null);
  }

  void _retireOutcomes() {
    if (_closed) return;
    _outcomeEpoch++;
    _changes.add(null);
  }

  void _retireAccount() {
    if (_closed) return;
    _accountEpoch++;
    _retireManagement();
    _retireOutcomes();
  }

  (int, int, int, int, int) _fence(bool management) => (
    _accountEpoch,
    management ? _managementEpoch : _outcomeEpoch,
    transport.requestEpoch,
    transport.session.activeGeneration,
    transport.session.connectionModeRevision,
  );
  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> payload, {
    required bool management,
  }) async {
    if (!(management ? managementAvailable : outcomesAvailable)) {
      throw const CommunityFailure('unavailable');
    }
    final fence = _fence(management);
    bool current() =>
        fence == _fence(management) &&
        (management ? managementAvailable : outcomesAvailable);
    final row = await transport.sendRequest(
      name,
      payload,
      timeout: const Duration(seconds: 15),
      officialAnnouncementCurrent: current,
    );
    if (!current()) {
      throw const CommunityFailure('identityUnavailable');
    }
    return row;
  }

  @override
  Future<OrganizationAnnouncementEditor> readEditor(String sourceRef) =>
      transport.workspaceRead(() async {
        if (!RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(sourceRef) ||
            int.tryParse(sourceRef.substring(14)) == null) {
          throw const FormatException();
        }
        final version = ++_editorRead;
        final row = await _request(editorCommand, {
          'schemaVersion': 1,
          'sourceRef': sourceRef,
        }, management: true);
        if (version != _editorRead) {
          throw const CommunityFailure('refreshRequired');
        }
        return OrganizationAnnouncementEditor.parse(row, sourceRef);
      });

  @override
  Future<OrganizationAnnouncementOutcome> manage(
    OrganizationAnnouncementIntent intent,
  ) async {
    if (!managementAvailable) {
      return OrganizationAnnouncementOutcome.unavailable(intent);
    }
    try {
      // Exactly one borrowed request. Any uncertainty after admission stays on
      // the original ID; neither OAuth callbacks nor queries replay it here.
      final row = await _request(
        manageCommand,
        intent.toPayload(),
        management: true,
      );
      return OrganizationAnnouncementOutcome.parseManage(row, intent);
    } on OfficialAnnouncementNotDispatched {
      return OrganizationAnnouncementOutcome.unavailable(intent);
    } catch (_) {
      return OrganizationAnnouncementOutcome.unknown(intent);
    }
  }

  @override
  Future<OrganizationAnnouncementPendingPage> readPending({int offset = 0}) =>
      transport.workspaceRead(() async {
        if (offset < 0 || offset > 127 || offset % 20 != 0) {
          throw const FormatException();
        }
        final row = await _request(outcomeCommand, {
          'schemaVersion': 1,
          'kind': 'pending',
          'offset': offset,
        }, management: false);
        return OrganizationAnnouncementPendingPage.parse(
          row,
          expectedOffset: offset,
        );
      });

  @override
  Future<OrganizationAnnouncementOutcome> query(
    String requestId, {
    String? expectedSourceRef,
    String? expectedAction,
  }) => transport.workspaceRead(() async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId)) {
      throw const FormatException();
    }
    final row = await _request(outcomeCommand, {
      'schemaVersion': 1,
      'kind': 'query',
      'requestId': requestId,
    }, management: false);
    return OrganizationAnnouncementOutcome.parseQuery(
      row,
      requestId,
      expectedSourceRef: expectedSourceRef,
      expectedAction: expectedAction,
    );
  });

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _accountEpoch++;
    _managementEpoch++;
    _outcomeEpoch++;
    _editorRead++;
    _managementChanges.add(null);
    _changes.add(null);
    _unobserve();
    _removeNetwork();
    await _transportEvents.cancel();
    await _capabilities.cancel();
    await _managementChanges.close();
    await _changes.close();
    // The shared transport/session and its activity worker remain with owner.
  }
}
