import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_chat_module.dart';
import 'menu_feature_session.dart';

final class MenuRoomsSession extends MenuFeatureSession {
  MenuRoomsSession(
    this.port,
    void Function(Map<String, Object?>) publish, {
    this.chatOnly = false,
  }) : super(publish, port.invalidations) {
    if (chatOnly) _tab = 'chat';
  }
  final bool chatOnly;
  int _before = 0, _sentRevision = 0;
  String _sendStatus = 'idle';
  final PartyRoomsPort port;
  String? _selected;
  String _tab = 'members', _notice = '';
  bool _uncertain = false;
  @override
  void reset() {
    changeScope();
    _selected = null;
    _tab = chatOnly ? 'chat' : 'members';
    _before = _sentRevision = 0;
    _sendStatus = 'idle';
    _notice = '';
    _uncertain = false;
  }

  @override
  Future<void> closePort() => port.close();
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
    final selection = chatOnly
        ? directory.currentRoomId
        : directory.currentRoomId ?? _selected;
    if (selection != _selected) {
      changeScope();
      _before = _sentRevision = 0;
      _sendStatus = 'idle';
      _uncertain = false;
      _notice = '';
    }
    _selected = selection;
    final room = directory.rooms.where((r) => r.id == _selected).firstOrNull;
    final actions = <Map<String, Object?>>[];
    final rows = <Map<String, Object?>>[];
    final messagePresentation = <Map<String, Object?>>[];
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
      for (final item in directory.rooms) {
        rows.add({
          'title': item.title,
          'detail': '${item.members.length}/${item.capacity} · ${item.goal}',
          'buttons': [
            button('查看房间', (_) async {
              changeScope();
              _selected = item.id;
              _tab = 'members';
            }),
          ],
        });
      }
    } else {
      if (directory.currentRoomId == null) {
        actions.add(
          button('返回房间列表', (_) async {
            changeScope();
            _selected = null;
          }),
        );
      }
      if (!chatOnly) {
        actions.add(
          button('成员', (_) async {
            if (_tab != 'members') changeScope();
            _tab = 'members';
          }),
        );
      }
      if (!chatOnly &&
          directory.currentRoomId == room.id &&
          port is RoomChatProvider) {
        actions.add(
          button('聊天', (_) async {
            if (_tab != 'chat') changeScope();
            _tab = 'chat';
          }),
        );
      }
      if (!chatOnly && commands && !_uncertain) {
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
        } else {
          actions.add(
            button(
              '加入房间',
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
      if (_tab == 'chat' &&
          directory.currentRoomId == room.id &&
          port is RoomChatProvider) {
        final chat = (port as RoomChatProvider).roomChat;
        final page = await chat.read(room.id, before: _before);
        if (!current(epoch)) throw StateError('retired');
        for (final message in page.messages) {
          rows.add({
            'title': message.sender,
            'detail':
                '${message.text}${message.attachment != null ? "\n[附件请在客户端查看]" : ""}',
          });
          messagePresentation.add({
            'self': message.isSelf,
            'time': message.time.toUtc().toIso8601String(),
          });
        }
        if (chatOnly && page.hasOlder && page.messages.isNotEmpty) {
          actions.add(
            button('较早消息', (_) async {
              _before = page.messages.first.sequence;
            }),
          );
        }
        if (chatOnly && _before > 0) {
          actions.add(
            button('最新消息', (_) async {
              _before = 0;
            }),
          );
        }
        if (chat.available && !_uncertain) {
          actions.add(
            button(
              '发送消息',
              (text) async {
                final value = text.trim();
                if (value.isEmpty || value.length > 1000) return;
                final active = accountEpoch;
                _uncertain = true;
                try {
                  final receipt = await chat
                      .send(room.id, value)
                      .timeout(const Duration(seconds: 12));
                  if (!currentAccount(active)) return;
                  if (!receipt.isSelf ||
                      receipt.text != value ||
                      receipt.sequence <= 0) {
                    throw StateError('unconfirmed');
                  }
                  _notice = '消息已发送。';
                  _sentRevision++;
                  _sendStatus = 'sent';
                  _before = 0;
                  _uncertain = false;
                } on Object {
                  if (currentAccount(active)) {
                    _uncertain = true;
                    _notice = '发送结果未确认，请查看记录后再操作。';
                    _sendStatus = 'unknown';
                  }
                }
              },
              input: '输入消息',
              limit: 1000,
            ),
          );
        }
      } else {
        for (final member in room.members) {
          rows.add({
            'title': member.displayName,
            'detail': [
              member.isHost ? '房主' : '成员',
              member.presence,
              member.ship,
              member.location,
              member.shard,
            ].where((v) => v.isNotEmpty).join(' · '),
          });
        }
      }
    }
    if (_uncertain) {
      actions.add(
        button('已核对当前结果', (_) async {
          _uncertain = false;
          _notice = '';
          _sendStatus = 'idle';
        }, confirm: '请先核对房间与聊天记录。继续只解除操作锁定，不会重复执行上次操作。'),
      );
    }
    return {
      'title': room?.title ?? '房间',
      'notice': _notice,
      'buttons': actions,
      'rows': rows,
      if (chatOnly && room != null)
        'chat': {
          'status': _sendStatus,
          'revision': _sentRevision,
          'messages': messagePresentation,
        },
    };
  }

  Future<void> _command(RoomCommand command) async {
    final epoch = accountEpoch;
    _uncertain = true;
    try {
      final result = await (port as RoomCommandsPort)
          .execute(command)
          .timeout(const Duration(seconds: 12));
      if (!currentAccount(epoch)) return;
      _uncertain = result.status == 'unknown';
      _notice = switch (result.status) {
        'joined' => '已加入房间。',
        'pending' => '申请已提交，等待房主审核。',
        'left' => '已退出房间。',
        'unknown' => '结果未确认，请刷新核对。',
        _ => '操作未完成，请刷新核对当前状态。',
      };
      if (result.accepted) {
        changeScope();
        _selected = null;
      }
    } on Object {
      if (currentAccount(epoch)) {
        _uncertain = true;
        _notice = '结果未确认，请刷新核对。';
      }
    }
  }
}
