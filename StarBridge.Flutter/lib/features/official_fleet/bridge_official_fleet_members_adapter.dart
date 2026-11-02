import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../shared/bounded_inline_avatar.dart';
import '../communities/community_activity.dart';
import '../onboarding/connection_mode_port.dart';
import 'official_fleet_bridge_values.dart' as wire;
import 'official_fleet_members_models.dart';
import 'official_fleet_members_port.dart';
import 'official_fleet_read_failure.dart';

/// Consumes only the Host's projection of SCM's registered-member directory.
/// Account generation and response ownership remain enforced by BridgeSession.
final class BridgeOfficialFleetMembersAdapter
    implements OfficialFleetMembersPort, OfficialFleetMembersActivityPort {
  BridgeOfficialFleetMembersAdapter(this._session) {
    _activity = CommunityActivity(
      _session,
      onlineAllowed: () => _mode?.allowsOnlineTraffic != false,
    );
    _activity.configureHintStrategy(null);
    _activityErrors = _activity.errors.stream.listen((_) {
      _runtimeInvalidations.add(null);
    });
    _capabilities = _session.capabilitiesChanged.listen((_) {
      _activity.reconcileAdmission();
      _runtimeInvalidations.add(null);
    });
    _unobserveGeneration = _session.observeGenerationChanges((_, _) {
      retireRuntimeActivity();
      _runtimeInvalidations.add(null);
    });
    _subscription = _session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _invalidations.add(null);
        retireRuntimeActivity();
      }
    });
  }
  final BridgeClientSession _session;
  late final CommunityActivity _activity;
  late final StreamSubscription<String> _activityErrors;
  late final StreamSubscription<void> _capabilities;
  late final void Function() _unobserveGeneration;
  final _runtimeInvalidations = StreamController<void>.broadcast();
  ConnectionModeControl? _mode;
  (Object, int?, ConnectionModeState, bool, bool)? _modeKey;
  (String, String, OfficialFleetMemberFilter, int, int)? _queryKey;
  void bindConnectionMode(ConnectionModeControl mode) {
    if (identical(mode, _mode)) return;
    _mode?.removeListener(_modeChanged);
    _mode = mode;
    mode.addListener(_modeChanged);
    _modeChanged();
  }

  void _modeChanged() {
    final mode = _mode;
    if (mode == null) return;
    final value = mode.snapshot;
    final key = (
      value.scope,
      value.revision,
      value.state,
      mode.failed,
      mode.allowsOnlineTraffic,
    );
    if (key == _modeKey) return;
    final previous = _modeKey;
    _modeKey = key;
    _activity.reconcileAdmission();
    // Only a new revision of the same scope, state, failure and traffic
    // admission is no change of authority: reread silently and keep the rows
    // (user report 2026-10-29: the list blanked on every revision).
    if (previous != null &&
        previous.$1 == key.$1 &&
        previous.$3 == key.$3 &&
        previous.$4 == key.$4 &&
        previous.$5 == key.$5) {
      if (!_activity.changes.isClosed) _activity.changes.add(null);
      return;
    }
    _runtimeInvalidations.add(null);
  }

  @override
  Stream<void> get runtimeChanges => _activity.changes.stream;
  @override
  Stream<void> get runtimeScopeInvalidations => _runtimeInvalidations.stream;
  @override
  void retireRuntimeActivity() => _activity.configureHintStrategy(null);
  final _invalidations = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;
  @override
  Stream<void> get invalidations => _invalidations.stream;

  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    final key = (
      query.sourceRef,
      query.search,
      query.filter,
      query.pageNumber,
      query.pageSize,
    );
    if (key != _queryKey) {
      _queryKey = key;
      retireRuntimeActivity();
    }
    try {
      if (_mode?.allowsOnlineTraffic == false) {
        throw const BridgeClientException('account.local_mode');
      }
      final runtime = _session.hostCapabilities.contains(
        'officialFleet.runtimeMembers',
      );
      if (runtime) {
        _activity.configureHintStrategy(
          CommunityActivityHintStrategy(
            sourceRef: query.sourceRef,
            command: 'officialFleet.waitRuntimeActivity',
            capability: 'officialFleet.runtimeActivity',
            payload: {
              'schemaVersion': 2,
              'sourceRef': query.sourceRef,
              'search': query.search,
              'filter': 'all',
              'pageNumber': query.pageNumber,
              'pageSize': query.pageSize,
            },
          ),
        );
      } else {
        retireRuntimeActivity();
      }
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      wire.requireSchema(account.payload);
      if (account.payload['state'] != 'signedIn' ||
          account.accountContext == null) {
        throw const BridgeFormatException('Current SCM session required.');
      }
      final response = await _session.request(
        runtime
            ? 'officialFleet.getRuntimeMembers'
            : 'officialFleet.getMembers',
        timeout: runtime ? const Duration(seconds: 12) : null,
        accountContext: account.accountContext,
        payload: {
          'schemaVersion': runtime ? 2 : 1,
          'sourceRef': query.sourceRef,
          'search': query.search,
          'filter': query.filter.name,
          'pageNumber': query.pageNumber,
          'pageSize': query.pageSize,
        },
      );
      return parseOfficialFleetMembers(
        response.payload,
        query,
        runtime: runtime,
      );
    } on Object catch (error) {
      // The worker may still recover through a fresh authorized hint and its
      // bounded reconciliation. No former rows survive this failed read.
      return OfficialFleetMemberDirectorySnapshot.unavailable(
        query: query,
        failureKey: fleetReadFailureKey(error, members: true),
        transientFailure: fleetReadIsTransient(error),
      );
    }
  }

  @override
  Future<void> close() async {
    _unobserveGeneration();
    _mode?.removeListener(_modeChanged);
    await _activityErrors.cancel();
    await _capabilities.cancel();
    await _activity.close();
    await _runtimeInvalidations.close();
    await _subscription.cancel();
    await _invalidations.close();
  }
}

