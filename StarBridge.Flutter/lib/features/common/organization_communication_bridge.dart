import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'organization_communication_port.dart';
import 'organization_member_actions.dart';
import '../communities/communities_module.dart';
import '../communities/community_bridge_communication.dart';
import '../communities/community_bridge_transport.dart';
import '../communities/community_own_avatar.dart';
import '../communities/community_author_projection.dart';
import '../communities/community_author_projection_port.dart';
import '../communities/community_activity_port.dart';
import '../onboarding/connection_mode_port.dart';

/// Exposes a scoped collaboration command. Parsers, cancellation, account fencing,
/// pagination and idempotent send outcomes are the existing community machinery.
final class ScopedOrganizationCommunicationBridge
    implements
        OrganizationCommunicationPort,
        OrganizationMemberActions,
        OrganizationCommunicationConnectionPort,
        CommunityActivityPort,
        CommunityActivityFailurePort,
        CommunityAuthorProjectionPort,
        OrganizationChatPreviewAuthorPort,
        CommunityChatAuthorRenewalPort,
        CommunityAnnouncementAuthorProjectionPort,
        CommunityAnnouncementAuthorDetailPort,
        CommunityChatAuthorDetailPort,
        CommunityOwnIdentitySource {
  ScopedOrganizationCommunicationBridge(
    BridgeClientSession session,
    String sourceRef, {
    required String command,
    ConnectionModeControl? connectionMode,
    String? Function()? ownAvatar,
    this._ownName,
  }) : _transport = _ScopedCommunicationTransport(
         session,
         sourceRef,
         command,
         connectionMode: connectionMode,
         ownAvatar: ownAvatar,
       );
  final _ScopedCommunicationTransport _transport;
  final String? Function()? _ownName;
  @override
  String? get ownAvatarImageData => _transport.ownAvatarImageData;
  @override
  String? get ownChatName => _ownName?.call();
  @override
  bool get authorIdentitiesAvailable => _transport.authorIdentitiesAvailable;
  @override
  Stream<void> get authorIdentityChanges => _transport.authorIdentityChanges;
  @override
  Future<CommunityChatPage> readChatAuthors(
    String targetRef, {
    int after = 0,
    int before = 0,
    List<String> observeMessageRefs = const [],
  }) => _transport.readChatAuthors(
    targetRef,
    after: after,
    before: before,
    observeMessageRefs: observeMessageRefs,
  );
  @override
  bool get chatAuthorRenewalAvailable => _transport.chatAuthorRenewalAvailable;
  @override
  Future<CommunityChatPage> renewChatAuthors(
    String targetRef, {
    int after = 0,
    List<String> observeMessageRefs = const [],
  }) => _transport.renewChatAuthors(
    targetRef,
    after: after,
    observeMessageRefs: observeMessageRefs,
  );
  @override
  bool get previewAuthorsAvailable => _transport.previewAuthorsAvailable;
  @override
  Stream<void> get previewAuthorChanges => _transport.previewAuthorChanges;
  @override
  Future<CommunityChatPage> renewPreviewAuthors(
    String targetRef, {
    int after = 0,
    int limit = 8,
    List<String> observeMessageRefs = const [],
  }) => _transport.renewPreviewAuthors(
    targetRef,
    after: after,
    limit: limit,
    observeMessageRefs: observeMessageRefs,
  );
  @override
  Future<CommunityAnnouncementsPage> readAnnouncementAuthors(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
    List<String> observeAnnouncementRefs = const [],
  }) async {
    final page = await _transport.readAnnouncementAuthors(
      targetRef,
      offset: offset,
      expectedRevision: expectedRevision,
      observeAnnouncementRefs: observeAnnouncementRefs,
    );
    if (page.canManage) throw const CommunityFailure('dataInvalid');
    return page;
  }

  @override
  Future<Map<String, Object?>> readAnnouncementAuthorDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
    String? expectedEditorIdentityVersion,
  }) => _transport.readAnnouncementAuthorDetail(
    targetRef,
    announcementRef,
    offset,
    version,
    expectedAuthorIdentityVersion: expectedAuthorIdentityVersion,
    expectedEditorIdentityVersion: expectedEditorIdentityVersion,
  );
  @override
  Future<Map<String, Object?>> readChatAuthorDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
  }) => _transport.readChatAuthorDetail(
    targetRef,
    messageRef,
    offset,
    version,
    expectedAuthorIdentityVersion: expectedAuthorIdentityVersion,
  );
  @override
  late final Stream<void> workspaceChanges = _transport.workspaceChanges;
  @override
  Stream<String> get activityReadErrors => _transport.activityReadErrors;
  @override
  bool get activityHealthy => _transport.activityHealthy;
  @override
  Stream<void> get connectionChanges => _transport.connectionChanges;
  @override
  bool get onlineTrafficAllowed => _transport.onlineTrafficAllowed;
  @override
  bool get memberActionsAvailable => false;
  @override
  Stream<void> get invalidations => _transport.invalidations;
  @override
  bool get announcementsAvailable => _transport.announcementsAvailable;
  @override
  bool get chatAvailable => _transport.chatAvailable;
  @override
  bool get chatSendAvailable => _transport.chatSendAvailable;
  @override
  bool get chatReadReceiptsAvailable => _transport.chatReadReceiptsAvailable;
  @override
  Future<OrganizationCommunicationContext> open() => _transport.open();
  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
  }) async {
    final page = await _transport.readAnnouncements(
      targetRef,
      offset: offset,
      expectedRevision: expectedRevision,
    );
    // This facade deliberately has no announcement management port.
    if (page.canManage) throw const CommunityFailure('dataInvalid');
    return page;
  }

  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version,
  ) => _transport.readAnnouncementDetail(
    targetRef,
    announcementRef,
    offset,
    version,
  );
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) => _transport.readChat(targetRef, after: after, before: before);
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => _transport.readChatDetail(targetRef, messageRef, offset, version);
  @override
  Future<CommunityChatSendOutcome> sendChat(CommunityChatSendIntent intent) =>
      _transport.sendChat(intent);
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => _transport.markChatRead(targetRef, message);
  @override
  Future<void> close() => _transport.close();
}

