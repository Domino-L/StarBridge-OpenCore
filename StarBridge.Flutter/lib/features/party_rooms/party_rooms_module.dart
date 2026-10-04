import 'dart:async';

import 'package:flutter/foundation.dart';

import 'room_commands.dart';
import 'room_invitations.dart';
import 'room_chat_module.dart';

enum RoomReadState { loading, ready, signedOut, unavailable }

final class RoomMember {
  const RoomMember({
    required this.callsign,
    required this.gameId,
    required this.isHost,
    required this.presence,
    required this.location,
    required this.ship,
    required this.shard,
    this.avatarData,
    this.userRef,
    this.removalToken,
    this.isSelf = false,
    this.serverRegion = '',
    this.presenceKey = 'presence.unknown',
    this.locationLabels = const {},
    this.shipLabels = const {},
    this.locationHiddenReason,
    this.arrivalPendingConfirmation = false,
    this.arrivalTargetCode,
    this.arrivalTargetLabels = const {},
  });
  final String callsign, gameId, presence, location, ship, shard;
  final bool isHost;
  final String? avatarData;
  final String? userRef;
  final String? removalToken;
  final bool isSelf;
  final String serverRegion;
  final String presenceKey;
  final Map<String, String> locationLabels;
  final Map<String, String> shipLabels;
  final String? locationHiddenReason;
  final bool arrivalPendingConfirmation;
  final String? arrivalTargetCode;
  final Map<String, String> arrivalTargetLabels;
  String get displayName => callsign.isEmpty
      ? gameId
      : gameId.isEmpty
      ? callsign
      : '$callsign ($gameId)';
}

final class RoomTag {
  const RoomTag({
    required this.id,
    required this.text,
    required this.isGameplay,
  });
  final String id, text;
  final bool isGameplay;
}

final class PartyRoom {
  PartyRoom({
    required this.id,
    required this.title,
    required this.goal,
    required this.capacity,
    required this.isPublic,
    required this.eligibility,
    required this.admissionMode,
    required this.passwordRequired,
    required this.voice,
    required this.language,
    required this.expiresAt,
    required this.recruitmentClosesAt,
    required this.viewerIsHost,
    required List<RoomMember> members,
    List<RoomTag> tags = const [],
    this.leaderServerRegion = '',
    this.leaderGameVersion = '',
    this.roomCode = '',
    this.canPreviewMemberProfiles = false,
    List<RoomApplication> pendingApplications = const [],
  }) : members = List.unmodifiable(members),
       pendingApplications = List.unmodifiable(pendingApplications),
       tags = List.unmodifiable(tags);
  final List<RoomTag> tags;
  final String leaderServerRegion;
  final String leaderGameVersion;
  final String roomCode;
  final bool canPreviewMemberProfiles;
  final List<RoomApplication> pendingApplications;
  final String id, title, goal, eligibility, admissionMode, voice, language;
  final int capacity;
  final bool isPublic, passwordRequired, viewerIsHost;
  final DateTime expiresAt;
  final DateTime? recruitmentClosesAt;
  final List<RoomMember> members;
}

final class RoomApplication {
  const RoomApplication({
    required this.id,
    required this.callsign,
    required this.gameId,
    required this.createdAt,
    this.avatarData,
    this.userRef,
  });
  final String id, callsign, gameId;
  final DateTime createdAt;
  final String? avatarData, userRef;
  String get displayName => callsign.isEmpty
      ? gameId
      : gameId.isEmpty
      ? callsign
      : '$callsign ($gameId)';
}

final class RoomDirectory {
  RoomDirectory({
    required List<PartyRoom> rooms,
    this.currentRoomId,
    this.supportsHostTransfer = false,
    required this.serverTime,
    List<RoomTag> tagOptions = const [],
    List<RoomInvitation> receivedInvitations = const [],
    List<RoomInvitation> sentInvitations = const [],
    List<String>? viewerPendingRoomIds,
  }) : tagOptions = List.unmodifiable(tagOptions),
       viewerPendingRoomIds = viewerPendingRoomIds == null
           ? null
           : List.unmodifiable(viewerPendingRoomIds),
       receivedInvitations = List.unmodifiable(receivedInvitations),
       sentInvitations = List.unmodifiable(sentInvitations),
       rooms = List.unmodifiable(rooms) {
    if (rooms.map((r) => r.id).toSet().length != rooms.length ||
        (currentRoomId != null &&
            (rooms.length != 1 || rooms.single.id != currentRoomId))) {
      throw const FormatException('Invalid room membership projection');
    }
  }
  final List<PartyRoom> rooms;
  final String? currentRoomId;
  final bool supportsHostTransfer;
  final DateTime serverTime;
  final List<RoomTag> tagOptions;
  final List<RoomInvitation> receivedInvitations, sentInvitations;
  final List<String>? viewerPendingRoomIds;
}

