import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'local_privacy_settings.dart';
import 'local_privacy_port.dart';
import 'privacy_publication_port.dart';
import 'community_sharing.dart';
import 'community_member_sharing.dart';

/// Local settings and an independently consented, Host-owned publication channel.
final class BridgeLocalPrivacy
    implements
        LocalPrivacyPort,
        LocationConfidencePrivacyPort,
        PrivacyPublicationPort,
        CommunitySharingPort,
        CommunityMemberSharingPort {
  BridgeLocalPrivacy(this._session) {
    _events = _session.events.listen((event) {
      if (const {
        'account.changed',
        'bootstrap.invalidated',
      }.contains(event.name)) {
        _epoch++;
        _lease = null;
        _pending = null;
        _invalidations.add(null);
      }
    });
  }
  final BridgeClientSession _session;
  late final StreamSubscription<BridgeEnvelope> _events;
  final _invalidations = StreamController<void>.broadcast();
  final _random = Random.secure();
  _PrivacyLease? _lease;
  ({String settings, String operation})? _pending;
  int _epoch = 0;
  bool _closed = false;
  bool _saving = false;
  @override
  Stream<void> get invalidations => _invalidations.stream;

  @override
  bool get locationConfidenceSupported =>
      _session.hostCapabilities.contains('privacy.locationConfidence');

  @override
  bool get communitySharingSupported =>
      _session.hostCapabilities.contains('privacy.communityScopes');

  @override
  bool get communityMemberSharingSupported =>
      _session.hostCapabilities.contains('privacy.communityMemberScopes');

  @override
  Future<CommunityMemberPage> readCommunityMembers(
    CommunitySharingScope scope, {
    int offset = 0,
    String? revision,
  }) async {
    _requireAvailable();
    if (!communityMemberSharingSupported) {
      throw const BridgeClientException('host.capability_missing');
    }
    final epoch = _epoch;
    final account = await _account();
    _requireCurrent(epoch, account.sessionGeneration);
    final response = await _session.request(
      'privacy.communityMembers',
      accountContext: account.accountContext,
      payload: {
        'schemaVersion': 3,
        'scope': scope.toJson(),
        'offset': offset,
        'revision': revision,
      },
    );
    _requireCurrent(epoch, account.sessionGeneration);
    if (!_sameOwner(response.accountContext, account.accountContext!) ||
        response.sessionGeneration != account.sessionGeneration) {
      throw const BridgeClientException('privacy_local.account_changed');
    }
    return CommunityMemberPage.fromJson(
      response.payload,
      scope,
      offset,
      revision,
    );
  }

  @override
  Future<CommunitySharingTargets> readCommunityTargets() async {
    _requireAvailable();
    if (!communitySharingSupported) {
      throw const BridgeClientException('host.capability_missing');
    }
    final epoch = _epoch;
    final account = await _account();
    _requireCurrent(epoch, account.sessionGeneration);
    final response = await _session.request(
      'privacy.communityTargets',
      accountContext: account.accountContext,
      payload: const {'schemaVersion': 1},
    );
    _requireCurrent(epoch, account.sessionGeneration);
    if (!_sameOwner(response.accountContext, account.accountContext!) ||
        response.sessionGeneration != account.sessionGeneration) {
      throw const BridgeClientException('privacy_local.account_changed');
    }
    return CommunitySharingTargets.fromJson(response.payload);
  }

  @override
  bool get publicationSupported =>
      _session.hostCapabilities.contains('privacy.publication');

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    _requireAvailable();
    if (!publicationSupported) {
      throw const BridgeClientException('host.capability_missing');
    }
    final lease = _lease;
    if (lease == null) {
      throw const BridgeClientException('privacy_local.refresh_required');
    }
    final name = switch (action) {
      'status' => 'privacy.publicationStatus',
      'apply' => 'privacy.applyPublication',
      'stop' => 'privacy.stopPublication',
      _ => throw ArgumentError.value(action),
    };
    if (action == 'apply' && revision != lease.revision) {
      throw const BridgeClientException('privacy_local.refresh_required');
    }
    final account = await _account();
    _requireCurrent(lease.epoch, lease.generation);
    if (!_sameOwner(account.accountContext, lease.owner) ||
        !identical(lease, _lease)) {
      throw const BridgeClientException('privacy_local.account_changed');
    }
    final response = await _session.request(
      name,
      timeout: action == 'status' ? null : const Duration(seconds: 45),
      accountContext: lease.owner,
      payload: {
        'schemaVersion': 1,
        if (action == 'apply') 'expectedRevision': revision,
      },
    );
    _requireCurrent(lease.epoch, lease.generation);
    final body = response.payload;
    if (!_sameOwner(response.accountContext, lease.owner) ||
        response.sessionGeneration != lease.generation ||
        body['schemaVersion'] != 1 ||
        body['supportedFields'] != 15 ||
        !const {
          'inactive',
          'identityRequired',
          'publishing',
          'pending',
          'applied',
          'withdrawn',
          'failed',
          'withdrawalPending',
          'reconnecting',
        }.contains(body['state']) ||
        (body['appliedRevision'] != null && body['appliedRevision'] is! int) ||
        (body['errorCode'] != null &&
            (body['errorCode'] is! String ||
                (body['errorCode'] as String).length > 128)) ||
        (body['firstUseRequired'] != null &&
            body['firstUseRequired'] is! bool)) {
      throw const FormatException('Unconfirmed publication status.');
    }
    return PrivacyPublicationView(
      body['state'] as String,
      revision: body['appliedRevision'] as int?,
      firstUseRequired: body['firstUseRequired'] as bool?,
      errorCode: body['errorCode'] as String?,
    );
  }

  @override
  Future<LocalPrivacySnapshot> read() async {
    _requireAvailable();
    final epoch = ++_epoch;
    _lease = null;
    _pending = null;
    final account = await _account();
    _requireCurrent(epoch, account.sessionGeneration);
    final response = await _session.request(
      'privacy.localRead',
      payload: const {'schemaVersion': 1},
      accountContext: account.accountContext,
    );
    _requireCurrent(epoch, account.sessionGeneration);
    final snapshot = _parse(
      response,
      account.accountContext!,
      account.sessionGeneration,
    );
    _lease = _PrivacyLease(
      account.accountContext!,
      account.sessionGeneration,
      epoch,
      snapshot.revision,
    );
    return snapshot;
  }

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) async {
    _requireAvailable();
    if (settings.hideLowConfidenceLocation != null &&
        !locationConfidenceSupported) {
      throw const BridgeClientException('host.capability_missing');
    }
    final lease = _lease;
    if (lease == null) {
      throw const BridgeClientException('privacy_local.refresh_required');
    }
    if (_saving) throw const BridgeClientException('privacy_local.busy');
    _saving = true;
    try {
      final account = await _account();
      _requireCurrent(lease.epoch, lease.generation);
      if (!identical(lease, _lease) ||
          !_sameOwner(account.accountContext, lease.owner) ||
          account.sessionGeneration != lease.generation) {
        throw const BridgeClientException('privacy_local.account_changed');
      }
      final encoded = jsonEncode(settings.toJson());
      if (_pending?.settings != encoded) {
        _pending = (
          settings: encoded,
          operation: List.generate(
            16,
            (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join(),
        );
      }
      final operation = _pending!.operation;
      final response = await _session.request(
        'privacy.localSave',
        accountContext: lease.owner,
        payload: {
          'schemaVersion': 1,
          'expectedRevision': lease.revision,
          'operationId': operation,
          'settings': settings.toJson(),
        },
      );
      _requireCurrent(lease.epoch, lease.generation);
      if (!identical(_lease, lease)) {
        throw const BridgeClientException('privacy_local.account_changed');
      }
      final snapshot = _parse(response, lease.owner, lease.generation);
      if (snapshot.revision != lease.revision + 1 ||
          response.payload['operationId'] != operation ||
          jsonEncode(snapshot.settings?.toJson()) != encoded) {
        throw const FormatException('Unconfirmed privacy save.');
      }
      _lease = _PrivacyLease(
        lease.owner,
        lease.generation,
        lease.epoch,
        snapshot.revision,
      );
      _pending = null;
      return snapshot;
    } on BridgeClientException catch (error) {
      if (const {
        'privacy_local.conflict',
        'privacy_local.account_changed',
        'bridge.stale_generation',
      }.contains(error.code)) {
        _lease = null;
        _pending = null;
      }
      rethrow;
    } finally {
      _saving = false;
    }
  }

  Future<BridgeEnvelope> _account() async {
    final response = await _session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (response.payload['schemaVersion'] != 1 ||
        !hasRelayAccount(response) ||
        response.accountContext == null) {
      throw const BridgeClientException('privacy_local.account_changed');
    }
    return response;
  }

  void _requireAvailable() {
    if (_closed) throw const BridgeDisconnectedException();
    if (!_session.hostCapabilities.contains('privacy.local')) {
      throw const BridgeClientException('host.capability_missing');
    }
  }

  void _requireCurrent(int epoch, int generation) {
    if (_closed || epoch != _epoch || generation != _session.activeGeneration) {
      throw const BridgeClientException('privacy_local.account_changed');
    }
  }

  static LocalPrivacySnapshot _parse(
    BridgeEnvelope response,
    BridgeAccountContext owner,
    int generation,
  ) {
    final body = response.payload;
    if (!_sameOwner(response.accountContext, owner) ||
        response.sessionGeneration != generation ||
        body['schemaVersion'] != 1 ||
        body['publicationAvailable'] != false) {
      throw const FormatException('Invalid privacy response scope.');
    }
    final revision = body['revision'] as int;
    final settings = body['settings'] == null
        ? null
        : LocalPrivacySettings.fromJson(
            (body['settings'] as Map).cast<String, Object?>(),
          );
    final savedAt = DateTime.tryParse(body['savedAt'] as String? ?? '');
    if (revision < 0 ||
        (revision == 0) != (settings == null) ||
        (revision == 0 &&
            (body['savedAt'] != null || body['operationId'] != null)) ||
        (revision > 0 &&
            (savedAt == null ||
                savedAt.isBefore(DateTime.utc(1970)) ||
                !RegExp(r'^[0-9a-fA-F]{32}$')
                    .hasMatch(body['operationId'] as String? ?? '')))) {
      throw const FormatException('Invalid local privacy revision.');
    }
    return LocalPrivacySnapshot(
      revision: revision,
      savedAt: savedAt,
      settings: settings,
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    _epoch++;
    _lease = null;
    _pending = null;
    await _events.cancel();
    await _invalidations.close();
  }

  static bool _sameOwner(BridgeAccountContext? a, BridgeAccountContext b) =>
      a?.environment == b.environment &&
      a?.authority == b.authority &&
      a?.subject == b.subject;
}

final class _PrivacyLease {
  const _PrivacyLease(this.owner, this.generation, this.epoch, this.revision);
  final BridgeAccountContext owner;
  final int generation;
  final int epoch;
  final int revision;
}
