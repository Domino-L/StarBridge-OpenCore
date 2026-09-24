import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'community_ships_port.dart';
import 'community_hangar_sharing_port.dart';
import 'community_ship_image_port.dart';
import 'community_ship_report_port.dart';

import 'community_bridge_transport.dart';

mixin CommunityBridgeHangar on CommunityBridgeTransport
    implements
        CommunityShipsPort,
        CommunityHangarSharingPort,
        CommunityShipImagePort,
        CommunityShipReportPort {
  @override
  bool get shipsAvailable =>
      !isClosed && session.hostCapabilities.contains('communities.ships');
  @override
  bool get shipImageAvailable =>
      !isClosed && session.hostCapabilities.contains('communities.shipImage');
  @override
  bool get shipReportAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.reportShipImage');
  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) => _shipReport(intent, checkOnly: false);
  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) => _shipReport(intent, checkOnly: true);
  Future<CommunityShipReportOutcome> _shipReport(
    CommunityShipReportIntent intent, {
    required bool checkOnly,
  }) async {
    if (!shipReportAvailable) {
      return const CommunityShipReportOutcome('rejected', error: 'unavailable');
    }
    try {
      return CommunityShipReportOutcome.parse(
        await sendRequest('communities.reportShipImage', {
          ...intent.toPayload(),
          if (checkOnly) 'checkOnly': true,
        }),
        intent,
      );
    } on BridgeClientException catch (e) {
      if (e.code == 'communities.dataInvalid') {
        return const CommunityShipReportOutcome(
          'rejected',
          error: 'dataInvalid',
        );
      }
      return const CommunityShipReportOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    } catch (_) {
      return const CommunityShipReportOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  @override
  Future<Map<String, Object?>> readShipImage(
    String targetRef,
    String shipRef, {
    required int offset,
    String? version,
  }) => workspaceRead(() {
    final reference = RegExp(r'^[a-f0-9]{32}$');
    if (!reference.hasMatch(targetRef) ||
        !reference.hasMatch(shipRef) ||
        offset < 0 ||
        offset >= 2 * 1024 * 1024 ||
        offset % (192 * 1024) != 0 ||
        offset > 0 && version == null ||
        version != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(version)) {
      throw const FormatException();
    }
    return sendRequest('communities.shipImage', {
      'targetRef': targetRef,
      'shipRef': shipRef,
      'offset': offset,
      'version': version,
    });
  });
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) => workspaceRead(() async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(targetRef) ||
        offset < 0 ||
        offset > 1000000 ||
        offset % 20 != 0 ||
        offset > 0 && revision == null ||
        revision != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision)) {
      throw const FormatException();
    }
    final page = CommunityShipsPage.parse(
      await sendRequest('communities.ships', {
        'targetRef': targetRef,
        'offset': offset,
        'revision': revision,
        if (query != null) 'query': query.toPayload(),
      }),
    );
    if (page.targetRef != targetRef ||
        page.offset != offset ||
        revision != null && page.revision != revision ||
        page.query != query) {
      throw const FormatException();
    }
    return page;
  });
  @override
  bool get hangarSharingAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.hangarSharing') &&
      session.hostCapabilities.contains('communities.saveHangarSharing');

  @override
  Future<CommunityHangarSharing> readHangarSharing() => workspaceRead(
    () async => CommunityHangarSharing.parse(
      await sendRequest('communities.hangarSharing', const {}),
    ),
  );

  @override
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String editRef,
    List<String> selectedRefs,
  ) async {
    final selected = List<String>.of(selectedRefs);
    if (!CommunityHangarSharing.validReference(editRef) ||
        selected.length > CommunityHangarSharing.maximumTargets ||
        selected.any((ref) => !CommunityHangarSharing.validReference(ref)) ||
        selected.toSet().length != selected.length) {
      return const CommunityHangarSharingOutcome(
        'rejected',
        error: 'invalidDraft',
      );
    }
    if (!hangarSharingAvailable) {
      return const CommunityHangarSharingOutcome(
        'rejected',
        error: 'unavailable',
      );
    }
    try {
      return CommunityHangarSharingOutcome.parse(
        await sendRequest('communities.saveHangarSharing', {
          'editRef': editRef,
          'selectedRefs': selected,
          'inventoryMode': 'auto',
        }),
      );
    } on BridgeClientException catch (e) {
      return e.code == 'communities.dataInvalid'
          ? const CommunityHangarSharingOutcome(
              'rejected',
              error: 'invalidDraft',
            )
          : const CommunityHangarSharingOutcome(
              'unknown',
              error: 'outcomeUnknown',
            );
    } catch (_) {
      return const CommunityHangarSharingOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }
}
