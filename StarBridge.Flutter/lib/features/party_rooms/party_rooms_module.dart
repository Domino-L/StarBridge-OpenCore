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
    this.isSelf = false,
    this.serverRegion = '',
    this.presenceKey = 'presence.unknown',
  });
  final String callsign, gameId, presence, location, ship, shard;
  final bool isHost;
  final String? avatarData;
  final String? userRef;
  final bool isSelf;
  final String serverRegion;
  final String presenceKey;
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
    List<RoomApplication> pendingApplications = const [],
  }) : members = List.unmodifiable(members),
       pendingApplications = List.unmodifiable(pendingApplications),
       tags = List.unmodifiable(tags);
  final List<RoomTag> tags;
  final String leaderServerRegion;
  final String leaderGameVersion;
  final String roomCode;
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
  });
  final String id, callsign, gameId;
  final DateTime createdAt;
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
    required this.serverTime,
    List<RoomTag> tagOptions = const [],
    List<RoomInvitation> receivedInvitations = const [],
    List<RoomInvitation> sentInvitations = const [],
  }) : tagOptions = List.unmodifiable(tagOptions),
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
  final DateTime serverTime;
  final List<RoomTag> tagOptions;
  final List<RoomInvitation> receivedInvitations, sentInvitations;
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
      commandMessage = null;
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
  bool commandNeedsRefresh = false;
  int contextRevision = 0;
  bool get supportsCommands =>
      _port is RoomCommandsPort && (_port as RoomCommandsPort).supportsCommands;
  bool get canCommand =>
      !_disposed &&
      supportsCommands &&
      !busy &&
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
        ].contains(command.operation) &&
        (!canManage || command.data['roomId'] != directory?.currentRoomId)) {
      return const RoomCommandResult('rejected', error: 'notHost');
    }
    final epoch = ++_epoch;
    busy = true;
    writing = true;
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
      final rooms = directory!.rooms;
      selectedRoomId =
          directory!.currentRoomId ??
          (rooms.any((room) => room.id == selectedRoomId)
              ? selectedRoomId
              : rooms.firstOrNull?.id);
    }
    _syncChat(verified: result.directory != null);
    notifyListeners();
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
  Future<void> refresh({bool reuseFresh = false, bool foreground = false}) async {
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
    if (state == RoomReadState.ready) commandNeedsRefresh = false;
    failure = result.failure;
    directory = result.state == RoomReadState.ready ? result.directory : null;
    if (state == RoomReadState.ready && directory == null) {
      state = RoomReadState.unavailable;
      failure = 'invalidResponse';
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
