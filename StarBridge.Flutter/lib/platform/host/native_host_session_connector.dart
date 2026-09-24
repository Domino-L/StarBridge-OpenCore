import 'dart:math';

import '../bridge/bridge_client_session.dart';
import '../bridge/bridge_envelope.dart';
import 'native_host_connector.dart';

final class NativeHostSessionConnector implements NativeHostConnector {
  NativeHostSessionConnector({required this._platform, Random? random})
    : _random = random ?? Random.secure();

  static const _requiredCapabilities = [
    'host.lifecycle',
    'account.read',
    'account.lifecycle',
    'officialFleet.read',
    'applicationPreferences.read',
    'applicationPreferences.write',
  ];

  final NativeHostPlatformPort _platform;
  final Random _random;

  @override
  Future<NativeHostLease> open() async {
    final platformLease = await _platform.start(pipeName: _createPipeName());
    BridgeClientSession? session;
    try {
      session = BridgeClientSession(
        connection: platformLease.connection,
        sessionGeneration: 0,
      );
      final hello = await session.request(
        'host.hello',
        payload: const {
          'protocols': {'minimum': 1, 'maximum': 1},
          'capabilities': [
            ..._requiredCapabilities,
            'diagnostics.safeSummary',
            'diagnostics.dataLocation',
            'diagnostics.openDataDirectory',
            'dataLocation.chooseMigration',
            'dataLocation.confirmMigration',
            'dataLocation.getMigrationResult',
            'dataLocation.acknowledgeMigrationResult',
            'gameplayTime.export',
            'account.compatibility.read',
            'account.passwordRecovery',
            'account.legacyLogin',
            'account.legacySession',
            'account.compatibility.linkExisting',
            'partyRooms.read',
            'friends.read',
            'communities.read',
            'communities.commands',
            'communities.create',
            'communities.workspace',
            'communities.logs',
            'communities.deleteLog',
            'communities.disbandPreview',
            'communities.chat',
            'communities.announcements',
            'communities.ships',
            'communities.hangarSharing',
            'communities.saveHangarSharing',
            'communities.shipImage',
            'communities.reportShipImage',
            'communities.announcementDetail',
            'communities.manageAnnouncements',
            'communities.chatDetail',
            'communities.markChatRead',
            'communities.sendChat',
            'communities.disband',
            'communities.media',
            'communities.profile',
            'communities.roles',
            'communities.saveRoles',
            'communities.memberRole',
            'communities.saveMemberRole',
            'communities.memberRemoval',
            'communities.removeMember',
            'communities.ownershipTransfer',
            'communities.transferOwnership',
            'communities.ownershipExit',
            'communities.leaveWithSuccessor',
            'communities.invites',
            'communities.sendInvite',
            'communities.admissions',
            'communities.manageAdmissions',
            'communities.logo',
            'friends.commands',
            'directMessages.read',
            'directMessages.send',
            'directMessages.markRead',
            'directMessages.privacyRead',
            'overlayScenes.read',
            'overlayScenes.select',
            'overlayScenes.focusCommunity',
            'directMessages.privacyWrite',
            'friendRequests.privacyRead',
            'friendRequests.privacyWrite',
            'recentlyPlayed.privacyRead',
            'recentlyPlayed.privacyWrite',
            'notificationAudio.read',
            'notificationSettings.read',
            'notificationSettings.save',
            'notificationSettings.presentDesktop',
            'notificationSettings.testDesktop',
            'notificationSettings.clearDesktop',
            'notificationSettings.consumeActivation',
            'notificationAudio.save',
            'notificationAudio.preview',
            'notificationAudio.stop',
            'partyRooms.commands',
            'partyRooms.manage',
            'partyRooms.invitations',
            'partyRooms.chat',
            'partyRooms.chatAttachments',
            'privacy.local',
            'privacy.publication',
            'overlay.presetSharing',
          ],
        },
      );
      final handshake = _validateHello(hello);
      session.acceptHostCapabilities(
        (hello.payload['hostCapabilities'] as List).whereType<String>(),
      );
      if (handshake.sessionGeneration > session.activeGeneration) {
        session.advanceGeneration(handshake.sessionGeneration);
      }
      final ready = await session.request('host.ready');
      _validateReady(ready, handshake.hostInstanceId);
      return _NativeHostLease(session, platformLease);
    } on Object {
      if (session != null) {
        await session.close();
      }
      await platformLease.close();
      rethrow;
    }
  }

  String _createPipeName() {
    final nonce = List.generate(
      4,
      (_) => _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
    ).join();
    return 'starbridge-flutter-$nonce';
  }

  static _HostHandshake _validateHello(BridgeEnvelope envelope) {
    final payload = envelope.payload;
    final selectedProtocol = payload['selectedProtocol'];
    final generation = payload['sessionGeneration'];
    final hostInstanceId = payload['hostInstanceId'];
    final maximumFrameBytes = payload['maximumFrameBytes'];
    final capabilities = payload['hostCapabilities'];
    if (selectedProtocol != BridgeProtocol.currentVersion ||
        generation is! int ||
        generation < 0 ||
        hostInstanceId is! String ||
        hostInstanceId.isEmpty ||
        maximumFrameBytes != BridgeProtocol.maximumFrameBytes ||
        capabilities is! List) {
      throw const NativeHostConnectionException('host.handshake_invalid');
    }
    final capabilitySet = capabilities.whereType<String>().toSet();
    if (!_requiredCapabilities.every(capabilitySet.contains)) {
      throw const NativeHostConnectionException('host.capability_missing');
    }
    return _HostHandshake(
      hostInstanceId: hostInstanceId,
      sessionGeneration: generation,
    );
  }

  static void _validateReady(
    BridgeEnvelope envelope,
    String expectedHostInstanceId,
  ) {
    final payload = envelope.payload;
    if (payload['ready'] != true ||
        payload['hostInstanceId'] != expectedHostInstanceId) {
      throw const NativeHostConnectionException('host.ready_invalid');
    }
  }
}

final class _HostHandshake {
  const _HostHandshake({
    required this.hostInstanceId,
    required this.sessionGeneration,
  });

  final String hostInstanceId;
  final int sessionGeneration;
}

final class _NativeHostLease implements NativeHostLease {
  _NativeHostLease(this.session, this._platformLease);

  @override
  final BridgeClientSession session;
  final NativeHostPlatformLease _platformLease;
  bool _closed = false;

  @override
  Future<NativeHostTermination> get terminated => _platformLease.terminated;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await session.close();
    await _platformLease.close();
  }
}
