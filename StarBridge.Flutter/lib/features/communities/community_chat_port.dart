import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract interface class CommunityChatPort {
  Stream<void> get invalidations;
  bool get chatAvailable;
  bool get chatReadReceiptsAvailable;
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  );
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  });
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  );
}

final class CommunityChatReadReceipt {
  const CommunityChatReadReceipt(this.status, {this.error, this.readThrough});
  factory CommunityChatReadReceipt.parse(
    Map<String, Object?> row,
    String targetRef,
    CommunityChatMessage message,
  ) {
    if (_number(row, 'schemaVersion') != 1 ||
        _reference(row, 'targetRef') != targetRef ||
        _reference(row, 'messageRef') != message.messageRef) {
      throw const FormatException();
    }
    final status = _text(row, 'status', 16);
    final error = row['error'];
    if (!['accepted', 'rejected', 'unknown'].contains(status) ||
        error != null && (error is! String || error.length > 64)) {
      throw const FormatException();
    }
    if (status == 'accepted') {
      final through = _number(row, 'readThroughSequence');
      if (error != null || through < message.sequence) {
        throw const FormatException();
      }
      return CommunityChatReadReceipt(status, readThrough: through);
    }
    if (row['readThroughSequence'] != null) {
      throw const FormatException();
    }
    return CommunityChatReadReceipt(status, error: error as String?);
  }
  final String status;
  final String? error;
  final int? readThrough;
}

final class CommunityChatMessage {
  CommunityChatMessage.parse(Map<String, Object?> row)
    : sequence = _number(row, 'sequence'),
      localRequestId = row['localRequestId'] == null
          ? null
          : _reference(row, 'localRequestId'),
      messageRef = _reference(row, 'messageRef'),
      senderRef = _reference(row, 'senderRef'),
      callsign = _text(row, 'senderCallsign', 512),
      gameId = _text(row, 'senderGameId', 512),
      roleTitle = _text(row, 'senderRoleTitle', 128),
      roleColor = _text(row, 'senderRoleColor', 7),
      text = _text(row, 'text', 1000, multiline: true),
      createdAt = _date(row, 'createdAt'),
      isSelf = _flag(row, 'isSelf'),
      hasAvatar = _flag(row, 'hasAvatar'),
      avatarVersion = row['avatarVersion'] == null
          ? null
          : _text(row, 'avatarVersion', 64),
      hasAttachment = _flag(row, 'hasAttachment') {
    if (sequence <= 0 || !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(roleColor)) {
      throw const FormatException();
    }
    if (avatarVersion != null &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(avatarVersion!)) {
      throw const FormatException();
    }
  }
  final int sequence;
  final String? localRequestId;
  final String? avatarVersion;
  final String messageRef,
      senderRef,
      callsign,
      gameId,
      roleTitle,
      roleColor,
      text;
  final DateTime createdAt;
  final bool isSelf, hasAvatar, hasAttachment;
}

final class CommunityChatPage {
  CommunityChatPage.parse(Map<String, Object?> row)
    : targetRef = _reference(row, 'targetRef'),
      localHistoryUnavailable = row['localHistoryUnavailable'] == true,
      unreadCount = _number(row, 'unreadCount'),
      latestSequence = _number(row, 'latestSequence'),
      oldestSequence = _number(row, 'oldestSequence'),
      canSend = _flag(row, 'canSend'),
      hasOlder = _flag(row, 'hasOlder'),
      serverTime = _date(row, 'serverTime'),
      messages = List.unmodifiable(
        _rows(row['messages']).map((v) => CommunityChatMessage.parse(v)),
      ) {
    if (row['schemaVersion'] != 1 ||
        unreadCount > 500 ||
        oldestSequence != (messages.firstOrNull?.sequence ?? 0) ||
        messages.isEmpty && hasOlder ||
        messages.map((v) => v.messageRef).toSet().length != messages.length) {
      throw const FormatException();
    }
    var previous = 0;
    for (final message in messages) {
      if (message.sequence <= previous || message.sequence > latestSequence) {
        throw const FormatException();
      }
      previous = message.sequence;
    }
  }
  final String targetRef;
  final int unreadCount, latestSequence, oldestSequence;
  final bool canSend, hasOlder;
  final bool localHistoryUnavailable;
  final DateTime serverTime;
  final List<CommunityChatMessage> messages;
}

