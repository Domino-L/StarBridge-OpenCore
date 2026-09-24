import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'communities_module.dart';
import 'community_chat_port.dart';
import 'community_chat_send_port.dart';
import 'community_preset_port.dart';
import 'community_workspace_port.dart';

/// Explicit example session only: no Host calls and no persistent mutations.
final class ExampleCommunityChat {
  final _rooms = <String, _Conversation>{};
  final _receipts = <(String, String), (String, CommunityChatSendOutcome)>{};
  final _presets = <String, Map<String, Object?>>{
    'example-preset': {
      'Version': 1,
      'Name': '示例浮层预设',
      'Settings': '0,CallsignAndGameName,0,0,0',
      'Layout': 'Notice,0.3,0,0.4,0.06;Squads,0,0.4,0.16,0.12;Members,0,0.52,0.16,0.2;Chat,0,0.72,0.16,0.16',
    },
  };
  var _revision = 1, _sequence = 2000;
  bool _closed = false;
  String _ref() => (++_sequence).toRadixString(16).padLeft(32, '0');
  void _check() {
    if (_closed) throw const CommunityFailure('unavailable');
  }

  Future<CommunityWorkspace> _access(
    String target,
    Future<CommunityWorkspace> Function() workspace,
  ) async {
    _check();
    final page = await workspace();
    _check();
    if (page.targetRef != target) throw const CommunityFailure('notAllowed');
    return page;
  }

  Map<String, Object?> _row(
    CommunityWorkspaceMember sender,
    int sequence,
    String text,
    DateTime time, {
    String? request,
    bool attachment = false,
  }) => {
    'sequence': sequence,
    'messageRef': _ref(),
    'senderRef': sender.memberRef,
    'senderCallsign': sender.callsign,
    'senderGameId': sender.gameName,
    'senderRoleTitle': sender.roleTitle,
    'senderRoleColor': sender.roleColor,
    'text': text,
    'createdAt': time.toUtc().toIso8601String(),
    'isSelf': sender.isSelf,
    'hasAvatar': false,
    'hasAttachment': attachment,
    'localRequestId': request,
  };

  _Conversation _conversation(
    CommunityWorkspace page,
    bool seed,
  ) => _rooms.putIfAbsent(page.targetRef, () {
    final room = _Conversation();
    if (!seed) return room;
    final now = DateTime.now().toUtc();
    final people = page.members.take(3).toList();
    if (people.isEmpty) return room;
    for (var i = 0; i < 56; i++) {
      final sender = people[i % people.length];
      final text = switch (i) {
        54 => '欢迎来到组织聊天，出发前可以在这里确认安排。',
        55 => '收到，准备好后在这里回复。',
        _ =>
          '示例历史消息 ${i + 1}：${['讨论本周的集合安排。', '出发前确认补给和分工。', '返回后分享本次探索收获。'][i % 3]}',
      };
      room.messages.add(
        _row(
          sender,
          ++room.latest,
          text,
          now.subtract(Duration(minutes: (56 - i) * 7)),
        ),
      );
    }
    room.readThrough = 53;
    return room;
  });

  Future<CommunityChatPage> read(
    String target, {
    required Future<CommunityWorkspace> Function() workspace,
    required bool seed,
    int after = 0,
    int before = 0,
  }) async {
    final page = await _access(target, workspace);
    if (after < 0 || before < 0 || after > 0 && before > 0) {
      throw const CommunityFailure('dataInvalid');
    }
    final room = _conversation(page, seed);
    final candidates = room.messages
        .where(
          (r) => before > 0
              ? (r['sequence'] as int) < before
              : (r['sequence'] as int) > after,
        )
        .toList();
    final messages = after > 0
        ? candidates.take(50).toList()
        : candidates
              .skip((candidates.length - 50).clamp(0, candidates.length))
              .toList();
    final oldest = messages.firstOrNull?['sequence'] as int? ?? 0;
    return CommunityChatPage.parse({
      'schemaVersion': 1,
      'targetRef': target,
      'unreadCount': room.messages
          .where(
            (r) =>
                r['isSelf'] == false &&
                (r['sequence'] as int) > room.readThrough,
          )
          .length
          .clamp(0, 500),
      'latestSequence': room.latest,
      'oldestSequence': oldest,
      'canSend': page.members.any((m) => m.isSelf),
      'hasOlder':
          oldest > 0 &&
          room.messages.any((r) => (r['sequence'] as int) < oldest),
      'serverTime': DateTime.now().toUtc().toIso8601String(),
      'messages': messages,
    });
  }

