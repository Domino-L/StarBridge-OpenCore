import 'dart:async';

import 'package:flutter/foundation.dart';

import 'room_preset_port.dart';
import '../communities/community_invitation_attachment.dart';

final class RoomChatMessage {
  const RoomChatMessage({
    required this.sequence,
    required this.id,
    required this.sender,
    required this.text,
    required this.time,
    this.kind = 'player',
    this.attachment,
    this.isSelf = false,
    this.avatar,
    this.userRef,
    this.gameId = '',
    this.communityInvitation,
  });
  final int sequence;
  final String id, sender, text, kind;
  final DateTime time;
  final Map<String, Object?>? attachment;
  final bool isSelf;
  final String? avatar;
  final String? userRef;
  final String gameId;
  final CommunityInvitationAttachment? communityInvitation;
}

final class RoomChatPage {
  const RoomChatPage(this.messages, this.latest, this.hasOlder);
  final List<RoomChatMessage> messages;
  final int latest;
  final bool hasOlder;
}

final class RoomChatFailure implements Exception {
  const RoomChatFailure(this.code);
  final String code;
}

abstract interface class RoomChatPort {
  bool get available;
  Future<RoomChatPage> read(String roomId, {int after = 0, int before = 0});
  Future<RoomChatMessage> send(String roomId, String text);
}

abstract interface class RoomChatProvider {
  RoomChatPort get roomChat;
}

/// One account/room lane. Cursor advances only through messages actually read.
final class RoomChatModule extends ChangeNotifier {
  RoomChatModule(this.port, {this.interval = const Duration(seconds: 8)});
  final RoomChatPort port;
  final Duration interval;
  String? roomId, error;
  String draft = '';
  Map<String, Object?>? attachmentDraft;
  Future<void> Function()? onPresetImported;
  List<RoomChatMessage> messages = const [];
  bool loading = false, sending = false, hasOlder = false, uncertain = false;
  bool followLatest = true;
  bool _accessDenied = false;
  int unread = 0, _epoch = 0;
  int _readCursor = 0;
  bool _disposed = false;
  bool _visible = true, _foreground = true, _paused = false;
  bool _baselineEstablished = false;
  bool _importing = false;
  Timer? _timer;
  bool get available => port.available && !_accessDenied && !_paused;
  bool get _readingLatest =>
      available && _visible && _foreground && followLatest;

  void setVisible(bool value) {
    _visible = value;
    _acknowledgeVisible();
  }

  void setForeground(bool value) {
    _foreground = value;
    _acknowledgeVisible();
  }

  void _acknowledgeVisible() {
    if (!_disposed && _readingLatest && unread > 0) {
      unread = 0;
      notifyListeners();
    }
  }

  /// A transient directory failure suspends reads without losing the draft.
  void setPaused(bool value) {
    if (_disposed || _paused == value) return;
    _paused = value;
    if (value) {
      _epoch++;
      _timer?.cancel();
      loading = false;
      if (sending) {
        sending = false;
        uncertain = true;
        error = 'outcomeUnknown';
      }
    } else if (roomId != null && available) {
      unawaited(refresh());
    }
    notifyListeners();
  }

  RoomPresetPort? get presets =>
      port is RoomPresetPort ? port as RoomPresetPort : null;
  bool get presetsAvailable =>
      available && (presets?.presetsAvailable ?? false);
  int get contextRevision => _epoch;
  bool isCurrentContext(int revision) =>
      !_disposed && revision == _epoch && roomId != null && available;
  bool get hasDraft => draft.trim().isNotEmpty || attachmentDraft != null;

  Future<bool> preparePreset(
    RoomPresetChoice choice,
    int revision,
    int context,
  ) async {
    if (!isCurrentContext(context) ||
        !presetsAvailable ||
        sending ||
        uncertain) {
      return false;
    }
    try {
      final attachment = await presets!.exportPreset(choice.id, revision);
      if (!isCurrentContext(context) || sending || uncertain) return false;
      attachmentDraft = Map.unmodifiable(attachment);
      error = null;
      notifyListeners();
      return true;
    } on RoomChatFailure catch (failure) {
      if (isCurrentContext(context)) {
        error = failure.code;
        notifyListeners();
      }
      return false;
    }
  }

  void clearAttachment() {
    if (sending || uncertain) return;
    attachmentDraft = null;
    notifyListeners();
  }

  Future<String?> importPreset(
    RoomChatMessage message,
    int revision,
    int context,
  ) async {
    if (!isCurrentContext(context) ||
        _importing ||
        !presetsAvailable ||
        !messages.any(
          (item) =>
              item.id == message.id &&
              item.attachment?['overlayPresetPackage'] ==
                  message.attachment?['overlayPresetPackage'],
        )) {
      return null;
    }
    final package = message.attachment?['overlayPresetPackage'];
    if (message.attachment?['kind'] != 'overlay_preset' || package is! String) {
      return null;
    }
    _importing = true;
    try {
      final name = await presets!.importPreset(package, revision);
      await onPresetImported?.call();
      return isCurrentContext(context) ? name : null;
    } on RoomChatFailure catch (failure) {
      if (isCurrentContext(context)) {
        error = failure.code;
        notifyListeners();
      }
      return null;
    } finally {
      _importing = false;
    }
  }