final class CommunityChatDetail {
  const CommunityChatDetail(this.avatar, this.attachment);
  final String? avatar;
  final Map<String, Object?>? attachment;
  factory CommunityChatDetail.parse(Map<String, Object?> row) {
    final avatar = row['avatarImageData'];
    if (avatar != null) {
      if (avatar is! String ||
          avatar.length > 700000 ||
          !RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,')
              .hasMatch(avatar)) {
        throw const FormatException();
      }
      final bytes = base64Decode(avatar.substring(avatar.indexOf(',') + 1));
      if (bytes.length < 8 || bytes.length > 512 * 1024) {
        throw const FormatException();
      }
    }
    Map<String, Object?>? attachment;
    if (row['attachment'] != null) {
      final value = _map(row['attachment']);
      if (value['kind'] != 'overlay_preset') throw const FormatException();
      final package = _text(
        value,
        'overlayPresetPackage',
        96 * 1024,
        multiline: true,
      );
      // WPF/Host exports PascalCase; older shared packages may use camelCase.
      // Keep the original package bytes for Host validation/import.
      final rawBody = _map(jsonDecode(package));
      final body = <String, Object?>{};
      for (final entry in rawBody.entries) {
        final key = entry.key.toLowerCase();
        if (body.containsKey(key) ||
            !{'version', 'name', 'settings', 'layout'}.contains(key)) {
          throw const FormatException();
        }
        body[key] = entry.value;
      }
      if (body['version'] != 1 ||
          !['name', 'settings', 'layout'].every(
            (key) =>
                body[key] is String && (body[key] as String).trim().isNotEmpty,
          )) {
        throw const FormatException();
      }
      attachment = Map.unmodifiable({
        'kind': 'overlay_preset',
        'title': _text(value, 'title', 512),
        'summary': _text(value, 'summary', 2048, multiline: true),
        'overlayPresetPackage': package,
      });
    }
    return CommunityChatDetail(avatar as String?, attachment);
  }
}

Future<CommunityChatDetail> assembleCommunityChatDetail(
  CommunityChatPort port,
  String targetRef,
  String messageRef, {
  required void Function() checkCurrent,
}) async {
  final builder = BytesBuilder(copy: false);
  String? version;
  int? total;
  var offset = 0;
  while (true) {
    checkCurrent();
    final row = await port.readChatDetail(
      targetRef,
      messageRef,
      offset,
      version,
    );
    checkCurrent();
    final hash = _text(row, 'version', 64), size = _number(row, 'totalBytes');
    if (row['schemaVersion'] != 1 ||
        row['targetRef'] != targetRef ||
        row['messageRef'] != messageRef ||
        row['offset'] != offset ||
        size <= offset ||
        size > 2 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        version != null && (version != hash || total != size)) {
      throw const FormatException();
    }
    final bytes = base64Decode(_text(row, 'data', 256 * 1024));
    if (bytes.length != (size - offset).clamp(0, 192 * 1024)) {
      throw const FormatException();
    }
    version = hash;
    total = size;
    offset += bytes.length;
    if (row['next'] != (offset < size ? offset : null)) {
      throw const FormatException();
    }
    builder.add(bytes);
    if (offset == size) break;
  }
  final bytes = builder.takeBytes();
  if (sha256.convert(bytes).toString() != version) {
    throw const FormatException();
  }
  checkCurrent();
  return CommunityChatDetail.parse(_map(jsonDecode(utf8.decode(bytes))));
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : throw const FormatException();
List<Map<String, Object?>> _rows(Object? value) =>
    value is List && value.length <= 50
    ? value.map(_map).toList()
    : throw const FormatException();
int _number(Map<String, Object?> row, String key) =>
    row[key] is int &&
        (row[key] as int) >= 0 &&
        (row[key] as int) < 0x7fffffffffffffff
    ? row[key] as int
    : throw const FormatException();
bool _flag(Map<String, Object?> row, String key) =>
    row[key] is bool ? row[key] as bool : throw const FormatException();
String _text(
  Map<String, Object?> row,
  String key,
  int max, {
  bool multiline = false,
}) {
  final value = row[key];
  if (value is! String ||
      value.length > max ||
      RegExp(
        multiline ? r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' : r'[\x00-\x1f\x7f]',
      ).hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}

String _reference(Map<String, Object?> row, String key) {
  final value = _text(row, key, 32);
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) throw const FormatException();
  return value;
}

DateTime _date(Map<String, Object?> row, String key) =>
    DateTime.tryParse(_text(row, key, 64)) ?? (throw const FormatException());
