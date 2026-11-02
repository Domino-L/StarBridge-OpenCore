import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'local_privacy_settings.dart';
import 'local_privacy_port.dart';
import 'privacy_publication_port.dart';
import 'community_sharing.dart';
import 'community_member_sharing.dart';
import 'official_runtime_privacy_port.dart';

/// Local settings and an independently consented, Host-owned publication channel.
final class BridgeLocalPrivacy
    implements
        LocalPrivacyPort,
        LocationConfidencePrivacyPort,
        PrivacyPublicationPort,
        PrivacyPublicationChangePort,
        CommunitySharingPort,
        CommunityMemberSharingPort,
        OfficialRuntimePrivacyPort {
  BridgeLocalPrivacy(
    this._session, {
    this.officialSourceChanges,
    this.officialContextRevision,
  }) {
    _events = _session.events.listen((event) {
      if (const {
        'account.changed',
        'bootstrap.invalidated',
      }.contains(event.name)) {
        _epoch++;
        _lease = null;
        _pending = null;
        _invalidateOfficial();
        _invalidations.add(null);
      } else if (event.name == 'privacy.publicationChanged' &&
          event.sessionGeneration == _session.activeGeneration) {
        _publicationChanges.add(null);
      }
    });
    _unobserveGeneration = _session.observeGenerationChanges((_, _) {
      _invalidateOfficial();
    });
    _capabilities = _session.capabilitiesChanged.listen(
      (_) => _invalidateOfficial(),
    );
    officialSourceChanges?.addListener(_sourceChanged);
    _sourceRevision = officialContextRevision?.call();
  }
  final BridgeClientSession _session;
  final Listenable? officialSourceChanges;
  final Object? Function()? officialContextRevision;
  Object? _sourceRevision;
  late final VoidCallback _unobserveGeneration;
  late final StreamSubscription<void> _capabilities;
  final _officialInvalidations = StreamController<void>.broadcast();
  OfficialRuntimePrivacySnapshot? _officialSnapshot;
  int _officialEpoch = 0;
  bool _officialSaving = false;
  void _sourceChanged() {
    final next = officialContextRevision?.call();
    if (next == _sourceRevision) return;
    _sourceRevision = next;
    _invalidateOfficial();
  }

  void _invalidateOfficial() {
    _officialEpoch++;
    _officialSnapshot = null;
    if (!_closed) _officialInvalidations.add(null);
  }

  @override
  bool get officialRuntimePrivacySupported =>
      _session.hostCapabilities.contains('privacy.officialFleetScopes');
  @override
  Stream<void> get officialRuntimePrivacyInvalidations =>
      _officialInvalidations.stream;

  @override
  Future<OfficialRuntimePrivacySnapshot> readOfficialRuntimePrivacy() async {
    _requireAvailable();
    if (!officialRuntimePrivacySupported) {
      throw const BridgeClientException('host.capability_missing');
    }
    final lease = _lease;
    if (lease == null || _officialSaving) {
      throw const BridgeClientException('privacy_local.refresh_required');
    }
    final officialEpoch = _officialEpoch;
    _officialSnapshot = null;
    final account = await _account();
    _requireCurrent(lease.epoch, lease.generation);
    if (!_sameOwner(account.accountContext, lease.owner) ||
        !identical(lease, _lease)) {
      throw const BridgeClientException('privacy_local.account_changed');
    }
    final reply = await _session.request(
      'privacy.officialFleetRead',
      accountContext: lease.owner,
      payload: const {'schemaVersion': 1},
    );
    _requireCurrent(lease.epoch, lease.generation);
    if (officialEpoch != _officialEpoch ||
        !identical(lease, _lease) ||
        !_sameOwner(reply.accountContext, lease.owner) ||
        reply.sessionGeneration != lease.generation) {
      throw const BridgeClientException('privacy_local.account_changed');
    }
    final view = OfficialRuntimePrivacySnapshot.parse(reply.payload);
    if (view.revision != lease.revision) {
      throw const BridgeClientException('privacy_local.conflict');
    }
    return _officialSnapshot = view;
  }

  @override
  Future<OfficialRuntimePrivacySaveReceipt> saveOfficialRuntimePrivacy({
    required OfficialRuntimePrivacySnapshot scope,
    required int expectedRevision,
    required int fields,
    required bool cancelSavedScope,
    OfficialFleetAudience? audience,
  }) async {
    _requireAvailable();
    final lease = _lease;
    final reference = cancelSavedScope
        ? scope.cancelContextRef
        : scope.contextRef;
    if (!officialRuntimePrivacySupported ||
        lease == null ||
        _saving ||
        _officialSaving ||
        !identical(scope, _officialSnapshot) ||
        expectedRevision != lease.revision ||
        fields < 0 ||
        fields > 15 ||
        audience != null &&
            (!scope.audienceRankSupported ||
                !OfficialFleetAudience.valid(audience.maximumRankValue)) ||
        reference == null ||
        (cancelSavedScope ? !scope.canCancel || fields != 0 : !scope.canSave)) {
      throw const BridgeClientException('privacy_local.refresh_required');
    }
    final officialEpoch = _officialEpoch;
    final operation = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _officialSaving = true;
    try {
      final account = await _account();
      _requireCurrent(lease.epoch, lease.generation);
      if (officialEpoch != _officialEpoch ||
          !identical(lease, _lease) ||
          !_sameOwner(account.accountContext, lease.owner)) {
        throw const BridgeClientException('privacy_local.account_changed');
      }
      // This command consumes the old local revision. Only a subsequent common
      // localRead can renew the lease used by the one existing publisher.
      _lease = null;
      final reply = await _session.request(
        'privacy.officialFleetSave',
        accountContext: lease.owner,
        payload: {
          'schemaVersion': 1,
          'contextRef': reference,
          'expectedRevision': expectedRevision,
          'operationId': operation,
          'fields': fields,
          // Explicit null selects every member; omitted keeps the old shape.
          if (audience != null) 'maximumRankValue': audience.maximumRankValue,
        },
      );
      _requireCurrent(lease.epoch, lease.generation);
      if (officialEpoch != _officialEpoch ||
          !_sameOwner(reply.accountContext, lease.owner) ||
          reply.sessionGeneration != lease.generation) {
        throw const BridgeClientException('privacy_local.account_changed');
      }
      final body = reply.payload;
      if (body.keys.any(
            (key) => !const {
              'schemaVersion',
              'revision',
              'operationId',
              'fields',
              'state',
              'publicationApplied',
              'maximumRankValue',
            }.contains(key),
          ) ||
          !OfficialFleetAudience.valid(body['maximumRankValue']) ||
          audience != null &&
              body['maximumRankValue'] != audience.maximumRankValue ||
          body['schemaVersion'] != 1 ||
          body['revision'] != expectedRevision + 1 ||
          body['operationId'] != operation ||
          body['fields'] != fields ||
          body['state'] != 'saved' ||
          body['publicationApplied'] != false) {
        throw const FormatException('Unconfirmed official privacy save.');
      }
      return OfficialRuntimePrivacySaveReceipt(
        expectedRevision + 1,
        fields,
        body['maximumRankValue'] as int?,
      );
    } finally {
      _officialSnapshot = null;
      _officialSaving = false;
    }
  }

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

  final _publicationChanges = StreamController<void>.broadcast();
  @override
  bool get publicationEventsSupported =>
      publicationSupported &&
      _session.hostCapabilities.contains('privacy.publicationEvents');
  @override
  Stream<void> get publicationChanges => _publicationChanges.stream;

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
      'applyPreservingPause' => 'privacy.applyPublication',
      'stop' => 'privacy.stopPublication',
      _ => throw ArgumentError.value(action),
    };
    if ((action == 'apply' || action == 'applyPreservingPause') &&
        revision != lease.revision) {
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
        if (action == 'apply' || action == 'applyPreservingPause')
          'expectedRevision': revision,
        if (action == 'applyPreservingPause') 'preservePause': true,
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
    _unobserveGeneration();
    await _capabilities.cancel();
    officialSourceChanges?.removeListener(_sourceChanged);
    _invalidateOfficial();
    await _events.cancel();
    await _invalidations.close();
    await _officialInvalidations.close();
    await _publicationChanges.close();
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
