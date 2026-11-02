import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../common/user_avatar_menu.dart';
import '../common/organization_ship_image_features.dart';
import '../communities/communities_module.dart';
import '../communities/community_bridge_hangar.dart';
import '../communities/community_bridge_transport.dart';
import '../communities/community_ship_avatar_access.dart';
import '../communities/community_ships_port.dart';
import '../communities/community_ship_image_port.dart';
import '../communities/community_ship_report_port.dart';
import '../onboarding/connection_mode_port.dart';
import 'official_fleet_ship_owner_access.dart';

/// Exposes only the implemented public library and G1 holder presentation.
/// The reused private transport also contains community operations, but none of
/// its sharing, report or ship-image capabilities escape this facade.
final class BridgeOfficialFleetSharedShips
    implements
        CommunityShipsPort,
        CommunityShipsRefreshPort,
        CommunityShipImagePort,
        CommunityShipReportPort,
        CommunityShipReportReceiptScope,
        OfficialFleetShipOwnerAccess {
  BridgeOfficialFleetSharedShips(
    BridgeClientSession session, {
    required String? Function() sourceRef,
    required this.sourceChanges,
    ConnectionModeControl? connectionMode,
  }) : _transport = _OfficialShipsTransport(
         session,
         sourceRef: sourceRef,
         connectionMode: connectionMode,
       ) {
    _unobserveGeneration = session.observeGenerationChanges((_, _) {
      _imageFeatures = null;
      _transport.invalidateReadScope();
      _retireReceipts();
    });
    _source = sourceRef();
    sourceChanges.addListener(_sourceChanged);
    _invalidations = _transport.invalidations.listen((_) {
      _owners.clear();
      _imageFeatures = null;
    });
    _receiptEvents = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _retireReceipts();
      }
    }, onDone: _retireReceipts);
    _capabilityKey = _currentCapabilityKey;
    _capabilities = session.capabilitiesChanged.listen((_) {
      final next = _currentCapabilityKey;
      if (next == _capabilityKey) return;
      _capabilityKey = next;
      _imageFeatures = null;
      _transport.invalidateReadScope();
    });
  }
  final _OfficialShipsTransport _transport;
  final Listenable sourceChanges;
  late final StreamSubscription<void> _invalidations;
  late final StreamSubscription<void> _capabilities;
  late final StreamSubscription<BridgeEnvelope> _receiptEvents;
  final _receiptRetirements = StreamController<void>.broadcast();
  bool _closed = false;
  void _retireReceipts() {
    if (!_closed) _receiptRetirements.add(null);
  }

  OrganizationShipImageFeatures? _imageFeatures;
  String _capabilityKey = '';
  String get _currentCapabilityKey => [
    'officialFleet.ships',
    ...OrganizationShipImageFeatures.callableNames,
  ].where(_transport.session.hostCapabilities.contains).join('|');
  late final void Function() _unobserveGeneration;
  String? _source;
  int _ownersEpoch = -1;
  final _owners = <(String, String), _Owner>{};
  void _sourceChanged() {
    final value = _transport.sourceRef();
    if (value == _source) return;
    _source = value;
    _imageFeatures = null;
    _owners.clear();
    _transport.invalidateReadScope();
  }

  @override
  Stream<void> get invalidations => _transport.invalidations;
  @override
  Stream<void> get shipRefreshes => _transport.shipRefreshes;
  @override
  bool get shipsAvailable => _transport.shipsAvailable;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    final epoch = _transport.requestEpoch, source = _transport.sourceRef();
    try {
      // Parse the same page contract as community. Sidecar permission cannot
      // rescue a malformed public page or a mismatched query/continuation.
      final result = await _transport.readShipsWithOwners(
        targetRef,
        offset: offset,
        revision: revision,
        query: query,
      );
      if (epoch != _transport.requestEpoch ||
          source != _transport.sourceRef() ||
          source == null) {
        throw const CommunityFailure('identityUnavailable');
      }
      final page = result.$1;
      final next = <(String, String), _Owner>{};
      final raw = result.$2;
      if (raw['sourceRef'] != source ||
          raw['owners'] is! List ||
          (raw['owners'] as List).length > 20) {
        throw const FormatException();
      }
      for (final value in raw['owners'] as List) {
        if (value is! Map) throw const FormatException();
        final owner = _Owner.parse(Map<String, Object?>.from(value), source);
        if (next.containsKey((targetRef, owner.reference))) {
          throw const FormatException();
        }
        next[(targetRef, owner.reference)] = owner;
      }
      final expected = page.ships.map((s) => s.ownerMemberRef).toSet();
      if (!setEquals(expected, next.keys.map((key) => key.$2).toSet())) {
        throw const FormatException();
      }
      for (final ship in page.ships) {
        final owner = next[(targetRef, ship.ownerMemberRef)]!;
        if (ship.ownerHasAvatar != (owner.avatar != null) ||
            ship.ownerAvatarVersion != owner.version ||
            ship.ownerGameName.isNotEmpty ||
            ship.ownerOnline ||
            owner.profile == null && ship.ownerCallsign.isNotEmpty) {
          throw const FormatException();
        }
      }
      // Statistics may read later pages while the first page remains visible.
      // Keep bounded opaque owner entries; source/account/permission failures
      // clear all entries, and profile actions independently reauthorize G1.
      if (_owners.length + next.length > 10000) _owners.clear();
      _owners.addAll(next);
      _ownersEpoch = epoch;
      _imageFeatures = page.imageFeatures;
      return page;
    } catch (error) {
      _owners.clear();
      _imageFeatures = null;
      if (error is FormatException || error is TypeError) {
        throw const CommunityFailure('dataInvalid');
      }
      if (error is CommunityFailure && error.code == 'unavailable') {
        throw const CommunityFailure('identityUnavailable');
      }
      if (error is! CommunityFailure) {
        throw const CommunityFailure('identityUnavailable');
      }
      rethrow;
    }
  }

  @override
  UserTarget? ownerTarget(String targetRef, CommunitySharedShip ship) {
    final owner = _owners[(targetRef, ship.ownerMemberRef)];
    if (_transport.isClosed ||
        _ownersEpoch != _transport.requestEpoch ||
        owner?.source != _transport.sourceRef() ||
        owner?.profile == null) {
      return null;
    }
    return UserTarget(
      'officialFleet',
      owner!.profile!,
      contextRef: owner.source,
    );
  }

  late final _avatarAccess = CommunityShipAvatarAccess(
    read: (target, member, {required offset, version}) async {
      final owner = _owners[(target, member)];
      if (_transport.isClosed ||
          _ownersEpoch != _transport.requestEpoch ||
          owner?.source != _transport.sourceRef() ||
          owner?.avatar == null ||
          offset != 0 ||
          version != null && version != owner!.version) {
        throw const CommunityFailure('identityUnavailable');
      }
      final data = owner!.avatar!;
      return {
        'schemaVersion': 1,
        'kind': 'avatar',
        'memberRef': member,
        'offset': 0,
        'version': owner.version,
        'mimeType': data.substring(5, data.indexOf(';')),
        'totalBytes': base64Decode(data.substring(data.indexOf(',') + 1))
            .length,
        'data': data.substring(data.indexOf(',') + 1),
        'next': null,
      };
    },
  );
  @override
  CommunityShipAvatarAccess get avatarAccess => _avatarAccess;

  @override
  bool get shipImageAvailable =>
      !_transport.isClosed &&
      _imageFeatures?.read == true &&
      _transport.session.hostCapabilities.contains('officialFleet.shipImage');
  @override
  bool get shipReportAvailable =>
      !_transport.isClosed &&
      _imageFeatures?.report == true &&
      const [
        'officialFleet.reportShipImage',
        'officialFleet.shipImageReportStatus',
      ].every(_transport.session.hostCapabilities.contains);
  @override
  Future<Map<String, Object?>> readShipImage(
    String targetRef,
    String shipRef, {
    required int offset,
    String? version,
  }) {
    if (!shipImageAvailable) throw const CommunityFailure('unavailable');
    return _transport.readShipImage(
      targetRef,
      shipRef,
      offset: offset,
      version: version,
    );
  }

  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) async {
    if (!shipReportAvailable) {
      return const CommunityShipReportOutcome('rejected', error: 'unavailable');
    }
    try {
      return CommunityShipReportOutcome.parse(
        await _transport.sendRequest(
          'communities.reportShipImage',
          intent.toPayload(),
        ),
        intent,
      );
    } catch (_) {
      return const CommunityShipReportOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  @override
  bool get reportReceiptQueryAvailable =>
      !_transport.isClosed &&
      !_transport.session.connectionModeChanging &&
      _transport.onlineTrafficAllowed &&
      _transport.session.hostCapabilities.contains(
        'officialFleet.shipImageReportStatus',
      );
  @override
  Stream<void> get reportReceiptRetirements => _receiptRetirements.stream;
  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) async {
    if (!reportReceiptQueryAvailable) {
      return const CommunityShipReportOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
    try {
      return CommunityShipReportOutcome.parse(
        await _transport.checkOfficialReportReceipt(intent.requestId),
        intent,
      );
    } catch (_) {
      return const CommunityShipReportOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _retireReceipts();
    _closed = true;
    _imageFeatures = null;
    sourceChanges.removeListener(_sourceChanged);
    _unobserveGeneration();
    _owners.clear();
    await _invalidations.cancel();
    await _capabilities.cancel();
    await _receiptEvents.cancel();
    await _transport.close();
    await _receiptRetirements.close();
  }
}

final class _Owner {
  const _Owner(
    this.reference,
    this.source,
    this.profile,
    this.avatar,
    this.version,
  );
  final String reference, source;
  final String? profile, avatar, version;
  factory _Owner.parse(Map<String, Object?> value, String source) {
    final ref = value['ownerMemberRef'],
        profile = value['profileReference'],
        avatar = value['avatarImageData'],
        version = value['avatarVersion'];
    if (ref is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(ref) ||
        profile != null &&
            (profile is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(profile)) ||
        avatar != null &&
            (avatar is! String ||
                avatar.length > 4096 ||
                !RegExp(r'^data:image/(png|jpeg|gif|bmp|webp);base64,')
                    .hasMatch(avatar)) ||
        version != null &&
            (version is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(version)) ||
        profile == null && (avatar != null || version != null) ||
        (avatar == null) != (version == null)) {
      throw const FormatException();
    }
    if (avatar != null) {
      final bytes = base64Decode(
        (avatar as String).substring(avatar.indexOf(',') + 1),
      );
      if (bytes.isEmpty ||
          bytes.length > 3 * 1024 ||
          sha256.convert(bytes).toString() != version) {
        throw const FormatException();
      }
    }
    return _Owner(
      ref,
      source,
      profile as String?,
      avatar as String?,
      version as String?,
    );
  }
}

final class _OfficialShipsTransport extends CommunityBridgeTransport
    with CommunityBridgeHangar {
  _OfficialShipsTransport(
    super.session, {
    required this.sourceRef,
    super.connectionMode,
  });
  final String? Function() sourceRef;
  @override
  CommunityShipsPage parseShipPage(Map<String, Object?> payload) =>
      CommunityShipsPage.parse(payload, officialImages: true);
  @override
  bool get shipsAvailable =>
      !isClosed && session.hostCapabilities.contains('officialFleet.ships');
  @override
  bool get shipImageAvailable => false;
  @override
  bool get shipReportAvailable => false;
  @override
  bool get hangarSharingAvailable => false;
  @override
  Future<Map<String, Object?>> sendRequest(
    String name,
    Map<String, Object?> payload, {
    Duration? timeout,
    bool Function()? officialAnnouncementCurrent,
  }) async {
    final command = const {
      'communities.ships': 'officialFleet.ships',
      'communities.shipImage': 'officialFleet.shipImage',
      'communities.reportShipImage': 'officialFleet.reportShipImage',
    }[name];
    if (command == null) {
      throw const CommunityFailure('unavailable');
    }
    final source = sourceRef();
    if (source == null ||
        !RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(source)) {
      throw const CommunityFailure('identityUnavailable');
    }
    final result = await super.sendRequest(
      command,
      {...payload, if (name == 'communities.ships') 'sourceRef': source},
      timeout: const Duration(seconds: 15),
      officialAnnouncementCurrent: officialAnnouncementCurrent,
    );
    if (source != sourceRef()) {
      throw const CommunityFailure('identityUnavailable');
    }
    return result;
  }

  Future<Map<String, Object?>> checkOfficialReportReceipt(
    String requestId,
  ) async {
    final generation = session.activeGeneration;
    final watch = Stopwatch()..start();
    Duration remaining() => const Duration(seconds: 15) - watch.elapsed;
    bool current() =>
        !isClosed &&
        generation == session.activeGeneration &&
        !session.connectionModeChanging &&
        onlineTrafficAllowed &&
        session.hostCapabilities.contains(
          'officialFleet.shipImageReportStatus',
        );
    if (!current() || !RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId)) {
      throw const CommunityFailure('identityUnavailable');
    }
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: remaining(),
    );
    if (!current() ||
        account.payload['schemaVersion'] != 1 ||
        account.payload['state'] != 'signedIn' ||
        account.accountContext == null) {
      throw const CommunityFailure('identityUnavailable');
    }
    final reply = await session.request(
      'officialFleet.shipImageReportStatus',
      payload: {'schemaVersion': 1, 'requestId': requestId},
      accountContext: account.accountContext,
      timeout: remaining(),
    );
    final a = account.accountContext, b = reply.accountContext;
    if (!current() ||
        a == null ||
        b == null ||
        a.environment != b.environment ||
        a.authority != b.authority ||
        a.subject != b.subject ||
        reply.payload['schemaVersion'] != 1) {
      throw const CommunityFailure('identityUnavailable');
    }
    return reply.payload;
  }

  Future<(CommunityShipsPage, Map<String, Object?>)> readShipsWithOwners(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) => readShipProjection(
    targetRef,
    offset: offset,
    revision: revision,
    query: query ?? CommunityShipQuery(),
  );
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) => throw const CommunityFailure('unavailable');
  @override
  Future<String> execute(String action, String targetRef) async => 'rejected';
}
