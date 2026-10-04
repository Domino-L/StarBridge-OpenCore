import 'dart:convert';

import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_chat_module.dart';
import '../../features/party_rooms/room_member_policy.dart';
import 'menu_feature_session.dart';
import 'menu_room_view.dart';
import 'menu_organization_avatars.dart';
import 'menu_room_lobby_projection.dart';

import 'menu_room_preset_commands.dart';
import 'menu_room_management_session.dart';
import 'menu_room_lobby_invitations.dart';

final class MenuRoomsSession extends MenuFeatureSession {
  MenuRoomsSession(
    this.port,
    void Function(Map<String, Object?>) publish, {
    this.chatOnly = false,
  }) : super(publish, port.invalidations) {
    if (chatOnly) _tab = 'chat';
  }
  final bool chatOnly;
  final _images = MenuOrganizationAvatars();
  final _lobby = MenuRoomLobbyProjection();
  final _state = MenuRoomCommandState();
  late final _lobbyInvitations = MenuRoomLobbyInvitations(
    this,
    port,
    _state,
    _lobby,
    _images,
  );
  late final _roomPreset = MenuRoomPresetCommands(this, port, _state);
  late final _management = MenuRoomManagementSession(this, port, _state);
  Map<String, Object?>? _lobbyReply;
  Map<String, Object?>? _settingsReply;
  // Reuse the shared read/write arbitration: a click retires the pending read,
  // while Host still validates current membership before a management write.
  @override
  bool get backgroundReads => true;
  @override
  Map<String, Object?>? failedRead(Object error) {
    _roomPreset.clear();
    return null;
  }

  @override
  Map<String, Object?>? get readingView =>
      currentView['state'] == 'ready' ? {...currentView} : null;
  int _before = 0, _sentRevision = 0;
  String _sendStatus = 'idle';
  final PartyRoomsPort port;
  String? _joinedRoom;
  String _tab = 'members';
  @override
  void reset() {
    _roomPreset.clear();
    _images.clear();
    _lobby.clear();
    _lobbyInvitations.clear();
    _management.clear();
    _lobbyReply = null;
    _settingsReply = null;
    changeScope();
    _state.selected = null;
    _joinedRoom = null;
    _tab = chatOnly ? 'chat' : 'members';
    _before = _sentRevision = 0;
    _sendStatus = 'idle';
    _state.notice = '';
    _state.uncertain = false;
    emit({'state': 'loading'});
  }

