import 'dart:async';

import '../../features/communities/communities_module.dart';
import '../../features/communities/community_workspace_port.dart';
import '../../features/communities/community_announcements_port.dart';
import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_chat_controller.dart';
import '../../features/communities/community_ships_port.dart';
import '../../features/communities/community_member_runtime.dart';
import '../../features/communities/community_workspace_copy.dart';
import 'menu_feature_session.dart';
import 'menu_organization_view.dart';
import 'menu_organization_presentation.dart';
import '../../platform/window/menu_profile_navigation.dart';
import 'menu_organization_avatars.dart';
import 'menu_chat_archive.dart';
import 'menu_channel_avatars.dart';
import 'menu_account_avatar.dart';
import '../../features/communities/community_own_avatar.dart';

final class MenuOrganizationsSession extends MenuFeatureSession
    implements MenuProfileTargets {
  MenuOrganizationsSession(
    this.port,
    void Function(Map<String, Object?>) publish, {
    this.chatOnly = false,
    this.archive,
  }) : super(publish, port.invalidations) {
    if (chatOnly) _tab = 'chat';
  }
  final bool chatOnly;
  final MenuChatArchive? archive;
  final _chats = <String, CommunityChatController>{};
  List<CommunityCard> _channelCards = const [];
  String? _channelNext;
  final _channelLogos = <String, String?>{};
  final _chatViews = <String, Map<String, Object?>>{};
  final _messagePhotos = <String, Map<String, String>>{};
  final _photoMessages = <String, List<CommunityChatMessage>>{};
  late final _ownPhoto = MenuAccountAvatar(() {
    final cached = _chatViews[_selected];
    if (visible && cached != null) emit({'state': 'ready', ...cached});
  });
  @override
  void emit(Map<String, Object?> view) {
    final Object source = port;
    final own = _ownPhoto.read(
      source is CommunityOwnAvatarSource ? source.ownAvatarImageData : null,
    );
    super.emit(
      organizationPortraits(
        view,
        own,
        _photoMessages[_selected],
        _messagePhotos[_selected],
      ),
    );
  }

  Map<String, Object?>? _directoryView;
  @override
  bool get backgroundReads => chatOnly;
  @override
  Duration get refreshInterval => Duration(seconds: chatOnly ? 3 : 15);
  @override
  Map<String, Object?>? failedRead(Object error) {
    if (!chatOnly ||
        !(error is TimeoutException ||
            error is CommunityFailure && error.code == 'unavailable')) {
      _chatViews.clear();
      _chatProfiles.clear();
      _photoMessages.clear();
      _messagePhotos.clear();
      _chatAvatars.clear();
      _directoryView = null;
      return null;
    }
    final cached = readingView;
    final failed = cached == null
        ? null
        : {
            ...cached,
            'refreshing': false,
            'notice': silentRead ? '' : '暂时无法连接，已保留聊天记录和草稿。',
          };
    if (failed != null && _selected != null) _chatViews[_selected!] = failed;
    return failed;
  }

  @override
  Map<String, Object?>? get readingView {
    final source = _selected == null ? _directoryView : _chatViews[_selected];
    if (source == null) {
      if (_channelCards.isEmpty) return null;
      return {'state': 'ready', 'channels': channelRows()};
    }
    return organizationRefreshingView(source, channelRows());
  }

  int _sentRevision = 0;
  String _sendStatus = 'idle';
  String? _failedVisibleMessageRef;
  final CommunitiesPort port;
  String? _selected, _after;
  String _tab = 'members';
  int _offset = 0;
  String _query = '';
  String _directoryQuery = '';
  String? _selectedLogo;
  CommunityChatController? _chat;
  final _avatars = MenuOrganizationAvatars();
  final _chatAvatars = MenuChannelAvatars();
  final _profiles = <String, MenuProfileTarget>{};
  // Chat avatar keys survive quiet polls; authority stays in the primary engine.
  final _chatProfiles =
      <
        String,
        ({String target, CommunityChatMessage message, DateTime expires})
      >{};
  int _profileSerial = 0;
  @override
  MenuProfileTarget? profileTarget(String key) {
    final binding = _chatProfiles[key];
    if (binding != null) {
      final identity = accountEpoch;
      bool valid() =>
          currentAccount(identity) &&
          visible &&
          _selected == binding.target &&
          _chatProfiles[key]?.message.senderRef == binding.message.senderRef &&
          _chatProfiles[key]?.message.isSelf == binding.message.isSelf &&
          DateTime.now().isBefore(binding.expires);
      if (!valid()) return null;
      final message = binding.message;
      final Object source = port;
      return MenuProfileTarget(
        source: message.isSelf ? 'self' : 'community',
        reference: message.isSelf ? '' : message.senderRef,
        contextRef: message.isSelf ? null : binding.target,
        refreshReference: message.isSelf
            ? null
            : () async {
                if (!currentAccount(identity)) throw StateError('retired');
                final page = await (port as CommunityChatPort).readChat(
                  binding.target,
                  before: message.sequence + 1,
                );
                if (!currentAccount(identity) ||
                    page.targetRef != binding.target) {
                  throw StateError('retired');
                }
                final author = page.messages
                    .where((m) => m.sequence == message.sequence && !m.isSelf)
                    .firstOrNull;
                if (author == null) throw StateError('retired');
                return author.senderRef;
              },
        query: message.gameId,
        avatar: message.isSelf && source is CommunityOwnAvatarSource
            ? _ownPhoto.read(source.ownAvatarImageData)
            : _messagePhotos[binding.target]?[message.messageRef],
        isCurrent: valid,
        isAccountCurrent: () => currentAccount(identity),
      );
    }
    final target = _profiles[key];
    return target?.isCurrent() == true ? target : null;
  }

  @override
  void reset() {
    changeScope();
    _selected = _after = null;
    _channelCards = const [];
    _channelNext = null;
    _channelLogos.clear();
    _chatViews.clear();
    _messagePhotos.clear();
    _photoMessages.clear();
    _ownPhoto.clear();
    _directoryView = null;
    _tab = chatOnly ? 'chat' : 'members';
    _sentRevision = 0;
    _sendStatus = 'idle';
    _failedVisibleMessageRef = null;
    _offset = 0;
    _query = '';
    _directoryQuery = '';
    _selectedLogo = null;
    _avatars.clear();
    _chatAvatars.clear();
    _profiles.clear();
    _chatProfiles.clear();
    for (final chat in _chats.values) {
      chat.dispose();
    }
    _chats.clear();
    if (!chatOnly) _chat?.dispose();
    _chat = null;
  }

  @override
  Future<void> closePort() {
    for (final chat in _chats.values) {
      chat.dispose();
    }
    _chats.clear();
    if (!chatOnly) _chat?.dispose();
    _avatars.dispose();
    _chatAvatars.dispose();
    _ownPhoto.dispose();
    return port.close();
  }

  List<Map<String, Object?>> channelRows() => [
    for (final item in _channelCards)
      {
        'title': item.name,
        'avatar': _channelLogos[item.targetRef],
        'detail': _selected == item.targetRef ? '当前组织频道' : '组织频道',
        'buttons': [
          button('打开组织会话', (_) async {
            if (_selected == item.targetRef) return;
            changeScope();
            _chat?.setReadingContext(visible: false, foreground: false);
            _chat = null;
            _selected = item.targetRef;
            _selectedLogo = _channelLogos[item.targetRef];
            _failedVisibleMessageRef = null;
            _sentRevision = 0;
            _sendStatus = 'idle';
          }),
        ],
      },
  ];

  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation;
    _profiles.clear();
    final actions = <Map<String, Object?>>[], rows = <Map<String, Object?>>[];
    final presentation = <Map<String, Object?>>[];
    final receipts = <String, String>{};
    final messageProfiles = <String, String>{};
    final messagePresentation = <Map<String, Object?>>[];
    if (_selected == null) {
      final directory = await port.read(
        view: 'mine',
        query: _directoryQuery,
        after: _after,
      );
      final logos = await Future.wait(
        directory.items.map((item) => _avatars.logo(item.logo)),
      );
      if (!current(epoch)) throw StateError('retired');
      if (chatOnly) {
        _channelCards = directory.items;
        _channelNext = directory.next;
        for (var i = 0; i < directory.items.length; i++) {
          _channelLogos[directory.items[i].targetRef] = logos[i];
        }
      }
      actions.add(
        button('搜索组织', (value) async {
          _directoryQuery = value.trim();
          _after = null;
        }, input: '搜索已加入的组织'),
      );
      for (var i = 0; i < directory.items.length; i++) {
        final item = directory.items[i];
        rows.add({
          'title': item.name,
          'detail': item.description,
          'buttons': [
            button('打开组织', (_) async {
              changeScope();
              _selected = item.targetRef;
              _selectedLogo = logos[i];
              _offset = 0;
            }),
          ],
        });
        presentation.add({
          'logo': logos[i],
          'memberCount': item.memberCount,
          'relationship': item.relationship,
          'tags': item.tags,
          'language': item.language,
          'activeTime': item.activeTime,
        });
      }
      if (directory.next != null) {
        actions.add(
          button('下一页', (_) async {
            _after = directory.next;
          }),
        );
      }
      if (_after != null) {
        actions.add(
          button('首页', (_) async {
            _after = null;
          }),
        );
      }
      final result = <String, Object?>{
        if (chatOnly) 'channels': channelRows(),
        'title': '我的组织',
        'rows': rows,
        'buttons': actions,
        'organization': {
          'tab': 'directory',
          'total': rows.length,
          'matched': rows.length,
          'offset': 0,
          'rows': presentation,
          'query': _directoryQuery,
        },
      };
      if (chatOnly) _directoryView = result;
      return result;
    }
    final target = _selected!;
    if (chatOnly && archive != null && !_chatViews.containsKey(target)) {
      try {
        final local = await archive!
            .load('organization', target)
            .timeout(const Duration(seconds: 2));
        if (!current(epoch)) throw StateError('retired');
        if (local.isNotEmpty) {
          final cached = <String, Object?>{
            'state': 'ready',
            'title':
                _channelCards
                    .where((c) => c.targetRef == target)
                    .firstOrNull
                    ?.name ??
                '组织频道',
            'notice': '',
            'refreshing': false,
            'organization': {
              'tab': 'chat',
              'logo': _selectedLogo ?? _channelLogos[target],
              'total': local.length,
              'matched': local.length,
              'offset': 0,
              'rows': [for (final _ in local) <String, Object?>{}],
            },
            'channels': channelRows(),
            'rows': [
              for (final row in local)
                {'title': row['name'], 'detail': row['text']},
            ],
            'chat': {
              'status': 'idle',
              'availability': 'checking',
              'revision': 0,
              'receipts': <String, String>{},
              'messages': [
                for (final row in local)
                  {'self': row['self'], 'time': row['time']},
              ],
            },
          };
          _chatViews[target] = cached;
          emit(cached);
        }
      } on Object {
        if (!current(epoch)) throw StateError('retired');
      }
    }
    if (chatOnly &&
        (_channelCards.isEmpty ||
            !_channelCards.any((c) => c.targetRef == target))) {
      final directory = await port.read(view: 'mine', query: '', after: _after);
      if (!current(epoch)) throw StateError('retired');
      _channelCards = directory.items;
      _channelNext = directory.next;
      final logos = await Future.wait(
        directory.items.map((item) => _avatars.logo(item.logo)),
      );
      if (!current(epoch)) throw StateError('retired');
      for (var i = 0; i < directory.items.length; i++) {
        _channelLogos[directory.items[i].targetRef] = logos[i];
      }
      _selectedLogo = _channelLogos[target];
    }
    // The authenticated chat endpoint checks membership itself. Chat must not
    // wait for member presence, roster media or a second directory round trip.
    final workspace = chatOnly
        ? null
        : await (port as CommunityWorkspacePort).readWorkspace(
            target,
            _tab == 'members' ? _query : '',
            _tab == 'members' ? _offset : 0,
          );
    if (!current(epoch) || workspace != null && workspace.targetRef != target) {
      throw StateError('retired');
    }
    if (!chatOnly) {
      actions.add(
        button('返回组织列表', (_) async {
          final query = _directoryQuery;
          reset();
          _directoryQuery = query;
        }),
      );
    }
    if (chatOnly && _channelNext != null) {
      actions.add(
        button('更多组织会话', (_) async {
          _after = _channelNext;
        }),
      );
    }
    if (chatOnly && _after != null) {
      actions.add(
        button('组织会话首页', (_) async {
          _after = null;
        }),
      );
    }
    for (final entry in const {
      'members': '成员',
      'announcements': '公告',
      'chat': '聊天',
      'ships': '舰船',
    }.entries) {
      if (chatOnly) continue;
      if ((entry.key == 'announcements' &&
              port is! CommunityAnnouncementsPort) ||
          (entry.key == 'chat' && port is! CommunityChatPort) ||
          (entry.key == 'ships' && port is! CommunityShipsPort)) {
        continue;
      }
      actions.add(
        button(entry.value, (_) async {
          if (_tab == entry.key) return;
          changeScope();
          _tab = entry.key;
          _offset = 0;
          _query = '';
        }),
      );
    }
    String notice = '';
    var total = workspace?.totalCount ?? 0,
        matched = workspace?.matchedCount ?? 0;
    if (_tab == 'members') {
      actions.add(
        button('搜索成员', (value) async {
          _query = value.trim();
          _offset = 0;
        }, input: '搜索成员、呼号或职务'),
      );
      final avatars = await Future.wait(
        workspace!.members.map(
          (member) =>
              _avatars.read(port as CommunityWorkspacePort, target, member),
        ),
      );
      if (!current(epoch)) throw StateError('retired');
      for (var i = 0; i < workspace.members.length; i++) {
        final member = workspace.members[i];
        final profileKey = 'om${++_profileSerial}', identity = accountEpoch;
        _profiles[profileKey] = MenuProfileTarget(
          source: 'community',
          reference: member.memberRef,
          contextRef: target,
          query: member.gameName,
          avatar: avatars[i],
          isCurrent: () => current(epoch) && _selected == target,
          isAccountCurrent: () => currentAccount(identity),
        );
        final runtime = communityMemberRuntime(
          member,
          text: (key) => communityWorkspaceCopy[key]?.$1 ?? '—',
          regionText: (value) => value,
        );
        final presence = organizationPresence(member.online, member.liveStatus);
        final activity = organizationPresenceText(presence);
        rows.add({
          'title': member.displayName,
          'detail':
              '${member.roleTitle} · $activity\n${runtime.server} · ${runtime.ship} · ${runtime.location}',
        });
        presentation.add({
          'handle': member.gameName,
          'role': member.roleTitle,
          'roleColor': member.roleColor,
          'presence': presence,
          'isSelf': member.isSelf,
          'avatar': avatars[i],
          'profileKey': profileKey,
          'ship': runtime.ship,
          'location': runtime.location,
          'server': runtime.server,
        });
      }
      if (workspace.next != null) {
        actions.add(
          button('下一页', (_) async {
            _offset = workspace.next!;
          }),
        );
      }
      if (_offset > 0) {
        actions.add(
          button('首页', (_) async {
            _offset = 0;
          }),
        );
      }
    } else if (_tab == 'announcements' && port is CommunityAnnouncementsPort) {
      final page = await (port as CommunityAnnouncementsPort).readAnnouncements(
        target,
        offset: _offset,
      );
      if (!current(epoch) || page.targetRef != target) {
        throw StateError('retired');
      }
      for (final item in [?page.current, ...page.history]) {
        rows.add({'title': item.title, 'detail': item.content});
      }
      if (page.next != null) {
        actions.add(
          button('下一页', (_) async {
            _offset = page.next!;
          }),
        );
      }
      if (_offset > 0) {
        actions.add(
          button('首页', (_) async {
            _offset = 0;
          }),
        );
      }
    } else if (_tab == 'chat' && port is CommunityChatPort) {
      if (chatOnly) {
        if (!_chats.containsKey(target) && _chats.length >= 12) {
          _chats.remove(_chats.keys.first)?.dispose();
        }
        _chat = _chats.putIfAbsent(
          target,
          () => CommunityChatController(port as CommunityChatPort, target),
        );
      } else {
        _chat ??= CommunityChatController(port as CommunityChatPort, target);
      }
      final chat = _chat!;
      await chat.refresh(silent: silentRead);
      if (!current(epoch)) {
        throw StateError('retired');
      }
      if (chat.invalidated) {
        _chatViews.remove(target);
        throw StateError('restricted');
      }
      if (chat.error != null) throw CommunityFailure(chat.error!);
      if (chat.localHistoryUnavailable) notice = '消息已读取，但本机记录保存失败；重启后可能需要重新读取。';
      if (archive != null) {
        actions.add(
          button('清除本机记录', (_) async {
            await archive!.clear('organization', target);
            _chatViews.remove(target);
          }, confirm: '清除此会话的本机缓存？在线消息不会删除，后续读取可再次缓存。'),
        );
      }
      if (_sendStatus == 'unknown' &&
          !chat.sendUncertain &&
          chat.sendError == null &&
          chat.draft.isEmpty) {
        _sendStatus = 'sent';
        _sentRevision++;
      }
      if (chatOnly) {
        final senders = chat.messages.map((m) => m.senderRef).toSet();
        _chatProfiles.removeWhere(
          (_, b) =>
              b.target != target || !senders.contains(b.message.senderRef),
        );
      }
      for (final (index, message) in chat.messages.indexed) {
        rows.add({
          'title': message.callsign.isEmpty ? message.gameId : message.callsign,
          'detail':
              '${message.text}${message.hasAttachment ? "\n[附件请在客户端查看]" : ""}',
        });
        if (chatOnly) {
          final key =
              _chatProfiles.entries
                  .where(
                    (e) =>
                        e.value.target == target &&
                        e.value.message.senderRef == message.senderRef &&
                        e.value.message.isSelf == message.isSelf,
                  )
                  .firstOrNull
                  ?.key ??
              'om${++_profileSerial}';
          _chatProfiles[key] = (
            target: target,
            message: message,
            expires: DateTime.now().add(const Duration(minutes: 2)),
          );
          messageProfiles['$index'] = key;
          messagePresentation.add({
            'self': message.isSelf,
            'time': message.createdAt.toUtc().toIso8601String(),
            'role': message.roleTitle,
            'roleColor': message.roleColor,
          });
          if (!message.isSelf &&
              message.sequence > chat.confirmedReadThrough &&
              chat.receiptError == null) {
            receipts['$index'] =
                button('读取消息', (_) async {
                      _failedVisibleMessageRef = message.messageRef;
                      chat.setReadingContext(visible: true, foreground: true);
                      try {
                        await chat.acknowledgeVisible(message.messageRef);
                      } finally {
                        chat.setReadingContext(
                          visible: false,
                          foreground: false,
                        );
                      }
                    }, silent: true)['key']
                    as String;
          }
        }
      }
      if (chat.canSubmit) {
        actions.add(
          button(
            '发送消息',
            (text) async {
              if (text.trim().isEmpty || text.length > 1000) return;
              chat.updateDraft(text);
              await chat.submit();
              _sendStatus = chat.sendUncertain
                  ? 'unknown'
                  : chat.sendError != null
                  ? 'rejected'
                  : 'sent';
              if (_sendStatus == 'sent') _sentRevision++;
            },
            input: '输入消息',
            limit: 1000,
          ),
        );
      }
      if (chat.sendUncertain) {
        notice = '发送结果未确认，请刷新聊天记录核对。';
      } else if (chat.sendError != null) {
        notice = '消息未发送，可重新编辑后提交。';
      }
      if (chat.hasOlder) {
        actions.add(
          button('较早消息', (_) async {
            await chat.loadOlder();
          }),
        );
      }
      if (!silentRead &&
          chat.receiptError != null &&
          _failedVisibleMessageRef != null) {
        actions.add(
          button('重试已读同步', (_) async {
            chat.setReadingContext(visible: true, foreground: true);
            try {
              await chat.acknowledgeVisible(
                _failedVisibleMessageRef!,
                retry: true,
              );
            } finally {
              chat.setReadingContext(visible: false, foreground: false);
            }
          }),
        );
      }
    } else if (_tab == 'ships' && port is CommunityShipsPort) {
      final page = await (port as CommunityShipsPort).readShips(
        target,
        offset: _offset,
        query: CommunityShipQuery(text: _query),
      );
      if (!current(epoch) || page.targetRef != target) {
        throw StateError('retired');
      }
      total = page.totalCount;
      matched = page.matchedCount;
      actions.add(
        button('搜索舰船', (value) async {
          _query = value.trim();
          _offset = 0;
        }, input: '搜索舰船、所有者或用途'),
      );
      for (final ship in page.ships) {
        rows.add({
          'title': ship.displayName,
          'detail': ship.englishName ?? ship.manufacturer ?? '',
        });
        presentation.add(organizationShipPresentation(ship));
      }
      if (page.next != null) {
        actions.add(
          button('下一页', (_) async {
            _offset = page.next!;
          }),
        );
      }
      if (_offset > 0) {
        actions.add(
          button('首页', (_) async {
            _offset = 0;
          }),
        );
      }
    } else {
      throw StateError('unsupported');
    }
    final result = <String, Object?>{
      if (chatOnly) 'channels': channelRows(),
      'title':
          workspace?.name ??
          _channelCards.where((c) => c.targetRef == target).firstOrNull?.name ??
          '组织频道',
      'rows': rows,
      'buttons': actions,
      'notice': notice,
      if (chatOnly)
        'chat': {
          'status': _sendStatus,
          'availability': _chat?.canSubmit == true ? 'ready' : 'denied',
          'revision': _sentRevision,
          'messages': messagePresentation,
          'profiles': messageProfiles,
          'receipts': receipts,
        },
      'organization': {
        'tab': _tab,
        'code': workspace?.code ?? '',
        'description': workspace?.description ?? '',
        'logo': _selectedLogo,
        'activeTime': workspace?.activeTime ?? '',
        'query': _query,
        'total': total,
        'matched': matched,
        'offset': _offset,
        'rows': presentation.isEmpty
            ? [for (final _ in rows) <String, Object?>{}]
            : presentation,
      },
    };
    if (chatOnly) {
      if (!_chatViews.containsKey(target) && _chatViews.length >= 24) {
        final expired = _chatViews.keys.first;
        _chatViews.remove(expired);
        _photoMessages.remove(expired);
        _messagePhotos.remove(expired);
      }
      _chatViews[target] = result;
      final messages = List<CommunityChatMessage>.of(
        _chat?.messages ?? const [],
      );
      _photoMessages[target] = messages;
      final photos = _messagePhotos.putIfAbsent(target, () => {});
      final references = messages.map((m) => m.messageRef).toSet();
      photos.removeWhere((key, _) => !references.contains(key));
      final account = accountEpoch;
      // First paint and permissions never wait for photos. Use account identity,
      // not a poll generation: an unrelated background read must not lose media.
      unawaited(
        _chatAvatars
            .load(
              port as CommunityChatPort,
              target,
              messages,
              onPhoto: (index, photo) {
                if (!currentAccount(account)) return;
                final reference = messages[index].messageRef;
                if (photos[reference] == photo) return;
                photos[reference] = photo;
                final latest = _chatViews[target];
                if (visible && _selected == target && latest != null) {
                  emit({'state': 'ready', ...latest});
                }
              },
            )
            .then((_) {}),
      );
    }
    return result;
  }
}
