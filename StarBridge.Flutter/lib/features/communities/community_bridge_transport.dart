import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'communities_module.dart';
import 'community_own_avatar.dart';
import 'community_ships_port.dart';

/// Shared account-scoped request lifecycle for all organization operations.
abstract class CommunityBridgeTransport
    implements
        CommunitiesPort,
        CommunityOwnAvatarSource,
        CommunityShipsRefreshPort {
  CommunityBridgeTransport(this.session, {this.ownAvatar}) {
    _subscription = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'account.avatarChanged' ||
          event.name == 'bootstrap.invalidated') {
        _invalidate();
      }
      if (event.name == 'hangarReader.changed' && !_closed) {
        _shipRefreshes.add(null);
      }
    }, onDone: _invalidate);
  }
  final BridgeClientSession session;
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
  void _invalidate() {
    _epoch++;
    for (final operation in _pending.toList()) {
      unawaited(operation.cancel());
    }
    _pending.clear();
    if (!_closed) _changes.add(null);
  }

  @override
  Stream<void> get invalidations => _changes.stream;

  bool get isClosed => _closed;
  int get requestEpoch => _epoch;

  Future<Map<String, Object?>> sendRequest(
    String name,
    Map<String, Object?> payload,
  ) async {
    final epoch = _epoch;
    final capability = switch (name) {
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
      'communities.announcementDetail' => 'communities.announcementDetail',
      'communities.manageAnnouncements' => 'communities.manageAnnouncements',
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
      'communities.leaveWithSuccessor' => 'communities.leaveWithSuccessor',
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
    final accountRequest = session.beginRequest(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    _pending.add(accountRequest);
    final account = await accountRequest.future.whenComplete(
      () => _pending.remove(accountRequest),
    );
    if (_closed ||
        epoch != _epoch ||
        account.payload['schemaVersion'] != 1 ||
        !hasRelayAccount(account) ||
        account.accountContext == null) {
      throw const CommunityFailure('identityUnavailable');
    }
    final commandRequest = session.beginRequest(
      name,
      timeout: name == 'communities.pickLogo'
          ? const Duration(minutes: 5)
          : name == 'communities.sendInvite' ||
                name == 'communities.resumeInvite'
          ? const Duration(seconds: 75)
          : name == 'communities.ships'
          ? const Duration(seconds: 45)
          : name == 'communities.execute' || name == 'communities.hangarSharing'
          ? const Duration(seconds: 45)
          : null,
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
        'communities.identityUnavailable' ||
        'account.reauthorization_required' => 'identityUnavailable',
        'communities.dataInvalid' => 'dataInvalid',
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
    _closed = true;
    _invalidate();
    await _subscription.cancel();
    await _changes.close();
    await _shipRefreshes.close();
  }
}