  @override
  Future<void> closePort() {
    _roomPreset.clear();
    _images.dispose();
    return port.close();
  }

  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation;
    final result = await port.read();
    if (!current(epoch) ||
        result.state != RoomReadState.ready ||
        result.directory == null) {
      throw StateError('unavailable');
    }
    final directory = result.directory!;
    // Membership loss is a return to discovery, not a request to preview the
    // former room if it happens to remain in the public directory.
    final leftRoom = _joinedRoom != null && directory.currentRoomId == null;
    _joinedRoom = directory.currentRoomId;
    if (directory.currentRoomId == null ||
        directory.currentRoomId != _state.selected ||
        _roomPreset.presetPort == null) {
      _roomPreset.clear();
    }
    final selection = chatOnly
        ? directory.currentRoomId
        : directory.currentRoomId ?? (leftRoom ? null : _state.selected);
    if (selection != _state.selected) {
      _lobbyInvitations.clear();
      _management.clear();
      _images.clear();
      changeScope();
      _before = _sentRevision = 0;
      _sendStatus = 'idle';
      _state.uncertain = false;
      _state.notice = '';
      _settingsReply = null;
    }
    _state.selected = selection;
    final room = directory.rooms
        .where((r) => r.id == _state.selected)
        .firstOrNull;
    final actions = <Map<String, Object?>>[];
    final rows = <Map<String, Object?>>[];
    final messagePresentation = <Map<String, Object?>>[];
    final memberPresentation = <Map<String, Object?>>[];
    final memberActions = <String, String>{};
    final memberTransferActions = <String, String>{};
    final commands =
        port is RoomCommandsPort && (port as RoomCommandsPort).supportsCommands;
    if (room == null) {
      if (chatOnly) {
        return {
          'title': '房间聊天',
          'notice': '尚未加入房间。请先在房间窗口加入，再回到这里聊天。',
          'rows': rows,
        };
      }
      final data = await _lobby.directory(directory, _images);
      if (!current(epoch)) throw StateError('retired');
      return {
        'title': '房间',
        'notice': _state.notice,
        'lobby': {
          'directory': data,
          'invitations': _lobbyInvitations.rows(directory),
          'invitationReply': _lobbyInvitations.reply,
          'reply': _lobbyReply,
          'actions': {
            ..._lobbyInvitations.actions(),
            if (commands && !_state.uncertain)
              for (final op in [
                RoomOperation.create,
                RoomOperation.resolve,
                RoomOperation.join,
              ])
                op.name: button(
                  op.name,
                  (value) => _lobbyCommand(op, value),
                  limit: 2048,
                )['key'],
          },
        },
        'buttons': [
          if (_state.uncertain)
            button('已核对当前结果', (_) async {
              _state.uncertain = false;
              _state.notice = '';
            }, confirm: '请先核对房间状态。继续不会重复执行上次操作。'),
        ],
      };
    } else {
      if (directory.currentRoomId == null) {
        actions.add(
          button('返回房间列表', (_) async {
            changeScope();
            _state.selected = null;
          }),
        );
      }
      if (!chatOnly) {
        actions.add(
          button('成员', (_) async {
            _tab = 'members';
          }),
        );
      }
      if (!chatOnly &&
          directory.currentRoomId == room.id &&
          port is RoomChatProvider) {
        actions.add(
          button('聊天', (_) async {
            _tab = 'chat';
          }),
        );
      }
      if (!chatOnly && commands && !_state.uncertain) {
        if (directory.currentRoomId == room.id) {
          actions.add(
            button(
              '退出房间',
              (_) => _command(
                RoomCommand(RoomOperation.leave, {'roomId': room.id}),
              ),
              confirm: '退出 ${room.title}？你将不再接收此房间的信息。',
            ),
          );
        } else if (!roomRecruitmentClosed(room, directory.serverTime) &&
            room.members.length < room.capacity &&
            directory.viewerPendingRoomIds?.contains(room.id) != true) {
          actions.add(
            button(
              room.admissionMode == 'approval' ? '申请加入' : '加入房间',
              (password) => _command(
                RoomCommand(RoomOperation.join, {
                  'roomId': room.id,
                  'password': password,
                }),
              ),
              input: room.passwordRequired ? '房间密码' : null,
              confirm: '加入 ${room.title}？需要审核的房间会先提交申请。',
            ),
          );
        }
      }
      if (directory.currentRoomId == room.id && port is RoomChatProvider) {
        final chat = (port as RoomChatProvider).roomChat;
        final page = await chat.read(room.id, before: _before);
        if (!current(epoch)) throw StateError('retired');
        for (final message in page.messages) {
          final member = message.isSelf
              ? room.members.where((m) => m.isSelf).singleOrNull
              : message.gameId.isEmpty
              ? null
              : room.members
                    .where((m) => m.gameId == message.gameId)
                    .singleOrNull;
          final avatar =
              await _images.logo(message.avatar) ??
              await _images.logo(member?.avatarData);
          if (!current(epoch)) throw StateError('retired');
          rows.add({
            'title': message.sender,
            'avatar': avatar,
            'detail':
                '${message.text}${message.attachment != null ? "\n[附件请在客户端查看]" : ""}',
          });
          messagePresentation.add({
            'kind': message.kind == 'player' ? 'player' : 'system',
            'self': message.isSelf,
            'time': message.time.toUtc().toIso8601String(),
          });
        }
        if (page.hasOlder && page.messages.isNotEmpty) {
          actions.add(
            button('较早消息', (_) async {
              _before = page.messages.first.sequence;
            }),
          );
        }
        if (_before > 0) {
          actions.add(
            button('最新消息', (_) async {
              _before = 0;
            }),
          );
        }
        if (chat.available && !_state.uncertain) {
          actions.add(
            button(
              '发送消息',
              (text) async {
                final value = text.trim();
                final attachment = _roomPreset.attachment;
                if (value.isEmpty && attachment == null || value.length > 300) {
                  return;
                }
                final active = accountEpoch;
                final sendEpoch = generation;
                if (attachment != null &&
                    !await _roomPreset.checkAuthority(
                      room.id,
                      active,
                      sendEpoch,
                    )) {
                  if (currentAccount(active) && current(sendEpoch)) {
                    _sendStatus = 'rejected';
                  }
                  return;
                }
                _state.uncertain = true;
                try {
                  final receipt =
                      await (attachment == null
                              ? chat.send(room.id, value)
                              : _roomPreset.presetPort!.sendPreset(
                                  room.id,
                                  value,
                                  attachment,
                                ))
                          .timeout(const Duration(seconds: 12));
                  if (!currentAccount(active) || !current(sendEpoch)) return;
                  if (!receipt.isSelf ||
                      receipt.text != value ||
                      receipt.sequence <= 0) {
                    throw StateError('unconfirmed');
                  }
                  _state.notice = '消息已发送。';
                  _sentRevision++;
                  _sendStatus = 'sent';
                  _before = 0;
                  _state.uncertain = false;
                  _roomPreset.sent();
                } on Object {
                  if (currentAccount(active) && current(sendEpoch)) {
                    _state.uncertain = true;
                    _state.notice = '发送结果未确认，请查看记录后再操作。';
                    _sendStatus = 'unknown';
                  }
                }
              },
              input: '输入消息',
              limit: 300,
            ),
          );
        }
      }
      if (!chatOnly) {
        for (final member in room.members) {
          final avatar = await _images.logo(member.avatarData);
          if (!current(epoch)) throw StateError('retired');
          memberPresentation.add(menuRoomMember(member, avatar));
          final row = <String, Object?>{
            'title': member.displayName,
            'detail': [
              member.isHost ? '房主' : '成员',
              member.presence,
              member.ship,
              member.location,
              member.shard,
            ].where((v) => v.isNotEmpty).join(' · '),
            'buttons': [
              if (!chatOnly &&
                  commands &&
                  !_state.uncertain &&
                  directory.currentRoomId == room.id &&
                  port is RoomManagementPort &&
                  (port as RoomManagementPort).supportsManagement &&
                  canRemoveRoomMember(room, member))
                button(
                  '移出房间',
                  (_) => _command(
                    RoomCommand(RoomOperation.remove, {
                      'roomId': room.id,
                      'removalToken': member.removalToken,
                    }),
                  ),
                  confirm: '将 ${member.displayName} 移出房间？移出后，对方将离开当前房间。',
                ),
              if (commands &&
                  !_state.uncertain &&
                  directory.supportsHostTransfer &&
                  directory.currentRoomId == room.id &&
                  port is RoomManagementPort &&
                  (port as RoomManagementPort).supportsManagement &&
                  canRemoveRoomMember(room, member))
                button(
                  '转移房主',
                  (_) => _command(
                    RoomCommand(RoomOperation.transferHost, {
                      'roomId': room.id,
                      'memberToken': member.removalToken,
                    }),
                  ),
                  confirm:
                      '将房主转移给 ${member.displayName}？你将留在房间，但不再拥有房主管理权限；原房主发出的待处理邀请将失效。',
                ),
            ],
          };
          final memberButtons = row['buttons'] as List<Map<String, Object?>>;
          for (final action in memberButtons) {
            final target = action['label'] == '转移房主'
                ? memberTransferActions
                : memberActions;
            target['${memberPresentation.length - 1}'] =
                action['key'] as String;
          }
          if (directory.currentRoomId == room.id && port is RoomChatProvider) {
            actions.addAll(memberButtons);
          } else {
            rows.add(row);
          }
        }
      }
    }
    if (_state.uncertain) {
      actions.add(
        button('已核对当前结果', (_) async {
          _state.uncertain = false;
          _state.notice = '';
          _sendStatus = 'idle';
        }, confirm: '请先核对房间与聊天记录。继续只解除操作锁定，不会重复执行上次操作。'),
      );
    }
    return {
      'title': room.title,
      'notice': _state.notice.isNotEmpty
          ? _state.notice
          : directory.currentRoomId == room.id
          ? ''
          : roomRecruitmentClosed(room, directory.serverTime)
          ? '该房间已停止招募。'
          : room.members.length >= room.capacity
          ? '房间已满。'
          : directory.viewerPendingRoomIds?.contains(room.id) == true
          ? '申请已提交，等待房主审核。'
          : '',
      'buttons': actions,
      'rows': rows,
      if (!chatOnly)
        'room': {
          'management': _management.projection(directory, room),
          'settings': {
            'tagOptions': MenuRoomLobbyProjection.tags(directory.tagOptions),
            'reply': _settingsReply,
            if (commands &&
                !_state.uncertain &&
                directory.currentRoomId == room.id &&
                room.viewerIsHost &&
                port is RoomManagementPort &&
                (port as RoomManagementPort).supportsManagement)
              'action': button(
                '房间设置',
                (value) => _updateSettings(room.id, value),
                limit: 2048,
              )['key'],
          },
          'tab': _tab,
          'code': room.roomCode,
          'goal': room.goal,
          'capacity': room.capacity,
          'memberCount': room.members.length,
          'tags': MenuRoomLobbyProjection.tags(room.tags),
          'isPublic': room.isPublic,
          'serverTime': directory.serverTime.toUtc().toIso8601String(),
          'expiresAt': room.expiresAt.toUtc().toIso8601String(),
          'recruitmentClosesAt': room.recruitmentClosesAt
              ?.toUtc()
              .toIso8601String(),
          'canChat':
              directory.currentRoomId == room.id && port is RoomChatProvider,
          'members': memberPresentation,
          'memberActions': memberActions,
          'memberTransferActions': memberTransferActions,
          'facts': {
            'language': room.language,
            'admission': room.admissionMode,
            'voice': room.voice,
            'eligibility': room.eligibility,
            'password': room.passwordRequired ? 'required' : 'notRequired',
          },
        },
      if (directory.currentRoomId == room.id && port is RoomChatProvider)
        'chat': {
          'preset': _roomPreset.projection(room.id),
          'status': _sendStatus,
          'revision': _sentRevision,
          'messages': messagePresentation,
        },
    };
  }

  Future<void> _lobbyCommand(RoomOperation operation, String value) async {
    final active = accountEpoch;
    final raw = jsonDecode(value);
    if (raw is! Map ||
        raw['request'] is! String ||
        !RegExp(r'^q[1-9][0-9]{0,13}$').hasMatch(raw['request'] as String) ||
        raw['data'] is! Map) {
      return;
    }
    final command = _lobby.command(
      operation,
      Map<String, Object?>.from(raw['data'] as Map),
    );
    var result = const RoomCommandResult('rejected', error: 'invalidInput');
    if (command != null) {
      try {
        result = await (port as RoomCommandsPort)
            .execute(command)
            .timeout(const Duration(seconds: 12));
      } on Object {
        result = const RoomCommandResult('unknown', error: 'outcomeUnknown');
      }
    }
    if (!currentAccount(active)) return;
    _state.uncertain = result.status == 'unknown';
    Map<String, Object?>? preview;
    if (result.preview case final room?) {
      _lobby.previewId = room.id;
      preview = {
        'schemaVersion': 1,
        'currentRoomId': null,
        'serverTime': DateTime.now().toUtc().toIso8601String(),
        'rooms': [await _lobby.room(room, _images)],
      };
    }
    if (!currentAccount(active)) return;
    _lobbyReply = {
      'request': raw['request'],
      'status': result.status,
      'error': result.error,
      'preview': ?preview,
    };
    final lobby = currentView['lobby'];
    if (lobby is Map) {
      emit({
        ...currentView,
        'lobby': {...lobby, 'reply': _lobbyReply},
      });
    }
  }

  Future<void> _updateSettings(String roomId, String value) async {
    final epoch = accountEpoch;
    final readEpoch = generation;
    final raw = jsonDecode(value);
    if (raw is! Map ||
        raw.keys.any((key) => key != 'request' && key != 'data') ||
        raw['request'] is! String ||
        !RegExp(r'^q[1-9][0-9]{0,13}$').hasMatch(raw['request']) ||
        raw['data'] is! Map) {
      return;
    }
    final data = Map<String, Object?>.from(raw['data'] as Map);
    const allowed = {
      'title',
      'goal',
      'capacity',
      'isPublic',
      'eligibility',
      'admissionMode',
      'passwordMode',
      'password',
      'voiceRequirement',
      'language',
      'autoDisbandHours',
      'recruitmentDurationMinutes',
      'gameplayTagNodeIds',
      'contextTagIds',
    };
    var result = const RoomCommandResult('rejected', error: 'invalidInput');
    if (data.keys.every(allowed.contains) &&
        allowed.every(data.containsKey) &&
        const {'keep', 'remove', 'replace'}.contains(data['passwordMode']) &&
        !_state.uncertain) {
      var dispatched = false;
      try {
        // Re-read authority immediately before the existing command path.
        final fresh = await port.read();
        if (!currentAccount(epoch) ||
            !current(readEpoch) ||
            _state.selected != roomId) {
          return;
        }
        final directory = fresh.directory;
        final room = directory?.rooms.where((r) => r.id == roomId).singleOrNull;
        if (fresh.state != RoomReadState.ready || directory == null) {
          result = const RoomCommandResult('rejected', error: 'unavailable');
        } else if (directory.currentRoomId != roomId || room == null) {
          result = const RoomCommandResult('stale', error: 'contextChanged');
        } else if (port is! RoomCommandsPort ||
            !(port as RoomCommandsPort).supportsCommands ||
            port is! RoomManagementPort ||
            !(port as RoomManagementPort).supportsManagement) {
          result = const RoomCommandResult('rejected', error: 'unavailable');
        } else if (!room.viewerIsHost) {
          result = const RoomCommandResult('rejected', error: 'notHost');
        } else {
          dispatched = true;
          _state.uncertain = true;
          result = await (port as RoomCommandsPort)
              .execute(
                RoomCommand(RoomOperation.update, {...data, 'roomId': roomId}),
              )
              .timeout(const Duration(seconds: 12));
          if (!const {
            'updated',
            'rejected',
            'unknown',
            'stale',
          }.contains(result.status)) {
            result = const RoomCommandResult(
              'unknown',
              error: 'outcomeUnknown',
            );
          }
        }
      } on Object {
        result = RoomCommandResult(
          dispatched ? 'unknown' : 'rejected',
          error: dispatched ? 'outcomeUnknown' : 'unavailable',
        );
      }
    }
    if (!currentAccount(epoch) ||
        !current(readEpoch) ||
        _state.selected != roomId) {
      return;
    }
    _state.uncertain = result.status == 'unknown';
    _state.notice = switch (result.status) {
      'updated' => '房间设置已保存。',
      'unknown' => '房间设置的保存结果未确认，请刷新核对，不要重复提交。',
      _ => '',
    };
    _settingsReply = {
      'request': raw['request'],
      'status': result.status,
      'error': result.error,
    };
    final presentation = currentView['room'];
    if (presentation is Map) {
      emit({
        ...currentView,
        'room': {
          ...presentation,
          'settings': {
            ...presentation['settings'] as Map,
            'reply': _settingsReply,
          },
        },
      });
    }
  }

  Future<void> _command(RoomCommand command) async {
    final epoch = accountEpoch;
    _state.uncertain = true;
    try {
      final result = await (port as RoomCommandsPort)
          .execute(command)
          .timeout(const Duration(seconds: 12));
      if (!currentAccount(epoch)) return;
      _state.uncertain = result.status == 'unknown';
      _state.notice = switch (result.status) {
        'joined' => '已加入房间。',
        'pending' => '申请已提交，等待房主审核。',
        'left' => '已退出房间。',
        'removed' => '已将成员移出房间。',
        'hostTransferred' => '房主已转移，你仍在房间中。',
        'unknown' => '结果未确认，请刷新核对。',
        _ => '操作未完成，请刷新核对当前状态。',
      };
      if (result.accepted) {
        changeScope();
        if (command.operation != RoomOperation.remove) _state.selected = null;
      }
    } on Object {
      if (currentAccount(epoch)) {
        _state.uncertain = true;
        _state.notice = '结果未确认，请刷新核对。';
      }
    }
  }
}