final class RoomReadResult {
  const RoomReadResult(
    this.state, {
    this.directory,
    this.failure = 'unavailable',
  });
  final RoomReadState state;
  final RoomDirectory? directory;
  final String failure;
}

abstract interface class PartyRoomsPort {
  Stream<void> get invalidations;
  Future<RoomReadResult> read();
  Future<void> close();
}

abstract interface class PartyRoomsPreviewControl {
  String get previewScene;
  void selectPreviewScene(String scene);
}

final class UnavailablePartyRoomsPort implements PartyRoomsPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<RoomReadResult> read() async => const RoomReadResult(
    RoomReadState.unavailable,
    failure: 'hostUnavailable',
  );
  @override
  Future<void> close() async {}
}

/// Owns selection, refresh and account invalidation together. A room selection
/// is never a membership; only the authoritative currentRoomId changes mode.
final class PartyRoomsModule extends ChangeNotifier {
  PartyRoomsModule(
    this._port, {
    this.refreshInterval = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _subscription = _port.invalidations.listen((_) {
      _epoch++;
      contextRevision++;
      chat?.setRoom(null);
      directory = null;
      selectedRoomId = null;
      busy = false;
      writing = false;
      _commandFeedbackTimer?.cancel();
      commandMessage = null;
      _pendingApplicationRoomId = null;
      commandNeedsRefresh = false;
      state = RoomReadState.loading;
      _updateActivity();
      notifyListeners();
      if (_active || _sessionStarted) unawaited(refresh());
    });
    chat?.addListener(_updateActivity);
  }
  final PartyRoomsPort _port;
  late final RoomChatModule? chat = _port is RoomChatProvider
      ? (RoomChatModule((_port as RoomChatProvider).roomChat)
          ..setVisible(_active))
      : null;
  void _syncChat({bool verified = false}) {
    if (state == RoomReadState.unavailable &&
        const [
          'identityUnavailable',
          'forbidden',
          'hostUnavailable',
        ].contains(failure)) {
      chat?.setRoom(null);
    } else if (state == RoomReadState.unavailable &&
        (_active || _sessionStarted)) {
      chat?.setPaused(true);
    } else {
      chat?.setRoom(
        (_active || _sessionStarted) ? directory?.currentRoomId : null,
        verified: verified,
      );
      chat?.setPaused(false);
    }
    _updateActivity();
  }

  final activityCount = ValueNotifier<int>(0);
  final pendingCount = ValueNotifier<int>(0);
  int get invitationCount => state == RoomReadState.ready
      ? directory?.receivedInvitations.length ?? 0
      : 0;
  int get applicationCount =>
      state == RoomReadState.ready &&
          selectedRoom?.viewerIsHost == true &&
          directory?.currentRoomId == selectedRoom?.id
      ? selectedRoom?.pendingApplications.length ?? 0
      : 0;
  bool _activityQueued = false;
  void _updateActivity() {
    if (_disposed || _activityQueued) return;
    _activityQueued = true;
    scheduleMicrotask(() {
      _activityQueued = false;
      if (_disposed) return;
      pendingCount.value = invitationCount + applicationCount;
      activityCount.value =
          pendingCount.value +
          (state == RoomReadState.ready ? chat?.unread ?? 0 : 0);
    });
  }

  /// Mounted application owns the session; page navigation only changes visibility.
  void startSession() {
    if (_disposed || _sessionStarted) return;
    _sessionStarted = true;
    if (!busy) unawaited(refresh());
  }

  void stopSession() {
    if (_disposed) return;
    _commandFeedbackTimer?.cancel();
    commandMessage = null;
    _pendingApplicationRoomId = null;
    _sessionStarted = false;
    _active = false;
    _refreshTimer?.cancel();
    _epoch++;
    contextRevision++;
    busy = false;
    writing = false;
    directory = null;
    selectedRoomId = null;
    state = RoomReadState.loading;
    chat?.setRoom(null);
    _updateActivity();
  }

  void setForeground(bool value) => chat?.setForeground(value);
  final Duration refreshInterval;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  Timer? _refreshTimer;
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if ((!_active && !_sessionStarted) ||
        _disposed ||
        state == RoomReadState.signedOut ||
        _port is PartyRoomsPreviewControl) {
      return;
    }
    _refreshTimer = Timer(refreshInterval, () {
      if (busy) {
        _scheduleRefresh();
      } else {
        unawaited(refresh());
      }
    });
  }

