import 'dart:async';
import 'dart:convert';

import 'community_ships_port.dart';
import 'community_hangar_sharing_port.dart';
import 'example_community_ships.dart';

import 'package:crypto/crypto.dart';

import 'communities_module.dart';
import 'community_creation_port.dart';
import 'community_announcements_port.dart';
import 'community_announcement_write_port.dart';
import 'example_community_announcements.dart';
import 'community_chat_port.dart';
import 'community_chat_send_port.dart';
import 'community_preset_port.dart';
import 'example_community_chat.dart';
import 'legacy_community_tag_catalog.dart';
import 'community_workspace_port.dart';
import 'example_community_workspace.dart';
import 'community_profile_port.dart';
import 'example_community_profile.dart';
import 'community_member_role_port.dart';
import 'example_community_member_roles.dart';
import 'community_member_removal_port.dart';
import 'example_community_member_removal.dart';
import 'community_ownership_transfer_port.dart';
import 'community_ownership_exit_port.dart';
import 'example_community_ownership_transfer.dart';
import 'community_invite_port.dart';
import 'community_logs_port.dart';
import 'community_disband_port.dart';
import 'example_community_logs.dart';
import '../settings/local_privacy_port.dart';
import 'example_admission_privacy.dart';

final class ExampleCommunities
    implements
        CommunitiesPort,
        CommunityCreationPort,
        CommunityWorkspacePort,
        CommunityShipsPort,
        CommunityProfilePort,
        CommunityMemberRolePort,
        CommunityMemberRemovalPort,
        CommunityOwnershipTransferPort,
        CommunityOwnershipExitPort,
        CommunityLogsPort,
        CommunityDisbandPort,
        CommunityAnnouncementsPort,
        CommunityAnnouncementWritePort,
        CommunityChatPort,
        CommunityChatSendPort,
        CommunityPresetPort,
        CommunityInvitePort,
        CommunityHangarSharingPort {
  final _hangarSelected = <String>{};
  String? _hangarEdit;
  int _hangarSequence = 0;
  @override
  bool get hangarSharingAvailable => !_disbandClosed;
  @override
  Future<CommunityHangarSharing> readHangarSharing() async {
    if (_disbandClosed) throw const CommunityFailure('identityUnavailable');
    final directory = await read(view: 'mine', query: '');
    _hangarSelected.retainAll(directory.items.map((r) => r.targetRef));
    _hangarEdit = (++_hangarSequence).toRadixString(16).padLeft(32, '0');
    return CommunityHangarSharing.parse({
      'schemaVersion': 1,
      'maximumTargets': 64,
      'editRef': _hangarEdit,
      'usesExplicitTargets': true,
      'options': [
        for (final row in directory.items)
          {
            'targetRef': row.targetRef,
            'name': row.name,
            'selected': _hangarSelected.contains(row.targetRef),
          },
      ],
    });
  }

  @override
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String editRef,
    List<String> selectedRefs,
  ) async {
    if (_disbandClosed ||
        editRef != _hangarEdit ||
        selectedRefs.length > 64 ||
        selectedRefs.toSet().length != selectedRefs.length) {
      return const CommunityHangarSharingOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
    _hangarEdit = null;
    final directory = await read(view: 'mine', query: '');
    if (!selectedRefs.every(
      (ref) => directory.items.any((r) => r.targetRef == ref),
    )) {
      return const CommunityHangarSharingOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
    _hangarSelected
      ..clear()
      ..addAll(selectedRefs);
    return const CommunityHangarSharingOutcome('accepted');
  }

  final _chat = ExampleCommunityChat();
  @override
  bool get shipsAvailable => !_disbandClosed;

  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    if (_disbandClosed) throw const CommunityFailure('identityUnavailable');
    final workspace = await readWorkspace(targetRef, '', 0);
    return exampleCommunityShips(
      workspace,
      seeded: _isSeededOrganization(targetRef),
      offset: offset,
      revision: revision,
      query: query ?? CommunityShipQuery(),
    );
  }

  final _profile = ExampleCommunityProfile();
  @override
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  }) => _profile.read(readWorkspace, targetRef: targetRef, editRef: editRef);
  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> changes,
  ) => _profile.save(readWorkspace, requestId, editRef, changes);
  @override
  bool get chatAvailable => !_disbandClosed;
  @override
  bool get chatReadReceiptsAvailable => !_disbandClosed;
  @override
  bool get chatSendAvailable => !_disbandClosed;
  @override
  bool get communityPresetsAvailable => !_disbandClosed;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) => _chat.read(
    targetRef,
    workspace: () => readWorkspace(targetRef, '', 0),
    seed: _isSeededOrganization(targetRef),
    after: after,
    before: before,
  );
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => _chat.detail(
    targetRef,
    messageRef,
    offset,
    version,
    workspace: () => readWorkspace(targetRef, '', 0),
    seed: _isSeededOrganization(targetRef),
  );
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => _chat.markRead(
    targetRef,
    message,
    workspace: () => readWorkspace(targetRef, '', 0),
    seed: _isSeededOrganization(targetRef),
  );
  @override
  Future<CommunityChatSendOutcome> sendChat(CommunityChatSendIntent intent) =>
      _chat.send(
        intent,
        workspace: () => readWorkspace(intent.targetRef, '', 0),
        seed: _isSeededOrganization(intent.targetRef),
      );
  @override
  Future<CommunityPresetCatalog> readCommunityPresets() => _chat.presets();
  @override
  Future<Map<String, Object?>> exportCommunityPreset(String id, int revision) =>
      _chat.export(id, revision);
  @override
  Future<String> importCommunityPreset(
    Map<String, Object?> attachment,
    int revision,
  ) => _chat.importPreset(attachment, revision);
  final _announcements = ExampleCommunityAnnouncements();
  final _invalidations = StreamController<void>.broadcast();
  @override
  bool get announcementsAvailable => !_disbandClosed;
  @override
  bool get announcementWritesAvailable => !_disbandClosed;
  bool _isSeededOrganization(String targetRef) =>
      _states.containsKey(targetRef);
  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
  }) => _announcements.read(
    targetRef,
    workspace: () => readWorkspace(targetRef, '', 0),
    seed: _isSeededOrganization(targetRef),
    offset: offset,
    expectedRevision: expectedRevision,
  );
  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version,
  ) => _announcements.detail(
    targetRef,
    announcementRef,
    offset,
    version,
    workspace: () => readWorkspace(targetRef, '', 0),
    seed: _isSeededOrganization(targetRef),
  );
  @override
  Future<CommunityAnnouncementOutcome> manageAnnouncement(
    CommunityAnnouncementIntent intent,
  ) => _announcements.manage(
    intent,
    workspace: () => readWorkspace(intent.targetRef, '', 0),
    seed: _isSeededOrganization(intent.targetRef),
  );
  final _invitePreviews = <String>{};
  final _disbanded = <String>{};
  final _disbandPreviews = <String, CommunityDisbandPreview>{};
  int _disbandSequence = 0;
  bool _disbandClosed = false;
  @override
  bool get disbandAvailable => !_disbandClosed;
  @override
  Future<CommunityDisbandPreview> readDisband(String targetRef) async {
    if (!disbandAvailable) throw const CommunityFailure('unavailable');
    final workspace = await readWorkspace(targetRef, '', 0);
    if (workspace.access['isOwner'] != true) {
      throw const CommunityFailure('notAllowed');
    }
    _disbandPreviews.removeWhere((_, value) => value.targetRef == targetRef);
    final ref = (++_disbandSequence).toRadixString(16).padLeft(32, '0');
    final preview = CommunityDisbandPreview(
      targetRef,
      ref,
      workspace.name,
      workspace.totalCount,
      true,
      isExample: true,
    );
    _disbandPreviews[ref] = preview;
    return preview;
  }

  @override
  Future<CommunityDisbandOutcome> disband(
    String targetRef,
    String confirmationRef,
    String password,
  ) async {
    if (!disbandAvailable) {
      return const CommunityDisbandOutcome('rejected', error: 'unavailable');
    }
    final preview = _disbandPreviews[confirmationRef];
    if (preview == null || preview.targetRef != targetRef) {
      return const CommunityDisbandOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
    _disbandPreviews.remove(confirmationRef);
    if (password != 'example-only') {
      return const CommunityDisbandOutcome(
        'rejected',
        error: 'passwordInvalid',
      );
    }
    try {
      final workspace = await readWorkspace(targetRef, '', 0);
      if (workspace.access['isOwner'] != true) {
        return const CommunityDisbandOutcome('rejected', error: 'notAllowed');
      }
      if (workspace.name != preview.name ||
          workspace.totalCount != preview.memberCount) {
        return const CommunityDisbandOutcome(
          'rejected',
          error: 'refreshRequired',
        );
      }
      if (!disbandAvailable) {
        return const CommunityDisbandOutcome('rejected', error: 'unavailable');
      }
      _disbanded.add(targetRef);
      _states[targetRef] = 'none';
      return const CommunityDisbandOutcome('accepted');
    } on CommunityFailure {
      return const CommunityDisbandOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
  }

  final _logs = ExampleCommunityLogs();
  @override
  bool get logsAvailable => true;
  @override
  bool get logDeletionAvailable => true;
  @override
  Future<CommunityLogPage> readLogs(
    String targetRef,
    String type,
    String query,
    int offset,
  ) => _logs.read(readWorkspace, targetRef, type, query, offset);
  @override
  Future<CommunityLogOutcome> deleteLog(String targetRef, String logRef) =>
      _logs.delete(readWorkspace, targetRef, logRef);
  final _memberRoles = ExampleCommunityMemberRoles();
  final _memberRemoval = ExampleCommunityMemberRemoval();
  final _ownership = ExampleCommunityOwnershipTransfer();
  @override
  bool get ownershipExitAvailable => true;
  @override
  Future<CommunityOwnershipExit> readOwnershipExit({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) async => CommunityOwnershipExit.example(
    await _ownership.read(
      readWorkspace,
      targetRef: targetRef,
      memberRef: memberRef,
      editRef: editRef,
      leaveAfterTransfer: true,
    ),
  );
  @override
  Future<CommunityOwnershipTransferOutcome> leaveWithSuccessor(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) async {
    final result = await _ownership.transfer(
      readWorkspace,
      requestId,
      editRef,
      leaveAfterTransfer: true,
    );
    if (result.status == 'accepted') {
      for (final target in _ownership.departed) {
        // An accepted replay must not remove a later, ordinary membership.
        if (_states[target] == 'owner') _states[target] = 'none';
      }
    }
    return result;
  }

  @override
  bool get ownershipTransferAvailable => true;
  @override
  Future<CommunityOwnershipTransfer> readOwnershipTransfer({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => _ownership.read(
    readWorkspace,
    targetRef: targetRef,
    memberRef: memberRef,
    editRef: editRef,
  );
  @override
  Future<CommunityOwnershipTransferOutcome> transferOwnership(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) async {
    final result = await _ownership.transfer(readWorkspace, requestId, editRef);
    if (result.status == 'accepted') {
      for (final target in _ownership.owners.keys) {
        if (_states[target] == 'owner') _states[target] = 'member';
      }
    }
    return result;
  }

  @override
  bool get memberRemovalAvailable => true;
  @override
  Future<CommunityMemberRemoval> readMemberRemoval({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => _memberRemoval.read(
    readWorkspace,
    targetRef: targetRef,
    memberRef: memberRef,
    editRef: editRef,
  );
  @override
  Future<CommunityMemberRemovalOutcome> removeMember(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) => _memberRemoval.remove(readWorkspace, requestId, editRef);
  @override
  bool get memberRoleAvailable => true;
  @override
  Future<CommunityMemberRole> readMemberRole({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => _memberRoles.read(
    readWorkspace,
    targetRef: targetRef,
    memberRef: memberRef,
    editRef: editRef,
  );
  @override
  Future<CommunityMemberRoleOutcome> saveMemberRole(
    String requestId,
    String editRef,
    String roleKey, {
    bool confirmUncertainRetry = false,
  }) => _memberRoles.save(readWorkspace, requestId, editRef, roleKey);
  final _inviteReceipts = <String, String>{};
  int _previewSequence = 0;
  final _privacy = ExampleAdmissionPrivacy();

  LocalPrivacyPort createAdmissionPrivacy() => _privacy.open();

  @override
  Future<CommunityInvitePreview> previewInvite(String inviteCode) async {
    if (inviteCode.trim().toUpperCase() != 'EXAMPLE-ORG') {
      throw const CommunityFailure('inviteInvalid');
    }
    final reference = (++_previewSequence).toRadixString(16).padLeft(32, '0');
    _invitePreviews.add(reference);
    return CommunityInvitePreview(
      previewRef: reference,
      name: '示例 · 新手互助',
      code: 'EXAMPLE-ORG',
      commander: '示例负责人',
      memberCount: 8,
      joinPolicy: 'Open',
      expiresAt: null,
      remainingUses: -1,
      alreadyMember: _states['00000000000000000000000000000003'] == 'member',
    );
  }

  @override
  Future<CommunityInviteOutcome> acceptInvite(
    String requestId,
    String previewRef,
  ) async {
    if (_inviteReceipts.containsKey(requestId)) {
      return _inviteReceipts[requestId] == previewRef
          ? const CommunityInviteOutcome('accepted')
          : const CommunityInviteOutcome('rejected', error: 'requestChanged');
    }
    if (!_invitePreviews.contains(previewRef)) {
      return const CommunityInviteOutcome('rejected', error: 'refreshRequired');
    }
    _states['00000000000000000000000000000003'] = 'member';
    _inviteReceipts[requestId] = previewRef;
    return const CommunityInviteOutcome('accepted');
  }

  final _states = <String, String>{
    '00000000000000000000000000000001': 'member',
    '00000000000000000000000000000002': 'owner',
    '00000000000000000000000000000003': 'none',
  };
  final _created = <String, CommunityCard>{};
  final _intents = <String, CommunityCreationOutcome>{};
  @override
  Future<CommunityCreationOptions> creationOptions() async =>
      LegacyCommunityTagCatalog.options;

  @override
  Future<CommunityCreationOutcome> createCommunity(
    String requestId,
    Map<String, Object?> draft,
  ) async {
    if (_intents.containsKey(requestId)) return _intents[requestId]!;
    final code = (draft['code'] as String).trim().toUpperCase();
    if (_created.containsKey(code)) {
      return const CommunityCreationOutcome(
        'rejected',
        error: 'codeUnavailable',
      );
    }
    // Explicitly session-only preview; production validation belongs to Core/Host.
    final targetRef = sha256
        .convert(utf8.encode('example-created-$code'))
        .toString()
        .substring(0, 32);
    final card = CommunityCard(
      targetRef: targetRef,
      organizationRef: targetRef,
      name: draft['name'] as String,
      description: draft['description'] as String,
      tags: LegacyCommunityTagCatalog.tags
          .where((tag) => (draft['tagIds'] as List).contains(tag.id))
          .map((tag) => tag.name)
          .join(' · '),
      systems: List<String>.unmodifiable(
        (draft['activeSystemIds'] as List).map(
          (id) => switch (id) {
            'pyro' => 'Pyro',
            'nyx' => 'Nyx',
            _ => 'Stanton',
          },
        ),
      ),
      activeTime:
          '${draft['activeFrom']}–${draft['activeTo']} · ${draft['timeZoneId']}',
      relationship: 'owner',
      memberCount: 1,
      memberScale: 'small',
      recruiting: true,
      recruitingTarget: '所有玩家',
      joinMode: switch (draft['joinPolicy']) {
        'Open' => 'direct',
        'Approval' => 'application',
        _ => 'inviteOnly',
      },
    );
    _created[code] = card;
    return _intents[requestId] = CommunityCreationOutcome(
      'accepted',
      organization: card,
    );
  }

  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    final f = filters == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(filters));
    final rows = [
      for (final id in _states.keys)
        CommunityCard(
          targetRef: id,
          organizationRef: id,
          name:
              '示例 · ${switch (id) {
                '00000000000000000000000000000001' => '休闲协作',
                '00000000000000000000000000000002' => '探索交流',
                _ => '新手互助',
              }}',
          description: '组织示例资料，用于检查筛选、名片和操作，不影响真实组织。',
          language: id == '00000000000000000000000000000002'
              ? 'English'
              : '中文 / English',
          activeTime: id == '00000000000000000000000000000002'
              ? '18:00–22:00'
              : '20:00–23:00',
          tags: id == '00000000000000000000000000000002'
              ? '探索 · 调查'
              : id == '00000000000000000000000000000003'
              ? '教学 · 新手互助'
              : '协作 · 休闲',
          recruiting: id != '00000000000000000000000000000002',
          recruitingTarget: id == '00000000000000000000000000000003'
              ? '新手友好'
              : '所有玩家',
          systems: [
            id == '00000000000000000000000000000002' ? 'Pyro' : 'Stanton',
          ],
          relationship: _states[id]!,
          joinMode: 'application',
          memberCount:
              (id == '00000000000000000000000000000002'
                  ? 48
                  : id == '00000000000000000000000000000003'
                  ? 8
                  : 12) -
              (_memberRemoval.removed[id]?.length ?? 0) -
              (_ownership.departed.contains(id) && _states[id] != 'member'
                  ? 1
                  : 0),
          memberScale: id == '00000000000000000000000000000003'
              ? 'small'
              : 'medium',
          actions: switch (_states[id]) {
            'owner' => [],
            'member' => ['leave'],
            'pending' => ['withdraw'],
            _ => ['apply'],
          },
        ),
      ..._created.values,
    ];
    bool matches(CommunityCard r) {
      if (_disbanded.contains(r.targetRef)) return false;
      List<String> group(String key) =>
          List<String>.from((f[key] as List?) ?? []);
      bool one(String key, String value) =>
          group(key).isEmpty || group(key).contains(value);
      if (!(view == 'discover' ||
          const {'member', 'owner'}.contains(r.relationship))) {
        return false;
      }
      if (!'${r.name} ${r.tags} ${r.description}'.toLowerCase().contains(
        query.toLowerCase(),
      )) {
        return false;
      }
      if (group('status').contains('recruiting') && !r.recruiting ||
          group('status').contains('pending') && r.relationship != 'pending' ||
          !one('join', r.joinMode) ||
          !one('scale', r.memberScale) ||
          group('targets').isNotEmpty &&
              (!r.recruiting || !one('targets', r.recruitingTarget)) ||
          !one(
            'cadence',
            r.key == '00000000000000000000000000000002' ? '周末行动' : '休闲',
          ) ||
          !r.language.toLowerCase().contains(
            (f['language'] as String? ?? '').toLowerCase(),
          )) {
        return false;
      }
      if (group('systems').isNotEmpty &&
          !group('systems').any(r.systems.contains)) {
        return false;
      }
      if (group('tags').isNotEmpty &&
          !(f['allTags'] == true
              ? group('tags').every(r.tags.contains)
              : group('tags').any(r.tags.contains))) {
        return false;
      }
      if (group('period').isNotEmpty && !group('period').contains('evening')) {
        return false;
      }
      if (group('days').isNotEmpty &&
          !group('days').any(['Sat', 'Sun'].contains)) {
        return false;
      }
      // Synthetic, explicitly public resources for filter review only.
      if (!one('ships', 'small') ||
          !one(
            'roles',
            r.key == '00000000000000000000000000000002'
                ? 'exploration'
                : 'support',
          )) {
        return false;
      }
      return true;
    }

    final found = rows.map(_profile.project).where(matches).toList();
    switch (f['sort']) {
      case 'name':
        found.sort((a, b) => a.name.compareTo(b.name));
      case 'members':
        found.sort((a, b) => b.memberCount!.compareTo(a.memberCount!));
    }
    return CommunityDirectory(view, query, found, totalCount: found.length);
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    if (action == 'leave') {
      _hangarSelected.remove(targetRef);
      _hangarEdit = null;
    }
    if (_disbanded.contains(targetRef)) {
      throw const CommunityFailure('notFound');
    }
    _states[targetRef] = switch (action) {
      'join' => 'member',
      'apply' => 'pending',
      _ => 'none',
    };
    return 'accepted';
  }

  @override
  Future<void> close() async {
    if (_disbandClosed) return;
    _disbandClosed = true;
    _invalidations.add(null);
    _disbandPreviews.clear();
    _disbanded.clear();
    _logs.close();
    _announcements.close();
    _chat.close();
    _profile.close();
    _memberRoles.clear();
    _memberRemoval.clear();
    _ownership.clear();
    _created.clear();
    _intents.clear();
    _invitePreviews.clear();
    _inviteReceipts.clear();
    _privacy.reset();
    await _invalidations.close();
  }

  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async {
    final directory = await read(view: 'mine', query: '');
    final card = directory.items
        .where((row) => row.targetRef == targetRef)
        .firstOrNull;
    if (card == null) throw const CommunityFailure('notAllowed');
    return exampleCommunityWorkspace(
      card,
      query,
      offset,
      assignments: _memberRoles.assignments[targetRef] ?? const {},
      removed: _memberRemoval.removed[targetRef] ?? const {},
      ownerRef: _ownership.owners[targetRef],
      formerOwnerLeft: _ownership.departed.contains(targetRef),
      profile: _profile.fields(targetRef),
      hasLogo: _profile.hasLogo(targetRef),
    );
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    await readWorkspace(targetRef, '', 0);
    if (kind != 'logo' || memberRef != null) {
      throw const CommunityFailure('notFound');
    }
    return _profile.media(targetRef, offset, version);
  }
}
