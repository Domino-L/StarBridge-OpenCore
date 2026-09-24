import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'communities_module.dart';
import 'community_invite_port.dart';
import 'community_invitation_send_port.dart';
import 'community_chat_port.dart';
import 'community_chat_send_port.dart';
import 'community_preset_port.dart';
import 'community_announcements_port.dart';
import 'community_announcement_write_port.dart';

import 'community_bridge_transport.dart';

mixin CommunityBridgeCommunication on CommunityBridgeTransport
    implements
        CommunityPresetPort,
        CommunityInvitePort,
        CommunityInvitationSendPort,
        CommunityAnnouncementsPort,
        CommunityAnnouncementWritePort,
        CommunityChatPort,
        CommunityChatSendPort {
  @override
  bool get communityPresetsAvailable =>
      !isClosed && session.hostCapabilities.contains('overlay.presetSharing');

  Future<T> _presetOperation<T>(
    Future<T> Function() run, {
    bool importing = false,
  }) async {
    try {
      return await run();
    } on BridgeClientException catch (error) {
      throw CommunityFailure(switch (error.code) {
        'overlay.revision_conflict' ||
        'overlay.workspace_revision_conflict' => 'presetChanged',
        'overlay.shared_preset_invalid' => 'presetInvalid',
        _ => importing ? 'presetImportUnknown' : 'unavailable',
      });
    } on Object {
      throw CommunityFailure(importing ? 'presetImportUnknown' : 'unavailable');
    }
  }

  @override
  Future<CommunityPresetCatalog> readCommunityPresets() => _presetOperation(
    () async => CommunityPresetCatalog.parse(
      await sendRequest('overlay.getWorkspace', const {}),
    ),
  );

  @override
  Future<Map<String, Object?>> exportCommunityPreset(String id, int revision) {
    presetText(id, 128);
    if (revision < 0) throw const FormatException();
    return _presetOperation(() async {
      final row = await sendRequest('overlay.updateWorkspace', {
        'action': 'exportSharedPreset',
        'presetId': id,
        'expectedRevision': revision,
      });
      return checkedCommunityPreset(
        Map<String, Object?>.from(row['attachment'] as Map),
      );
    });
  }

  @override
  Future<String> importCommunityPreset(
    Map<String, Object?> attachment,
    int revision,
  ) {
    final checked = checkedCommunityPreset(attachment);
    if (revision < 0) throw const FormatException();
    return _presetOperation(() async {
      final row = await sendRequest('overlay.updateWorkspace', {
        'action': 'importSharedPreset',
        'package': checked['overlayPresetPackage'],
        'expectedRevision': revision,
      });
      presetText(row['presetId'], 128);
      return presetText(row['name'], 64);
    }, importing: true);
  }

  @override
  Future<CommunityInvitePreview> previewInvite(String inviteCode) =>
      workspaceRead(
        () async => CommunityInvitePreview.parse(
          await sendRequest('communities.previewInvite', {
            'inviteCode': inviteCode,
          }),
        ),
      );

  @override
  bool get invitationSendingAvailable =>
      !isClosed && session.hostCapabilities.contains('communities.sendInvite');

  @override
  Future<List<CommunityInvitationOperation>> readInvitationOutbox() =>
      workspaceRead(
        () async => CommunityInvitationOperation.parsePage(
          await sendRequest('communities.invitationOutbox', {}),
        ),
      );

  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) => _invitationSendOperation('communities.sendInvite', operationId, {
    'operationId': operationId,
    'organizationRef': organizationRef,
    'channel': channel,
    'destinationRef': destinationRef,
    'maxUses': maxUses,
    'action': 'advance',
  });

  @override
  Future<CommunityInvitationProgress> resumeInvitation(
    String operationId, {
    String action = 'check',
  }) => _invitationSendOperation('communities.resumeInvite', operationId, {
    'operationId': operationId,
    'action': action,
  });

  Future<CommunityInvitationProgress> _invitationSendOperation(
    String name,
    String operationId,
    Map<String, Object?> data,
  ) async {
    if (!invitationSendingAvailable) {
      return CommunityInvitationProgress(
        operationId,
        'rejected',
        'unavailable',
      );
    }
    try {
      return CommunityInvitationProgress.parse(
        await sendRequest(name, data),
        operationId,
      );
    } on BridgeClientException catch (failure) {
      return CommunityInvitationProgress(
        operationId,
        'unknown',
        failure.code == 'communities.localRecoveryUnavailable'
            ? 'localRecoveryUnavailable'
            : 'outcomeUnknown',
      );
    } catch (_) {
      // Never generate a replacement ID or assume a lost response means failure.
      return CommunityInvitationProgress(
        operationId,
        'unknown',
        'outcomeUnknown',
      );
    }
  }

  @override
  Future<CommunityInviteOutcome> acceptInvite(
    String requestId,
    String previewRef,
  ) async {
    try {
      return CommunityInviteOutcome.parse(
        await sendRequest('communities.acceptInvite', {
          'requestId': requestId,
          'previewRef': previewRef,
        }),
      );
    } on CommunityFailure catch (failure) {
      return failure.code == 'unavailable'
          ? const CommunityInviteOutcome('rejected', error: 'unavailable')
          : const CommunityInviteOutcome('unknown', error: 'outcomeUnknown');
    } catch (_) {
      // A timeout or lost Bridge reply is not evidence that admission failed.
      return const CommunityInviteOutcome('unknown', error: 'outcomeUnknown');
    }
  }

  @override
  bool get announcementsAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.announcements') &&
      session.hostCapabilities.contains('communities.announcementDetail');
  @override
  bool get announcementWritesAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.manageAnnouncements');
  @override
  Future<CommunityAnnouncementOutcome> manageAnnouncement(
    CommunityAnnouncementIntent intent,
  ) async {
    if (!announcementWritesAvailable) {
      return const CommunityAnnouncementOutcome(
        'rejected',
        error: 'unavailable',
      );
    }
    try {
      return CommunityAnnouncementOutcome.parse(
        await sendRequest(
          'communities.manageAnnouncements',
          intent.toPayload(),
        ),
        intent,
      );
    } on BridgeClientException catch (e) {
      if (e.code == 'communities.dataInvalid') {
        return const CommunityAnnouncementOutcome(
          'rejected',
          error: 'dataInvalid',
        );
      }
      return const CommunityAnnouncementOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    } catch (_) {
      return const CommunityAnnouncementOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
  }) => workspaceRead(() async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(targetRef) ||
        offset < 0 ||
        offset > 100 ||
        expectedRevision != null && expectedRevision < 0 ||
        offset > 0 && expectedRevision == null) {
      throw const FormatException();
    }
    final page = CommunityAnnouncementsPage.parse(
      await sendRequest('communities.announcements', {
        'targetRef': targetRef,
        'offset': offset,
        'expectedRevision': expectedRevision,
      }),
    );
    if (page.targetRef != targetRef ||
        page.offset != offset ||
        expectedRevision != null && page.revision != expectedRevision) {
      throw const FormatException();
    }
    return page;
  });
  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version,
  ) => workspaceRead(
    () => sendRequest('communities.announcementDetail', {
      'targetRef': targetRef,
      'announcementRef': announcementRef,
      'offset': offset,
      'version': version,
    }),
  );
  @override
  bool get chatAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.chat') &&
      session.hostCapabilities.contains('communities.chatDetail');
  @override
  bool get chatReadReceiptsAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.markChatRead');
  @override
  bool get chatSendAvailable =>
      !isClosed && session.hostCapabilities.contains('communities.sendChat');
  @override
  Future<CommunityChatSendOutcome> sendChat(
    CommunityChatSendIntent intent,
  ) async {
    if (!chatSendAvailable) {
      return const CommunityChatSendOutcome('rejected', error: 'unavailable');
    }
    try {
      return CommunityChatSendOutcome.parse(
        await sendRequest('communities.sendChat', intent.toPayload()),
        intent,
      );
    } on BridgeClientException catch (e) {
      if (e.code == 'communities.dataInvalid') {
        return const CommunityChatSendOutcome('rejected', error: 'dataInvalid');
      }
      return const CommunityChatSendOutcome('unknown', error: 'outcomeUnknown');
    } catch (_) {
      return const CommunityChatSendOutcome('unknown', error: 'outcomeUnknown');
    }
  }

  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) async {
    if (!chatReadReceiptsAvailable) {
      return const CommunityChatReadReceipt('rejected', error: 'unavailable');
    }
    try {
      return CommunityChatReadReceipt.parse(
        await sendRequest('communities.markChatRead', {
          'targetRef': targetRef,
          'messageRef': message.messageRef,
        }),
        targetRef,
        message,
      );
    } catch (_) {
      // A timeout, changed account or malformed response is not a confirmed read.
      return const CommunityChatReadReceipt('unknown', error: 'outcomeUnknown');
    }
  }

  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) => workspaceRead(() async {
    if (after < 0 || before < 0 || after > 0 && before > 0) {
      throw const FormatException();
    }
    final result = CommunityChatPage.parse(
      await sendRequest('communities.chat', {
        'targetRef': targetRef,
        'after': after,
        'before': before,
      }),
    );
    if (result.targetRef != targetRef ||
        result.messages.any(
          (v) =>
              after > 0 && v.sequence <= after ||
              before > 0 && v.sequence >= before,
        )) {
      throw const FormatException();
    }
    return result;
  });
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => workspaceRead(
    () => sendRequest('communities.chatDetail', {
      'targetRef': targetRef,
      'messageRef': messageRef,
      'offset': offset,
      'version': version,
    }),
  );
}