final class _ScopedCommunicationTransport extends CommunityBridgeTransport
    with CommunityBridgeCommunication {
  _ScopedCommunicationTransport(
    super.session,
    this.sourceRef,
    this.command, {
    super.connectionMode,
    super.ownAvatar,
  }) {
    connectionMode?.addListener(_connectionChanged);
    if (sourceRef.isEmpty ||
        sourceRef.length > 64 ||
        sourceRef.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException();
    }
    configureOfficialActivity(sourceRef, available: false);
    _hadAuthorSupport = _authorSupport;
    _hadPreviewSupport = _previewSupport;
    _authorCapabilities = session.capabilitiesChanged.listen((_) {
      final preview = _previewSupport;
      if (preview != _hadPreviewSupport) {
        _hadPreviewSupport = preview;
        // Names on the tile end with the capability; the chat keeps its own.
        if (!_previewChanges.isClosed) _previewChanges.add(null);
      }
      final next = _authorSupport;
      if (next == _hadAuthorSupport) return;
      _hadAuthorSupport = next;
      _retireAuthors();
    }, onDone: _retireAuthors);
    _unobserveAuthorGeneration = session.observeGenerationChanges(
      (_, _) => _retireAuthors(),
    );
  }
  final String sourceRef, command;
  final _authorChanges = StreamController<void>.broadcast(sync: true);
  Stream<void> get authorIdentityChanges => _authorChanges.stream;
  final _previewChanges = StreamController<void>.broadcast(sync: true);
  Stream<void> get previewAuthorChanges => _previewChanges.stream;
  late final StreamSubscription<void> _authorCapabilities;
  late final void Function() _unobserveAuthorGeneration;
  bool _hadAuthorSupport = false;
  int _authorAdmission = 0;
  bool get _authorSupport => session.hostCapabilities.contains(
    'officialFleet.communication.authorIdentities',
  );
  bool _hadPreviewSupport = false;
  bool get _previewSupport => session.hostCapabilities.contains(
    'officialFleet.communication.previewAuthors',
  );
  void _retireAuthors() {
    if (isClosed) return;
    ++_authorAdmission;
    _authors = false;
    _authorTarget = null;
    _authorChanges.add(null);
    _previewChanges.add(null);
  }

  final _connectionChanges = StreamController<void>.broadcast();
  Stream<void> get connectionChanges => _connectionChanges.stream;
  @override
  bool get onlineTrafficAllowed =>
      !isClosed &&
      connectionMode?.allowsOnlineTraffic != false &&
      connectionMode?.failed != true;
  @override
  bool get connectionModeInvalidatesDisplay => false;
  void _connectionChanged() {
    if (isClosed) return;
    // Online mode is only transport admission. Old context capabilities must
    // not become writable before the reconnect open is freshly authorized.
    _send = _receipts = false;
    _retireAuthors();
    _connectionChanges.add(null);
  }

  @override
  Future<void> close() async {
    connectionMode?.removeListener(_connectionChanged);
    _retireAuthors();
    _unobserveAuthorGeneration();
    await _authorCapabilities.cancel();
    await super.close();
    await _authorChanges.close();
    await _previewChanges.close();
    await _connectionChanges.close();
  }

  bool _announcements = false, _chat = false, _send = false, _receipts = false;
  bool _authors = false;
  int _authorEpoch = -1, _authorGeneration = -1;
  String? _authorTarget;
  bool get authorIdentitiesAvailable =>
      onlineTrafficAllowed &&
      _authors &&
      requestEpoch == _authorEpoch &&
      session.activeGeneration == _authorGeneration &&
      session.hostCapabilities.contains(
        'officialFleet.communication.authorIdentities',
      );
  bool _previewAuthors = false;

  /// Host support and the relay's explicit yes, on the current open.
  bool get previewAuthorsAvailable =>
      authorIdentitiesAvailable && _previewAuthors && _previewSupport;
  @override
  bool get announcementsAvailable => !isClosed && _announcements;
  @override
  bool get chatAvailable => !isClosed && _chat;
  @override
  bool get chatSendAvailable => onlineTrafficAllowed && _send;
  @override
  bool get chatReadReceiptsAvailable => onlineTrafficAllowed && _receipts;

  Future<CommunityChatPage> readChatAuthors(
    String targetRef, {
    int after = 0,
    int before = 0,
    List<String> observeMessageRefs = const [],
  }) => workspaceRead(() async {
    if (after < 0 ||
        before < 0 ||
        after > 0 && before > 0 ||
        observeMessageRefs.length > 50 ||
        observeMessageRefs.toSet().length != observeMessageRefs.length ||
        observeMessageRefs.any(
          (ref) => !RegExp(r'^[a-f0-9]{32}$').hasMatch(ref),
        )) {
      throw const FormatException();
    }
    final row = await sendRequest('communities.chat', {
      'targetRef': targetRef,
      'after': after,
      'before': before,
      'observeMessageRefs': observeMessageRefs,
    });
    final page = CommunityChatPage.parse(
      row,
      officialAuthors: authorIdentitiesAvailable,
    );
    if (page.targetRef != targetRef ||
        page.messages.any(
          (message) =>
              after > 0 && message.sequence <= after ||
              before > 0 && message.sequence >= before,
        )) {
      throw const FormatException();
    }
    return page;
  });

  bool get chatAuthorRenewalAvailable =>
      authorIdentitiesAvailable &&
      session.hostCapabilities.contains(
        'officialFleet.communication.chatAuthorRenewal',
      );

  /// The open chat keeps its names with one request and no channel read. Unlike
  /// the tile's, new messages here do go to the local history as usual.
  Future<CommunityChatPage> renewChatAuthors(
    String targetRef, {
    int after = 0,
    List<String> observeMessageRefs = const [],
  }) => workspaceRead(() async {
    if (!chatAuthorRenewalAvailable) {
      throw const CommunityFailure('unavailable');
    }
    if (after < 0 ||
        observeMessageRefs.length > 50 ||
        observeMessageRefs.toSet().length != observeMessageRefs.length ||
        observeMessageRefs.any(
          (ref) => !RegExp(r'^[a-f0-9]{32}$').hasMatch(ref),
        )) {
      throw const FormatException();
    }
    final row = await sendRequest('communities.chatAuthorRenewal', {
      'targetRef': targetRef,
      'surface': 'chat',
      'after': after,
      'limit': 50,
      'observeMessageRefs': observeMessageRefs,
    });
    final page = CommunityChatPage.parse(
      row,
      officialAuthors: authorIdentitiesAvailable,
    );
    if (page.targetRef != targetRef ||
        page.messages.any((message) => after > 0 && message.sequence <= after)) {
      throw const FormatException();
    }
    return page;
  });

  /// One request and no channel read: the tile needs author proofs, nothing else.
  /// Not a read of the conversation: no receipt, no archive, no unread change.
  Future<CommunityChatPage> renewPreviewAuthors(
    String targetRef, {
    int after = 0,
    int limit = 8,
    List<String> observeMessageRefs = const [],
  }) => workspaceRead(() async {
    if (!previewAuthorsAvailable) throw const CommunityFailure('unavailable');
    if (after < 0 ||
        limit < 1 ||
        limit > 8 ||
        observeMessageRefs.length > 8 ||
        observeMessageRefs.toSet().length != observeMessageRefs.length ||
        observeMessageRefs.any(
          (ref) => !RegExp(r'^[a-f0-9]{32}$').hasMatch(ref),
        )) {
      throw const FormatException();
    }
    final row = await sendRequest('communities.chatAuthorRenewal', {
      'targetRef': targetRef,
      'after': after,
      'limit': limit,
      'observeMessageRefs': observeMessageRefs,
    });
    final page = CommunityChatPage.parse(row, officialAuthors: true);
    if (page.targetRef != targetRef ||
        page.messages.any((message) => after > 0 && message.sequence <= after)) {
      throw const FormatException();
    }
    return page;
  });

  Future<CommunityAnnouncementsPage> readAnnouncementAuthors(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
    List<String> observeAnnouncementRefs = const [],
  }) => workspaceRead(() async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(targetRef) ||
        offset < 0 ||
        offset > 100 ||
        expectedRevision != null && expectedRevision < 0 ||
        offset > 0 && expectedRevision == null ||
        observeAnnouncementRefs.length > 21 ||
        observeAnnouncementRefs.toSet().length !=
            observeAnnouncementRefs.length ||
        observeAnnouncementRefs.any(
          (ref) => !RegExp(r'^[a-f0-9]{32}$').hasMatch(ref),
        )) {
      throw const FormatException();
    }
    final row = await sendRequest('communities.announcements', {
      'targetRef': targetRef,
      'offset': offset,
      'expectedRevision': expectedRevision,
      'observeAnnouncementRefs': observeAnnouncementRefs,
    });
    final page = CommunityAnnouncementsPage.parse(row, officialAuthors: true);
    if (page.targetRef != targetRef ||
        page.offset != offset ||
        expectedRevision != null && page.revision != expectedRevision) {
      throw const FormatException();
    }
    return page;
  });

  Future<Map<String, Object?>> readAnnouncementAuthorDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
    String? expectedEditorIdentityVersion,
  }) => workspaceRead(() async {
    if (!authorIdentitiesAvailable || targetRef != _authorTarget) {
      throw const CommunityFailure('unavailable');
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(announcementRef) ||
        offset < 0 ||
        offset > 1600 * 1024 ||
        offset % (192 * 1024) != 0 ||
        offset > 0 && version == null ||
        [
          version,
          expectedAuthorIdentityVersion,
          expectedEditorIdentityVersion,
        ].any(
          (value) =>
              value != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(value),
        )) {
      throw const FormatException();
    }
    return sendRequest('communities.announcementDetail', {
      'targetRef': targetRef,
      'announcementRef': announcementRef,
      'offset': offset,
      'version': version,
      'authorIdentitySchemaVersion': 1,
      'expectedAuthorIdentityVersion': expectedAuthorIdentityVersion,
      'expectedEditorIdentityVersion': expectedEditorIdentityVersion,
    });
  });

  Future<Map<String, Object?>> readChatAuthorDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
  }) => workspaceRead(() async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(targetRef) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(messageRef) ||
        offset < 0 ||
        offset > 2 * 1024 * 1024 ||
        offset % (192 * 1024) != 0 ||
        offset > 0 && version == null ||
        [version, expectedAuthorIdentityVersion].any(
          (value) =>
              value != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(value),
        )) {
      throw const FormatException();
    }
    // A metadata-only support loss does not cancel still-authorized content.
    // sendRequest admits the optional fields only for the current source open.
    return sendRequest('communities.chatDetail', {
      'targetRef': targetRef,
      'messageRef': messageRef,
      'offset': offset,
      'version': version,
      'authorIdentitySchemaVersion': 1,
      'expectedAuthorIdentityVersion': expectedAuthorIdentityVersion,
    });
  });
  Future<OrganizationCommunicationContext> open() => workspaceRead(() async {
    _retireAuthors();
    final row = await sendRequest('open', {});
    if (row['sourceRef'] != sourceRef ||
        row['targetRef'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(row['targetRef'] as String) ||
        row['name'] is! String ||
        (row['name'] as String).isEmpty ||
        (row['name'] as String).length > 256 ||
        (row['name'] as String).trim().isEmpty ||
        RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(row['name'] as String) ||
        [
          'announcementsAvailable',
          'chatAvailable',
          'chatSendAvailable',
          'readReceiptsAvailable',
        ].any((key) => row[key] is! bool) ||
        row.containsKey('activityAvailable') &&
            row['activityAvailable'] is! bool) {
      throw const FormatException();
    }
    _announcements = row['announcementsAvailable'] as bool;
    _chat = row['chatAvailable'] as bool;
    _send = row['chatSendAvailable'] as bool;
    _receipts = row['readReceiptsAvailable'] as bool;
    _authors =
        row['authorIdentitySchemaVersion'] is int &&
        row['authorIdentitySchemaVersion'] == 1;
    _previewAuthors = row['previewAuthorsAvailable'] == true;
    _authorEpoch = requestEpoch;
    _authorGeneration = session.activeGeneration;
    _authorTarget = row['targetRef'] as String;
    configureOfficialActivity(
      sourceRef,
      available: row['activityAvailable'] == true,
    );
    return OrganizationCommunicationContext(
      row['targetRef'] as String,
      row['name'] as String,
    );
  });

  @override
  Future<Map<String, Object?>> sendRequest(
    String name,
    Map<String, Object?> payload, {
    Duration? timeout,
    bool Function()? officialAnnouncementCurrent,
  }) {
    final action = switch (name) {
      'open' => 'open',
      'communities.announcements' => 'announcements',
      'communities.announcementDetail' => 'announcementDetail',
      'communities.chat' => 'chat',
      'communities.chatAuthorRenewal' => 'chatAuthorRenewal',
      'communities.chatDetail' => 'chatDetail',
      'communities.sendChat' => 'sendChat',
      'communities.markChatRead' => 'markChatRead',
      _ => throw const CommunityFailure('notAllowed'),
    };
    final currentAuthors =
        authorIdentitiesAvailable && payload['targetRef'] == _authorTarget;
    final chatAuthors = action == 'chat' && currentAuthors;
    final renewal = action == 'chatAuthorRenewal';
    if (renewal && !currentAuthors) {
      throw const CommunityFailure('unavailable');
    }
    final announcementAuthors =
        action == 'announcements' &&
        payload.containsKey('observeAnnouncementRefs') &&
        currentAuthors;
    final announcementDetailAuthors =
        action == 'announcementDetail' &&
        payload['authorIdentitySchemaVersion'] == 1 &&
        currentAuthors;
    final chatDetailAuthors =
        action == 'chatDetail' &&
        payload['authorIdentitySchemaVersion'] == 1 &&
        currentAuthors;
    final admission = _authorAdmission;
    final observed = chatAuthors || renewal
        ? List<String>.from(payload['observeMessageRefs'] as List? ?? const [])
        : <String>[];
    final observedAnnouncements = announcementAuthors
        ? List<String>.from(
            payload['observeAnnouncementRefs'] as List? ?? const [],
          )
        : <String>[];
    return super
        .sendRequest(
          command,
          {
            for (final entry in payload.entries)
              if (entry.key != 'observeMessageRefs' &&
                  entry.key != 'observeAnnouncementRefs' &&
                  entry.key != 'authorIdentitySchemaVersion' &&
                  entry.key != 'expectedAuthorIdentityVersion' &&
                  entry.key != 'expectedEditorIdentityVersion')
                entry.key: entry.value,
            'sourceRef': sourceRef,
            'action': action,
            if (chatAuthors) ...{
              'authorIdentitySchemaVersion': 1,
              'observeMessageRefs': observed,
            },
            if (renewal) 'observeMessageRefs': observed,
            if (chatDetailAuthors) ...{
              'authorIdentitySchemaVersion': 1,
              'expectedAuthorIdentityVersion':
                  payload['expectedAuthorIdentityVersion'],
            },
            if (announcementDetailAuthors) ...{
              'authorIdentitySchemaVersion': 1,
              'expectedAuthorIdentityVersion':
                  payload['expectedAuthorIdentityVersion'],
              'expectedEditorIdentityVersion':
                  payload['expectedEditorIdentityVersion'],
            },
            if (announcementAuthors) ...{
              'authorIdentitySchemaVersion': 1,
              'observeAnnouncementRefs': observedAnnouncements,
            },
          },
          timeout: timeout,
          officialAnnouncementCurrent: officialAnnouncementCurrent,
        )
        .then((row) {
          if (renewal) {
            // A lost capability or a reply without proofs shows no names.
            final allowed = payload['surface'] == 'chat'
                ? authorIdentitiesAvailable
                : previewAuthorsAvailable;
            return !allowed || row['authorIdentitySchemaVersion'] != 1
                ? neutralOfficialChatPage(row)
                : checkedOfficialChatPage(row, observed);
          }
          if (action == 'chat') {
            return !chatAuthors ||
                    !authorIdentitiesAvailable ||
                    row['authorIdentitySchemaVersion'] != 1
                ? neutralOfficialChatPage(row)
                : checkedOfficialChatPage(row, observed);
          }
          if (action == 'announcements') {
            return !announcementAuthors ||
                    !authorIdentitiesAvailable ||
                    admission != _authorAdmission ||
                    row['authorIdentitySchemaVersion'] != 1
                ? neutralOfficialAnnouncementsPage(row)
                : checkedOfficialAnnouncementsPage(row, observedAnnouncements);
          }
          if (action == 'chatDetail' &&
              payload['authorIdentitySchemaVersion'] == 1) {
            return !chatDetailAuthors ||
                    !authorIdentitiesAvailable ||
                    admission != _authorAdmission ||
                    payload['targetRef'] != _authorTarget
                ? neutralOfficialChatDetail(row)
                : row;
          }
          if (action == 'announcementDetail' &&
              payload['authorIdentitySchemaVersion'] == 1) {
            return !announcementDetailAuthors ||
                    !authorIdentitiesAvailable ||
                    admission != _authorAdmission ||
                    payload['targetRef'] != _authorTarget
                ? neutralOfficialAnnouncementDetail(row)
                : row;
          }
          return row;
        });
  }

  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) => Future.error(const CommunityFailure('notAllowed'));
  @override
  Future<String> execute(String action, String targetRef) =>
      Future.error(const CommunityFailure('notAllowed'));
}