OfficialFleetMemberDirectorySnapshot parseOfficialFleetMembers(
  Map<String, Object?> payload,
  OfficialFleetMemberDirectoryQuery query, {
  bool runtime = false,
}) {
  if (runtime ? payload['schemaVersion'] != 2 : payload['schemaVersion'] != 1) {
    throw const BridgeFormatException('Invalid member schema.');
  }
  if (runtime) {
    final caps = payload['runtimeCapabilities'];
    final filters = payload['supportedFilters'];
    if (caps is! Map ||
        caps.length != 6 ||
        const [
          'presence',
          'server',
          'ship',
          'location',
        ].any((key) => caps[key] != true) ||
        caps['onlineCount'] != false ||
        caps['inGameCount'] != false ||
        filters is! List ||
        filters.length != 1 ||
        filters.single != 'all') {
      throw const BridgeFormatException('Invalid runtime handshake.');
    }
  }
  final rows = payload['members'];
  final total = wire.optionalNonNegativeInt(payload, 'totalCount');
  final pages = wire.optionalNonNegativeInt(payload, 'totalPages');
  if (payload['sourceRef'] != query.sourceRef ||
      payload['search'] != query.search ||
      payload['pageNumber'] != query.pageNumber ||
      payload['pageSize'] != query.pageSize ||
      payload['filter'] != 'all' ||
      query.filter != OfficialFleetMemberFilter.all ||
      payload['coverage'] != 'scmRegisteredMembers' ||
      total == null ||
      pages == null ||
      pages != (total == 0 ? 1 : (total / query.pageSize).ceil()) ||
      payload['onlineCount'] != null ||
      payload['inGameCount'] != null ||
      rows is! List ||
      rows.length > query.pageSize ||
      rows.length > total) {
    throw const BridgeFormatException('Invalid scoped member page.');
  }
  final references = <String>{};
  final members = <OfficialFleetMember>[];
  for (final value in rows) {
    if (value is! Map) throw const BridgeFormatException('Invalid member.');
    final row = value.cast<String, Object?>();
    final reference = wire.requiredString(row, 'memberRef');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(reference) ||
        !references.add(reference) ||
        (runtime
            ? !const {
                'offline',
                'online',
                'away',
                'inGame',
              }.contains(row['presence'])
            : row['presence'] != 'unknown') ||
        row['officialRankValue'] != null) {
      throw const BridgeFormatException('Invalid member facts.');
    }
    final identityState = row.containsKey('identityState')
        ? switch (row['identityState']) {
            'scm' => OfficialFleetMemberIdentityState.scm,
            'starBridge' => OfficialFleetMemberIdentityState.starBridge,
            'restricted' => OfficialFleetMemberIdentityState.restricted,
            _ => throw const BridgeFormatException('Invalid member identity.'),
          }
        : null;
    final linked = identityState == OfficialFleetMemberIdentityState.starBridge;
    final restricted =
        identityState == OfficialFleetMemberIdentityState.restricted;
    OfficialFleetMemberField field(String key) {
      if (!runtime) {
        return const OfficialFleetMemberField(
          OfficialFleetMemberFieldState.unknown,
        );
      }
      final value = row[key];
      if (value is! Map ||
          value.keys.any(
            (k) => !const {'state', 'value', 'confidence'}.contains(k),
          ) ||
          !const {
            'value',
            'unknown',
            'notShared',
            'notInGame',
          }.contains(value['state']) ||
          (value['state'] == 'value'
              ? value['value'] is! String ||
                    (value['value'] as String).trim().isEmpty ||
                    (value['value'] as String).length > 512 ||
                    RegExp(r'[\u0000-\u001f\u007f-\u009f]')
                        .hasMatch(value['value'] as String)
              : value['value'] != null || value['confidence'] != null) ||
          value['confidence'] != null &&
              (value['confidence'] is! String ||
                  (value['confidence'] as String).length > 32 ||
                  RegExp(r'[\u0000-\u001f\u007f-\u009f]')
                      .hasMatch(value['confidence'] as String))) {
        throw const BridgeFormatException('Invalid runtime cell.');
      }
      return OfficialFleetMemberField(
        OfficialFleetMemberFieldState.values.byName(value['state'] as String),
        value: value['value'] as String?,
      );
    }

    final server = field('server'),
        ship = field('ship'),
        location = field('location');
    String? fact(String key, int max) {
      final value = row[key];
      if (value != null &&
          (value is! String ||
              value.length > max ||
              RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(value))) {
        throw const BridgeFormatException('Invalid runtime fact.');
      }
      return value as String?;
    }

    final region = runtime ? fact('serverRegion', 32) : null;
    final targetCode = runtime ? fact('arrivalTargetCode', 512) : null;
    final hiddenReason = runtime ? fact('locationHiddenReason', 32) : null;
    final hasSession = runtime ? row['hasServerSession'] : null;
    final pending = runtime ? row['arrivalPending'] : false;
    if (runtime &&
        (hasSession != null && hasSession is! bool ||
            pending is! bool ||
            hiddenReason != null && hiddenReason != 'lowConfidence' ||
            !linked && row['presence'] != 'offline' ||
            server.state == OfficialFleetMemberFieldState.notShared &&
                (region != null || hasSession != null) ||
            location.state == OfficialFleetMemberFieldState.notShared &&
                (pending == true ||
                    targetCode != null ||
                    hiddenReason != null) ||
            row['presence'] != 'inGame' &&
                (server.state != OfficialFleetMemberFieldState.notInGame ||
                    ship.state != OfficialFleetMemberFieldState.notInGame ||
                    location.state != OfficialFleetMemberFieldState.notInGame ||
                    region != null ||
                    hasSession != null ||
                    pending == true ||
                    targetCode != null ||
                    hiddenReason != null))) {
      throw const BridgeFormatException('Conflicting public runtime facts.');
    }
    final image = row['avatarImageData'];
    final target = row['profileTargetRef'];
    final self = row['isSelf'];
    if (self != null && (self != true || !linked)) {
      throw const BridgeFormatException('Invalid self member.');
    }
    if (linked
        ? row['starBridgeConnected'] != true ||
              row['avatarUrl'] != null ||
              target != reference ||
              image != null &&
                  (image is! String ||
                      image.length > 4096 ||
                      boundedInlineAvatar(image) == null)
        : row['starBridgeConnected'] != null ||
              image != null ||
              target != null ||
              restricted && row['avatarUrl'] != null) {
      throw const BridgeFormatException('Conflicting member identity fields.');
    }
    final avatar = wire.optionalString(row, 'avatarUrl');
    if (avatar != null) {
      final uri = Uri.tryParse(avatar);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const BridgeFormatException('Invalid member avatar.');
      }
    }
    members.add(
      OfficialFleetMember(
        memberRef: reference,
        callsign: restricted ? '' : wire.requiredString(row, 'callsign'),
        gameId: '',
        avatarUrl: avatar,
        identityState: identityState,
        avatarImageData: image as String?,
        profileTargetRef: target as String?,
        isSelf: self == true,
        officialRankName: wire.optionalString(row, 'officialRankName'),
        officialRankValue: null,
        presence: runtime
            ? OfficialFleetMemberPresence.values.byName(
                row['presence'] == 'online'
                    ? 'online'
                    : row['presence'] as String,
              )
            : OfficialFleetMemberPresence.unknown,
        starBridgeConnected: linked ? true : null,
        server: server,
        ship: ship,
        location: location,
        serverRegion: region,
        hasServerSession: hasSession as bool?,
        locationHiddenReason: hiddenReason,
        arrivalTargetCode: targetCode,
        arrivalPending: pending as bool,
      ),
    );
  }
  return OfficialFleetMemberDirectorySnapshot.available(
    query: query,
    members: members,
    totalCount: total,
    totalPages: pages,
    onlineCount: null,
    inGameCount: null,
    coverage: OfficialFleetRosterCoverage.scmRegisteredMembers,
    // Only the successful schema2 handshake supplies these four runtime
    // columns. Neither identity linkage nor a transport capability supplies
    // counts or additional filters; schema1 remains identity-only.
    runtimeCapabilities: runtime
        ? const OfficialFleetMemberRuntimeCapabilities(
            presence: true,
            server: true,
            ship: true,
            location: true,
          )
        : const OfficialFleetMemberRuntimeCapabilities.none(),
  );
}