  void setRoom(String? value, {bool verified = false}) {
    if (_disposed || (roomId == value && !(verified && _accessDenied))) return;
    _epoch++;
    _timer?.cancel();
    roomId = value;
    _accessDenied = false;
    messages = const [];
    draft = '';
    attachmentDraft = null;
    error = null;
    _readCursor = 0;
    _baselineEstablished = false;
    loading = sending = uncertain = hasOlder = false;
    unread = 0;
    followLatest = true;
    notifyListeners();
    if (value != null && available) unawaited(refresh());
  }

  void setFollowing(bool value) {
    if (followLatest == value && (!value || unread == 0)) return;
    followLatest = value;
    if (_readingLatest) unread = 0;
    notifyListeners();
  }

  void acknowledgeUncertain() {
    if (_accessDenied) return;
    uncertain = false;
    error = null;
    notifyListeners();
  }

  void _failure(String code) {
    error = code;
    if (const [
      'identityUnavailable',
      'forbidden',
      'notMember',
    ].contains(code)) {
      // A confirmed loss of access must remove private cached content now,
      // without waiting for the independent directory refresh.
      _accessDenied = true;
      _timer?.cancel();
      messages = const [];
      draft = '';
      attachmentDraft = null;
      unread = _readCursor = 0;
      uncertain = hasOlder = false;
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_disposed && roomId != null && available) {
      _timer = Timer(interval, () => unawaited(refresh()));
    }
  }

  void _merge(List<RoomChatMessage> incoming, {bool history = false}) {
    final byId = {for (final message in messages) message.id: message};
    var addedUnread = 0;
    for (final message in incoming) {
      if (!history &&
          _baselineEstablished &&
          !_readingLatest &&
          message.sequence > _readCursor &&
          !byId.containsKey(message.id)) {
        addedUnread++;
      }
      byId[message.id] = message;
    }
    final sorted = byId.values.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    if (sorted.map((message) => message.sequence).toSet().length !=
        sorted.length) {
      throw const RoomChatFailure('invalidResponse');
    }
    unread += addedUnread;
    messages = List.unmodifiable(
      sorted.length <= 500
          ? sorted
          : history
          ? sorted.take(500)
          : sorted.skip(sorted.length - 500),
    );
  }

  Future<void> refresh({bool older = false, bool latest = false}) async {
    if (_disposed || roomId == null || !available) return;
    if (loading || sending) {
      _schedule();
      return;
    }
    final epoch = _epoch, room = roomId!;
    loading = true;
    error = null;
    notifyListeners();
    try {
      for (var batch = 0; batch < 10; batch++) {
        final cursor = older || (latest && batch == 0) ? 0 : _readCursor;
        final page = await port.read(
          room,
          after: cursor,
          before: older ? messages.firstOrNull?.sequence ?? 0 : 0,
        );
        if (_disposed || epoch != _epoch) return;
        if (latest && batch == 0) {
          messages = const [];
          _readCursor = 0;
          followLatest = true;
          unread = 0;
        }
        if (older || cursor == 0) hasOlder = page.hasOlder;
        _merge(page.messages, history: older);
        if (!older) _baselineEstablished = true;
        if (!older && page.messages.isNotEmpty) {
          _readCursor = page.messages.last.sequence;
        }
        if (older || page.messages.isEmpty || _readCursor >= page.latest) break;
        if (_readCursor <= cursor) {
          throw const RoomChatFailure('invalidResponse');
        }
      }
    } on RoomChatFailure catch (failure) {
      if (epoch == _epoch && !_disposed) _failure(failure.code);
    } on Object {
      if (epoch == _epoch && !_disposed) error = 'unavailable';
    } finally {
      if (epoch == _epoch && !_disposed) {
        loading = false;
        notifyListeners();
        _schedule();
      }
    }
  }

  Future<bool> send() async {
    if (_disposed ||
        roomId == null ||
        !available ||
        sending ||
        loading ||
        uncertain ||
        !hasDraft ||
        (attachmentDraft != null && !presetsAvailable) ||
        draft.trim().length > 300) {
      return false;
    }
    final epoch = _epoch, room = roomId!, text = draft.trim();
    sending = true;
    error = null;
    notifyListeners();
    try {
      final attachment = attachmentDraft;
      final message = attachment == null
          ? await port.send(room, text)
          : await presets!.sendPreset(room, text, attachment);
      if (_disposed || epoch != _epoch) return false;
      // Locally sent messages never create unread activity.
      _merge([message], history: true);
      draft = '';
      attachmentDraft = null;
      return true;
    } on RoomChatFailure catch (failure) {
      if (epoch == _epoch && !_disposed) {
        _failure(failure.code);
        uncertain = failure.code == 'outcomeUnknown';
      }
    } on Object {
      if (epoch == _epoch && !_disposed) {
        error = 'outcomeUnknown';
        uncertain = true;
      }
    } finally {
      if (epoch == _epoch && !_disposed) {
        sending = false;
        notifyListeners();
        _schedule();
      }
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    super.dispose();
  }
}