  Future<Map<String, Object?>> detail(
    String target,
    String messageRef,
    int offset,
    String? version, {
    required Future<CommunityWorkspace> Function() workspace,
    required bool seed,
  }) async {
    final room = _conversation(await _access(target, workspace), seed);
    if (!room.messages.any((r) => r['messageRef'] == messageRef)) {
      throw const CommunityFailure('refreshRequired');
    }
    final bytes = utf8.encode(
      jsonEncode({
        'avatarImageData': null,
        'attachment': room.attachments[messageRef],
      }),
    );
    final hash = sha256.convert(bytes).toString();
    if (offset < 0 ||
        offset >= bytes.length ||
        offset % (192 * 1024) != 0 ||
        version != null && version != hash ||
        offset > 0 && version == null) {
      throw const CommunityFailure('refreshRequired');
    }
    final end = (offset + 192 * 1024).clamp(0, bytes.length);
    return {
      'schemaVersion': 1,
      'targetRef': target,
      'messageRef': messageRef,
      'offset': offset,
      'next': end < bytes.length ? end : null,
      'totalBytes': bytes.length,
      'version': hash,
      'data': base64Encode(bytes.sublist(offset, end)),
    };
  }

  Future<CommunityChatReadReceipt> markRead(
    String target,
    CommunityChatMessage message, {
    required Future<CommunityWorkspace> Function() workspace,
    required bool seed,
  }) async {
    final room = _conversation(await _access(target, workspace), seed);
    if (!room.messages.any(
      (r) =>
          r['messageRef'] == message.messageRef &&
          r['sequence'] == message.sequence,
    )) {
      return const CommunityChatReadReceipt(
        'rejected',
        error: 'refreshRequired',
      );
    }
    if (message.sequence > room.readThrough) {
      room.readThrough = message.sequence;
    }
    return CommunityChatReadReceipt('accepted', readThrough: room.readThrough);
  }

  Future<CommunityChatSendOutcome> send(
    CommunityChatSendIntent intent, {
    required Future<CommunityWorkspace> Function() workspace,
    required bool seed,
  }) async {
    CommunityWorkspace page;
    try {
      page = await _access(intent.targetRef, workspace);
    } on CommunityFailure catch (error) {
      return CommunityChatSendOutcome('rejected', error: error.code);
    }
    final sender = page.members.where((m) => m.isSelf).firstOrNull;
    if (sender == null) {
      return const CommunityChatSendOutcome('rejected', error: 'notAllowed');
    }
    final key = (intent.targetRef, intent.requestId);
    final fingerprint = jsonEncode(intent.toPayload());
    final receipt = _receipts[key];
    if (receipt != null) {
      return receipt.$1 == fingerprint
          ? receipt.$2
          : const CommunityChatSendOutcome('rejected', error: 'intentConflict');
    }
    final room = _conversation(page, seed);
    final row = _row(
      sender,
      ++room.latest,
      intent.text,
      DateTime.now().toUtc(),
      request: intent.requestId,
      attachment: intent.attachment != null,
    );
    room.messages.add(row);
    if (intent.attachment != null) {
      room.attachments[row['messageRef'] as String] = checkedCommunityPreset(
        intent.attachment!,
      );
    }
    if (room.messages.length > 500) {
      final removed = room.messages.removeAt(0);
      room.attachments.remove(removed['messageRef']);
    }
    final result = CommunityChatSendOutcome('accepted', sequence: room.latest);
    _receipts[key] = (fingerprint, result);
    return result;
  }

  Future<CommunityPresetCatalog> presets() async {
    _check();
    return CommunityPresetCatalog.parse({
      'schemaVersion': 1,
      'revision': _revision,
      'presets': [
        for (final entry in _presets.entries)
          {'id': entry.key, 'name': entry.value['Name']},
      ],
    });
  }

  Future<Map<String, Object?>> export(String id, int revision) async {
    _check();
    if (revision != _revision || !_presets.containsKey(id)) {
      throw const CommunityFailure('presetChanged');
    }
    return checkedCommunityPreset({
      'kind': 'overlay_preset',
      'title': _presets[id]!['Name'],
      'summary': '示例预设 · 仅在示例场景中使用',
      'overlayPresetPackage': jsonEncode(_presets[id]),
    });
  }

  Future<String> importPreset(
    Map<String, Object?> attachment,
    int revision,
  ) async {
    _check();
    if (revision != _revision) throw const CommunityFailure('presetChanged');
    final checked = checkedCommunityPreset(attachment);
    final raw = Map<String, Object?>.from(
      jsonDecode(checked['overlayPresetPackage'] as String) as Map,
    );
    final value = {for (final e in raw.entries) e.key.toLowerCase(): e.value};
    var stem = presetText(value['name'], 64);
    final suffix = ' (${_presets.length + 1})';
    while ((stem + suffix).length > 64) {
      stem = String.fromCharCodes(stem.runes.take(stem.runes.length - 1));
    }
    final name = stem + suffix;
    _presets['example-import-${++_revision}'] = {
      'Version': 1,
      'Name': name,
      'Settings': value['settings'],
      'Layout': value['layout'],
    };
    return name;
  }

  void close() {
    _closed = true;
    _rooms.clear();
    _receipts.clear();
    _presets.clear();
  }
}

final class _Conversation {
  int latest = 0, readThrough = 0;
  final messages = <Map<String, Object?>>[];
  final attachments = <String, Map<String, Object?>>{};
}