  late final StreamSubscription<void> _subscription;
  int _epoch = 0;
  bool _active = false, _disposed = false;
  bool _sessionStarted = false;
  bool busy = false;
  bool writing = false;
  int? _manualRefreshEpoch;
  bool get manualRefreshing => busy && _manualRefreshEpoch == _epoch;
  RoomReadState state = RoomReadState.loading;
  RoomDirectory? directory;
  String? selectedRoomId;
  String failure = 'unavailable';
  String? commandMessage;
  Timer? _commandFeedbackTimer;
  String? _pendingApplicationRoomId;

  void _reconcileApplicationFeedback() {
    if (commandMessage != 'pending' || directory == null) return;
    final pending = directory!.viewerPendingRoomIds;
    if (directory!.currentRoomId != null ||
        (_pendingApplicationRoomId != null &&
            pending != null &&
            !pending.contains(_pendingApplicationRoomId))) {
      commandMessage = null;
      _pendingApplicationRoomId = null;
    }
  }

  bool commandNeedsRefresh = false;
  bool get canTransferHost =>
      canManage && directory?.supportsHostTransfer == true;
  int contextRevision = 0;
  bool get supportsCommands =>
      _port is RoomCommandsPort && (_port as RoomCommandsPort).supportsCommands;
  bool get canCommand =>
      !_disposed &&
      supportsCommands &&
      !writing &&
      !commandNeedsRefresh &&
      state == RoomReadState.ready;
  bool get supportsManagement =>
      _port is RoomManagementPort &&
      (_port as RoomManagementPort).supportsManagement;
  bool get canManage =>
      canCommand &&
      supportsManagement &&
      directory?.currentRoomId == selectedRoom?.id &&
      selectedRoom?.viewerIsHost == true;
  bool get supportsInvitations =>
      _port is RoomInvitationsPort &&
      (_port as RoomInvitationsPort).supportsInvitations;
  bool get canInvite =>
      supportsInvitations &&
      canCommand &&
      supportsManagement &&
      directory?.currentRoomId == selectedRoom?.id &&
      selectedRoom?.viewerIsHost == true;

  // Preview is read-only: it must not change membership, chat or command feedback.
  Future<PartyRoom?> previewInvitation(RoomInvitation invitation) async {
    if (!supportsInvitations ||
        !canCommand ||
        directory?.currentRoomId != null ||
        directory?.receivedInvitations.any(
              (i) => i.id == invitation.id && i.roomId == invitation.roomId,
            ) !=
            true) {
      return null;
    }
    final revision = contextRevision;
    final result = await (_port as RoomCommandsPort).execute(
      RoomCommand(RoomOperation.invitePreview, {
        'roomId': invitation.roomId,
        'invitationId': invitation.id,
      }),
    );
    if (_disposed ||
        revision != contextRevision ||
        directory?.currentRoomId != null ||
        directory?.receivedInvitations.any(
              (i) => i.id == invitation.id && i.roomId == invitation.roomId,
            ) !=
            true) {
      return null;
    }
    return result.preview?.id == invitation.roomId ? result.preview : null;
  }

