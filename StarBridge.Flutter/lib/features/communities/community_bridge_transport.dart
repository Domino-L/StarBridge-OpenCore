import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../onboarding/connection_mode_port.dart';
import 'communities_module.dart';
import 'community_own_avatar.dart';
import 'community_ships_port.dart';
import 'community_activity.dart';
import 'community_activity_port.dart';

/// Shared account-scoped request lifecycle for all organization operations.
abstract class CommunityBridgeTransport
    implements
        CommunitiesPort,
        CommunityOwnAvatarSource,
        CommunityActivityPort,
        CommunityShipsRefreshPort {
  CommunityBridgeTransport(
    this.session, {
    this.ownAvatar,
    this.connectionMode,
  }) {
    _activity = CommunityActivity(
      session,
      onlineAllowed: () => onlineTrafficAllowed,
    );
    _subscription = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'account.avatarChanged' ||
          event.name == 'bootstrap.invalidated') {
        invalidateReadScope();
      }
      if (event.name == 'hangarReader.changed' && !_closed) {
        _shipRefreshes.add(null);
      }
    }, onDone: invalidateReadScope);
    connectionMode?.addListener(_modeChanged);
    _modeChanged();
  }
  final BridgeClientSession session;
  final ConnectionModeControl? connectionMode;
  (Object, int?, ConnectionModeState, bool, bool)? _modeKey;
  void _modeChanged() {
    final mode = connectionMode;
    if (mode == null) return;
    final value = mode.snapshot;
    final next = (
      value.scope,
      value.revision,
      value.state,
      mode.failed,
      mode.allowsOnlineTraffic,
    );
    if (next == _modeKey) return;
    _modeKey = next;
    invalidateReadScope(notify: connectionModeInvalidatesDisplay);
    _activity.reconcileAdmission();
  }

  // Scoped communication keeps same-owner drafts on transport-mode changes.
  // Requests are still retired and mode-gated; account invalidation is unchanged.
  bool get connectionModeInvalidatesDisplay => true;
  bool get onlineTrafficAllowed => connectionMode?.allowsOnlineTraffic != false;
  late final CommunityActivity _activity;
  void configureOfficialActivity(String source, {required bool available}) =>
      _activity.configureOfficialFleet(source, available: available);
  Stream<String> get activityReadErrors => _activity.errors.stream;
  @override
  Stream<void> get workspaceChanges => _activity.changes.stream;
  @override
  bool get activityHealthy => _activity.healthy;
  final String? Function()? ownAvatar;
  @override
  String? get ownAvatarImageData => _closed ? null : ownAvatar?.call();
  final _changes = StreamController<void>.broadcast();
  final _shipRefreshes = StreamController<void>.broadcast();
  @override
  Stream<void> get shipRefreshes => _shipRefreshes.stream;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  final _pending = <BridgeRequestOperation>{};
  int _epoch = 0;
  bool _closed = false;

  /// Retire pending operations before publishing a replacement display scope.
  /// A same-owner cached selection renews presentation through its own stream.
  void invalidateReadScope({bool notify = true}) {
    _epoch++;
    for (final operation in _pending.toList()) {
      unawaited(operation.cancel());
    }
    _pending.clear();
    if (!_closed && notify) _changes.add(null);
  }

  @override
  Stream<void> get invalidations => _changes.stream;

  bool get isClosed => _closed;
  int get requestEpoch => _epoch;

  static const _officialAnnouncementCommands = {
    'officialFleet.readAnnouncementEditor',
    'officialFleet.manageAnnouncements',
    'officialFleet.readAnnouncementOutcome',
  };
  static const _officialGovernanceManagementCommands = {
    'officialFleet.readRankPolicy',
    'officialFleet.writeRankPolicy',
    'officialFleet.readMemberRoles',
    'officialFleet.assignRole',
    'officialFleet.revokeRole',
    'officialFleet.updateRolePermissions',
    'officialFleet.readGovernanceAudit',
    'officialFleet.readRoleTemplates',
    'officialFleet.manageRoleTemplates',
    'officialFleet.readRoleTemplateOutcome',
    'officialFleet.getMembers',
  };

  /// Protocol support only. sendRequest still requires fresh account admission.
  bool supportsOfficialAnnouncementCommand(String name) =>
      !_closed &&
      _officialAnnouncementCommands.contains(name) &&
      session.hostCapabilities.contains(name);

  Future<Map<String, Object?>> readLocalDisplay(
    String name,
    Map<String, Object?> payload,
  ) async {
    if (_closed ||
        !const {
          'onboarding.mode.communities',
          'onboarding.mode.communityMedia',
          'account.offlineData.read',
        }.contains(name)) {
      throw const CommunityFailure('offlineCacheUnavailable');
    }
    final epoch = _epoch, generation = session.activeGeneration;
    final operation = session.beginRequest(
      name,
      payload: {'schemaVersion': 1, ...payload},
    );
    _pending.add(operation);
    final response = await operation.future.whenComplete(
      () => _pending.remove(operation),
    );
    if (_closed ||
        epoch != _epoch ||
        generation != session.activeGeneration ||
        response.sessionGeneration != generation ||
        response.accountContext != null) {
      throw const CommunityFailure('identityUnavailable');
    }
    return response.payload;
  }

  Future<Map<String, Object?>> sendRequest(
    String name,
    Map<String, Object?> payload, {
    Duration? timeout,
    bool Function()? officialAnnouncementCurrent,
  }) async {
    final officialAnnouncement = _officialAnnouncementCommands.contains(name);
    if (officialAnnouncementCurrent != null && !officialAnnouncement) {
      throw ArgumentError.value(name, 'name');
    }
    final epoch = _epoch;
    final clock = Stopwatch()..start();
    Duration? remaining() => timeout == null
        ? null
        : timeout - clock.elapsed > Duration.zero
        ? timeout - clock.elapsed
        : const Duration(microseconds: 1);
    final capability = name == 'officialFleet.getMembers'
        ? 'officialFleet.read'
        : _officialGovernanceManagementCommands.contains(name)
        ? name
        : switch (name) {
            'officialFleet.readAnnouncementEditor' ||
            'officialFleet.manageAnnouncements' ||
            'officialFleet.readAnnouncementOutcome' => name,
            'officialFleet.communication' => 'officialFleet.communication',
            'officialFleet.ships' => 'officialFleet.ships',
            'officialFleet.shipImage' => 'officialFleet.shipImage',
            'officialFleet.reportShipImage' => 'officialFleet.reportShipImage',
            'officialFleet.shipImageReportStatus' =>
              'officialFleet.shipImageReportStatus',
            'officialFleet.readGovernanceContext' ||
            'officialFleet.governance.activate' ||
            'officialFleet.governance.revokeActivation' =>
              'officialFleet.readGovernanceContext',
            'communities.read' => 'communities.read',
            'communities.workspace' => 'communities.workspace',
            'communities.memberPersonalProfile' =>
              'communities.memberPersonalProfile',
            'communities.logs' => 'communities.logs',
            'communities.deleteLog' => 'communities.deleteLog',
            'communities.disbandPreview' => 'communities.disbandPreview',
            'communities.disband' => 'communities.disband',
            'communities.chat' => 'communities.chat',
            'communities.announcements' => 'communities.announcements',
            'communities.ships' => 'communities.ships',
            'communities.hangarSharing' => 'communities.hangarSharing',
            'communities.saveHangarSharing' => 'communities.saveHangarSharing',
            'communities.shipImage' => 'communities.shipImage',
            'communities.reportShipImage' => 'communities.reportShipImage',
            'communities.announcementDetail' =>
              'communities.announcementDetail',
            'communities.manageAnnouncements' =>
              'communities.manageAnnouncements',
            'communities.chatDetail' => 'communities.chatDetail',
            'communities.markChatRead' => 'communities.markChatRead',
            'communities.sendChat' => 'communities.sendChat',
            'overlay.getWorkspace' ||
            'overlay.updateWorkspace' => 'overlay.presetSharing',
            'communities.admissions' => 'communities.admissions',
            'communities.manageAdmissions' => 'communities.manageAdmissions',
            'communities.media' => 'communities.media',
            'communities.previewInvite' ||
            'communities.acceptInvite' => 'communities.invites',
            'communities.sendInvite' ||
            'communities.resumeInvite' ||
            'communities.invitationOutbox' => 'communities.sendInvite',
            'communities.profile' ||
            'communities.saveProfile' => 'communities.profile',
            'communities.roles' => 'communities.roles',
            'communities.saveRoles' => 'communities.saveRoles',
            'communities.memberRole' => 'communities.memberRole',
            'communities.saveMemberRole' => 'communities.saveMemberRole',
            'communities.memberRemoval' => 'communities.memberRemoval',
            'communities.removeMember' => 'communities.removeMember',
            'communities.ownershipTransfer' => 'communities.ownershipTransfer',
            'communities.transferOwnership' => 'communities.transferOwnership',
            'communities.ownershipExit' => 'communities.ownershipExit',
            'communities.leaveWithSuccessor' =>
              'communities.leaveWithSuccessor',
            'communities.create' ||
            'communities.creationOptions' => 'communities.create',
            'communities.pickLogo' ||
            'communities.cropLogo' ||
            'communities.clearLogo' => 'communities.logo',
            _ => 'communities.commands',
          };
    if (_closed || !session.hostCapabilities.contains(capability)) {
      throw const CommunityFailure('unavailable');
    }
    if (!onlineTrafficAllowed) {
      if (connectionMode?.failed == false &&
          const {
            ConnectionModeState.offline,
            ConnectionModeState.local,
            ConnectionModeState.signInRequired,
            ConnectionModeState.recoveryRequired,
          }.contains(connectionMode?.snapshot.state)) {
        throw const BridgeClientException('account.local_mode');
      }
      throw const CommunityFailure('unavailable');
    }
    final accountRequest = session.beginRequest(
      'account.getCurrent',
      timeout: remaining(),
      payload: const {'schemaVersion': 1},
    );
    _pending.add(accountRequest);
    final account = await accountRequest.future.whenComplete(
      () => _pending.remove(accountRequest),
    );
    if (_closed ||
        epoch != _epoch ||
        account.payload['schemaVersion'] != 1 ||
        (officialAnnouncement ||
                _officialGovernanceManagementCommands.contains(name) ||
                name.startsWith('officialFleet.governance.') ||
                name == 'officialFleet.readGovernanceContext'
            ? account.payload['state'] != 'signedIn'
            : !hasRelayAccount(account)) ||
        account.accountContext == null) {
      throw const CommunityFailure('identityUnavailable');
    }
    // Only the three official announcement commands have this local fence.
    // This synchronous checkpoint is after the one account read and before
    // beginRequest can possibly dispatch the command. No await belongs here.
    if (officialAnnouncement &&
        (!session.hostCapabilities.contains(capability) ||
            officialAnnouncementCurrent?.call() != true)) {
      throw const OfficialAnnouncementNotDispatched._();
    }
    final commandRequest = session.beginRequest(
      name,
      timeout:
          remaining() ??
          (name == 'communities.pickLogo' ||
                  name == 'communities.saveHangarSharing' &&
                      payload['includeImages'] == true
              ? const Duration(minutes: 5)
              : name == 'communities.sendInvite' ||
                    name == 'communities.resumeInvite'
              ? const Duration(seconds: 75)
              : name == 'communities.ships'
              ? const Duration(seconds: 45)
              : name == 'communities.execute' ||
                    name == 'communities.hangarSharing'
              ? const Duration(seconds: 45)
              : null),
      // Overlay is device-local and rejects accountContext. Still gate its
      // initiation and late response with the surrounding account/epoch checks.
      accountContext:
          name == 'overlay.getWorkspace' || name == 'overlay.updateWorkspace'
          ? null
          : account.accountContext,
      payload: {'schemaVersion': 1, ...payload},
    );
    _pending.add(commandRequest);
    final response = await commandRequest.future.whenComplete(
      () => _pending.remove(commandRequest),
    );
    if (_closed || epoch != _epoch) {
      throw const CommunityFailure('identityUnavailable');
    }
    if (response.payload['schemaVersion'] != 1) throw const FormatException();
    return response.payload;
  }

  Future<T> workspaceRead<T>(
    Future<T> Function() read, {
    bool media = false,
  }) async {
    try {
      return await read();
    } on FormatException {
      throw const CommunityFailure('dataInvalid');
    } on TypeError {
      throw const CommunityFailure('dataInvalid');
    } on BridgeClientException catch (e) {
      throw CommunityFailure(switch (e.code) {
        'communities.notAllowed' => 'notAllowed',
        'communities.notFound' => media ? 'notFound' : 'notAllowed',
        'communities.refreshRequired' => 'refreshRequired',
        'official_fleet.identity_unavailable' ||
        'communities.identityUnavailable' ||
        'account.reauthorization_required' => 'identityUnavailable',
        'communities.dataInvalid' => 'dataInvalid',
        'membershipEvidenceStale' => 'membershipEvidenceStale',
        'communities.mediaChanged' => 'mediaChanged',
        'communities.announcementsChanged' => 'announcementsChanged',
        'communities.shipsChanged' => 'shipsChanged',
        'communities.upgradeRequired' => 'upgradeRequired',
        'communities.inviteInvalid' => 'inviteInvalid',
        'communities.localRecoveryUnavailable' => 'localRecoveryUnavailable',
        _ => 'unavailable',
      });
    }
  }

  @override
  Future<void> close() async {
    connectionMode?.removeListener(_modeChanged);
    _closed = true;
    invalidateReadScope();
    await _subscription.cancel();
    await _activity.close();
    await _changes.close();
    await _shipRefreshes.close();
  }
}

/// A local proof that the official announcement command was not dispatched.
/// Only this library's final pre-command checkpoint can construct this type.
final class OfficialAnnouncementNotDispatched extends BridgeClientException {
  const OfficialAnnouncementNotDispatched._()
    : super('bridge.official_announcement_not_dispatched');
}