  Future<RoomCommandResult> execute(
    RoomCommand command, {
    int? expectedRevision,
  }) async {
    if (expectedRevision != null && expectedRevision != contextRevision) {
      return const RoomCommandResult('stale', error: 'contextChanged');
    }
    if (!canCommand) {
      return const RoomCommandResult('rejected', error: 'unavailable');
    }
    if (const [
          RoomOperation.inviteTargets,
          RoomOperation.invite,
          RoomOperation.inviteRevoke,
        ].contains(command.operation) &&
        (!canInvite || command.data['roomId'] != directory?.currentRoomId)) {
      return const RoomCommandResult('rejected', error: 'notHost');
    }
    if (const [
          RoomOperation.update,
          RoomOperation.close,
          RoomOperation.decide,
          RoomOperation.remove,
          RoomOperation.transferHost,
        ].contains(command.operation) &&
        (!canManage || command.data['roomId'] != directory?.currentRoomId)) {
      return const RoomCommandResult('rejected', error: 'notHost');
    }
    if (command.operation == RoomOperation.remove &&
        !selectedRoom!.members.any(
          (m) =>
              !m.isHost &&
              !m.isSelf &&
              m.removalToken != null &&
              m.removalToken == command.data['removalToken'],
        )) {
      return const RoomCommandResult('rejected', error: 'memberGone');
    }
    if (command.operation == RoomOperation.transferHost &&
        (!canTransferHost ||
            !selectedRoom!.members.any(
              (member) =>
                  !member.isHost &&
                  !member.isSelf &&
                  member.removalToken != null &&
                  member.removalToken == command.data['memberToken'],
            ))) {
      return const RoomCommandResult('rejected', error: 'memberGone');
    }
    if (command.operation == RoomOperation.inviteTargets) {
      // Target enumeration is a read. Its failure belongs to the invitation
      // dialog and must not invalidate or write feedback onto the room page.
      final epoch = _epoch;
      final revision = contextRevision;
      RoomCommandResult result;
      try {
        result = await (_port as RoomCommandsPort).execute(command);
      } on Object {
        result = const RoomCommandResult('rejected', error: 'unavailable');
      }
      return _disposed || epoch != _epoch || revision != contextRevision
          ? const RoomCommandResult('stale', error: 'contextChanged')
          : result;
    }
    final epoch = ++_epoch;
    busy = true;
    writing = true;
    _commandFeedbackTimer?.cancel();
    commandMessage = null;
    notifyListeners();
    RoomCommandResult result;
    try {
      result = await (_port as RoomCommandsPort).execute(command);
    } on Object {
      result = const RoomCommandResult('unknown', error: 'outcomeUnknown');
    }
    if (_disposed || epoch != _epoch) return const RoomCommandResult('stale');
    busy = false;
    writing = false;
    commandMessage = result.error ?? result.status;
    _pendingApplicationRoomId = commandMessage == 'pending'
        ? command.data['roomId'] as String?
        : null;
    if (result.status == 'targets') commandMessage = result.error;
    if (command.operation == RoomOperation.inviteDecline && result.accepted) {
      commandMessage = 'invitationDeclined';
    }
    commandNeedsRefresh =
        result.status == 'unknown' || result.error == 'refreshRequired';
    if (commandNeedsRefresh) {
      directory = null;
      selectedRoomId = null;
      state = RoomReadState.unavailable;
      failure = 'refreshRequired';
    } else if (result.directory != null) {
      directory = result.directory;
      state = RoomReadState.ready;
      _reconcileApplicationFeedback();
      final rooms = directory!.rooms;
      selectedRoomId =
          directory!.currentRoomId ??
          (rooms.any((room) => room.id == selectedRoomId)
              ? selectedRoomId
              : rooms.firstOrNull?.id);
    }
    _syncChat(verified: result.directory != null);
    if (result.error == null &&
        const {
          'joined',
          'left',
          'closed',
          'updated',
          'approved',
          'declined',
          'invited',
          'revoked',
          'removed',
          'hostTransferred',
          'resolved',
        }.contains(result.status)) {
      final feedback = commandMessage;
      _commandFeedbackTimer = Timer(const Duration(seconds: 5), () {
        _commandFeedbackTimer = null;
        if (_disposed || commandMessage != feedback) return;
        commandMessage = null;
        notifyListeners();
      });
    }
    notifyListeners();
    // A foreground command may retire an in-flight background read. Its
    // completion must restart the existing scheduler, not strand refreshes.
    _scheduleRefresh();
    return result;
  }

  String? get previewScene => _port is PartyRoomsPreviewControl
      ? (_port as PartyRoomsPreviewControl).previewScene
      : null;

  Future<void> selectPreviewScene(String scene) async {
    if (busy ||
        _disposed ||
        _port is! PartyRoomsPreviewControl ||
        !const [
          'directory',
          'current',
          'host',
          'empty',
          'error',
        ].contains(scene)) {
      return;
    }
    (_port as PartyRoomsPreviewControl).selectPreviewScene(scene);
    await refresh();
  }

  PartyRoom? get selectedRoom {
    for (final room in directory?.rooms ?? <PartyRoom>[]) {
      if (room.id == selectedRoomId) return room;
    }
    return null;
  }

  void enter() {
    if (_disposed || _active) return;
    _active = true;
    chat?.setVisible(true);
    unawaited(refresh(reuseFresh: _sessionStarted));
  }

  void leave() {
    if (_disposed || !_active) return;
    _active = false;
    chat?.setVisible(false);
    contextRevision++;
    if (_sessionStarted) return;
    chat?.setRoom(null);
    _refreshTimer?.cancel();
    _epoch++;
    busy = false;
    writing = false;
  }

  void select(String id) {
    if (directory?.currentRoomId != null ||
        writing ||
        !(directory?.rooms.any((room) => room.id == id) ?? false)) {
      return;
    }
    selectedRoomId = id;
    notifyListeners();
  }

  /// A notification click may race the normal background read. Wait for that
  /// read, then obtain a fresh authorized snapshot instead of navigating a cache.
  Future<bool> refreshForNotification() async {
    if (_disposed) return false;
    if (busy) {
      final idle = Completer<void>();
      void changed() {
        if (!busy && !idle.isCompleted) idle.complete();
      }

      addListener(changed);
      try {
        await idle.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        return false;
      } finally {
        removeListener(changed);
      }
    }
    if (_disposed) return false;
    await refresh();
    return !_disposed && !busy && state == RoomReadState.ready;
  }

  /// Navigation alone may reuse recent data; commands and explicit refreshes
  /// still read authoritative state. Account invalidation clears ready state.
  Future<void> refresh({
    bool reuseFresh = false,
    bool foreground = false,
  }) async {
    if (_disposed || busy) return;
    final age = _lastSuccessfulRead == null
        ? null
        : _now().difference(_lastSuccessfulRead!);
    if (reuseFresh &&
        state == RoomReadState.ready &&
        directory != null &&
        !commandNeedsRefresh &&
        age != null &&
        !age.isNegative &&
        age < refreshInterval) {
      return;
    }
    final epoch = ++_epoch;
    busy = true;
    _manualRefreshEpoch = foreground ? epoch : null;
    notifyListeners();
    RoomReadResult result;
    try {
      result = await _port.read();
    } on Object {
      result = const RoomReadResult(RoomReadState.unavailable);
    }
    if (_disposed || epoch != _epoch) return;
    busy = false;
    state = result.state;
    failure = result.failure;
    directory = result.state == RoomReadState.ready ? result.directory : null;
    if (state == RoomReadState.ready && directory == null) {
      state = RoomReadState.unavailable;
      failure = 'invalidResponse';
    }
    if (state == RoomReadState.ready) {
      // Only a valid authoritative directory resolves the readback warning.
      // Failed/invalid reads cannot unlock an uncertain write or erase its
      // feedback; this recovery never replays the original command.
      if (commandNeedsRefresh &&
          const {
            'refreshRequired',
            'outcomeUnknown',
          }.contains(commandMessage)) {
        commandMessage = null;
      }
      commandNeedsRefresh = false;
      _reconcileApplicationFeedback();
    }
    final rooms = directory?.rooms ?? <PartyRoom>[];
    _lastSuccessfulRead = state == RoomReadState.ready ? _now() : null;
    selectedRoomId =
        directory?.currentRoomId ??
        (rooms.any((r) => r.id == selectedRoomId)
            ? selectedRoomId
            : rooms.isEmpty
            ? null
            : rooms.first.id);
    _syncChat(verified: state == RoomReadState.ready);
    notifyListeners();
    _scheduleRefresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _commandFeedbackTimer?.cancel();
    chat?.removeListener(_updateActivity);
    chat?.dispose();
    activityCount.dispose();
    pendingCount.dispose();
    _refreshTimer?.cancel();
    _epoch++;
    unawaited(_subscription.cancel());
    unawaited(_port.close());
    super.dispose();
  }
}
