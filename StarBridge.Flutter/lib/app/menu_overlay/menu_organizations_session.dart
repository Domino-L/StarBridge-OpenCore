import 'dart:async';

import '../../features/communities/communities_module.dart';
import '../../features/communities/community_workspace_port.dart';
import '../../features/communities/community_overview_reader.dart';
import '../../features/communities/community_announcements_port.dart';
import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_ships_port.dart';
import 'menu_organization_member_presentation.dart';
import 'menu_feature_session.dart';
import 'menu_organization_presentation.dart';
import 'menu_organization_sections.dart';
import 'menu_organization_ships.dart';
import 'menu_organization_shell.dart';
import '../../platform/window/menu_profile_navigation.dart';
import 'menu_organization_avatars.dart';
import 'menu_announcement_details_session.dart';
import 'menu_directory_logos.dart';
import 'menu_organization_previews.dart';
import 'menu_chat_archive.dart';
import 'menu_organization_chat_session.dart';

final class MenuOrganizationsSession extends MenuFeatureSession
    implements MenuProfileTargets {
  MenuOrganizationsSession(
    this.port,
    void Function(Map<String, Object?>) publish, {
    this.chatOnly = false,
    this.archive,
    CommunityOverviewReader? overview,
  }) : super(publish, port.invalidations) {
    _shell.overview = overview;
    if (organizationSections(port).containsKey('chat')) _tab = 'chat';
  }
  final bool chatOnly;
  late final _announcementDetails = MenuAnnouncementDetailsSession(
    grant: (run) => button('详情', (_) => run(), silent: true),
    changed: () => emit(currentView),
    denied: _announcementDenied,
    isCurrent: (target) =>
        visible && !disposed && _tab == 'announcements' && _selected == target,
  );
  void _announcementDenied() {
    if (!visible || disposed) return;
    // Retire the read AND its busy gate through the existing visibility path.
    // Clear all section snapshots before re-reading the authorized directory.
    super.show(false);
    _reset();
    emit({'state': 'unavailable'});
    super.show(true);
  }

  @override
  void changeScope() {
    _announcementDetails.clear();
    super.changeScope();
  }

  @override
  void show(bool value) {
    if (!value) _announcementDetails.clear();
    super.show(value);
  }

  final _shell = MenuOrganizationShell();
  final _ships = MenuOrganizationShips();
  final MenuChatArchive? archive;
  String _readStage = 'directory';
  late final _chatData = MenuOrganizationChatSession(
    port,
    this,
    archive: archive,
    selected: () => _selected,
    nextProfileKey: () => 'om${++_profileSerial}',
    observed: (target, messages, unread) =>
        _previews?.observe(target, messages, unread),
    chatSelected: () => chatOnly || _tab == 'chat',
  );
  @override
  Map<String, Object?>? failedWrite() => _chatData.failedWrite();
  @override
  Map<String, Object?>? get writingView => _chatData.writingView;

  List<CommunityCard> _channelCards = const [];
  String? _channelNext;
  final _channelLogos = <String, String?>{};
  List<String> _navigationTargets = const [];
  late final _previews = port is CommunityChatPort
      ? MenuOrganizationPreviews(port as CommunityChatPort, (target, preview) {
          final index = _navigationTargets.indexOf(target);
          if (disposed || index < 0) return;
          _navigation = [
            for (var i = 0; i < _navigation.length; i++)
              {..._navigation[i], if (i == index) ...preview},
          ];
          _publishNavigation();
        })
      : null;
  void _publishNavigation() {
    if (chatOnly && _directoryView != null) {
      _directoryView = {..._directoryView!, 'channels': channelRows()};
      if (visible && _selected == null) {
        emit({'state': 'ready', ..._directoryView!});
      }
    }
    final cached = _chatData.views[_selected];
    if (cached != null) {
      _chatData.views[_selected!] = organizationNavigationProjection(
        cached,
        _navigation,
        _selectedLogo,
      );
    }
    final shown = organizationVisibleNavigation(
      currentView,
      _tab,
      _navigation,
      _selectedLogo,
    );
    if (visible && shown != null) {
      emit(shown);
    }
  }

  late final _directoryLogos = MenuDirectoryLogos(port, (target, logo) {
    if (disposed || !_channelCards.any((card) => card.targetRef == target)) {
      return;
    }
    _channelLogos[target] = logo;
    if (_selected == target) _selectedLogo = logo;
    _navigation = [
      for (var i = 0; i < _navigation.length; i++)
        {
          ..._navigation[i],
          if (_navigationTargets[i] == target) 'avatar': logo,
        },
    ];
    _publishNavigation();
  });

  Future<String?> _directoryLogo(CommunityCard card) async {
    if (chatOnly && card.logo != null) {
      return await _avatars.logo(card.logo) ?? _channelLogos[card.targetRef];
    }
    return _directoryLogos.read(card);
  }

  @override
  void emit(Map<String, Object?> view) {
    view = _chatData.projectDelivery(view);
    view = _avatars.project(view);
    view = _announcementDetails.project(view);
    _shell.observe(view, chatOnly ? null : port, this);
    super.emit(_chatData.projectPortraits(view));
  }

  Map<String, Object?>? _directoryView;
  @override
  bool get backgroundReads =>
      chatOnly || _tab == 'chat' || _tab == 'announcements';
  @override
  Duration get refreshInterval => Duration(seconds: chatOnly ? 3 : 15);
  @override
  Map<String, Object?>? failedRead(Object error) {
    if (!organizationTransientRead(error)) {
      _announcementDetails.clear();
      if (error is CommunityFailure &&
              const {
                'identityUnavailable',
                'notAllowed',
                'notFound',
                'refreshRequired',
              }.contains(error.code) ||
          error is StateError && error.message == 'restricted') {
        _closeChats();
      }
      _ships.clear();
      _shell.clear();
      _chatData.views.clear();
      _chatData.clearProfiles();
      _chatData.portraits.clear();
      _directoryView = null;
      _previews?.clear();
      _directoryLogos.clear();
      _channelLogos.clear();
      _selectedLogo = null;
      _navigation = const [];
      _navigationTargets = const [];
      _channelCards = const [];
      return chatOnly ? null : organizationReadFailure(error, _readStage);
    }
    if (!chatOnly) {
      return _shell.failed(_selected, _tab, _query, _offset) ??
          organizationReadFailure(error, _readStage);
    }
    final failed = organizationRetainedRead(
      readingView,
      quiet: silentRead && chatOnly,
    );
    if (failed != null && _selected != null) {
      _chatData.views[_selected!] = failed;
    }
    return failed;
  }

  @override
  Map<String, Object?>? get readingView {
    if (!chatOnly) return _shell.loading(_selected, _tab, _query, _offset);
    final source = _selected == null
        ? _directoryView
        : _chatData.views[_selected];
    if (source == null) {
      if (_channelCards.isEmpty) return null;
      return {'state': 'ready', 'channels': channelRows()};
    }
    return organizationRefreshingView(source, channelRows());
  }

  final CommunitiesPort port;
  String? _selected, _after;
  List<Map<String, Object?>> _navigation = const [];
  String _tab = 'members';
  int _offset = 0;
  String _query = '';
  String _directoryQuery = '';
  void _selectPage(int offset, [String? query]) {
    _shell.sectionTransition = true;
    _offset = offset;
    if (query != null) _query = query;
  }

  List<Map<String, Object?>> _pageButtons(int? next) => [
    if (next != null)
      button('下一页', (_) async {
        _selectPage(next);
      }),
    if (_offset > 0)
      button('首页', (_) async {
        _selectPage(0);
      }),
  ];

  String? _selectedLogo;
  late final _avatars = MenuOrganizationAvatars(onChanged: _refreshPortraits);
  void _refreshPortraits() {
    if (visible && !disposed) emit(currentView);
  }

  final _profiles = <String, MenuProfileTarget>{};
  int _profileSerial = 0;
  @override
  MenuProfileTarget? profileTarget(String key) {
    final chat = _chatData.profileTarget(key);
    if (chat != null) return chat;
    final target = _profiles[key];
    return target?.isCurrent() == true ? target : null;
  }

  @override
  void reset() => _reset();

  void _reset({bool keepDeliveries = false}) {
    _ships.clear();
    _shell.clear();
    changeScope();
    _selected = _after = null;
    _navigation = const [];
    _navigationTargets = const [];
    _previews?.clear();
    _directoryLogos.clear();
    _channelCards = const [];
    _channelNext = null;
    _channelLogos.clear();
    _chatData.clear();
    _directoryView = null;
    _tab = organizationSections(port).containsKey('chat') ? 'chat' : 'members';
    _offset = 0;
    _query = '';
    _directoryQuery = '';
    _selectedLogo = null;
    _avatars.clear();
    _profiles.clear();
    if (keepDeliveries) {
      _chatData.active?.setReadingContext(visible: false, foreground: false);
      _chatData.active = null;
    } else {
      _closeChats();
    }
  }

  void _closeChats() => _chatData.closeChats();

  @override
  Future<void> closePort() {
    _closeChats();
    _avatars.dispose();
    _directoryLogos.dispose();
    _previews?.dispose();
    _chatData.dispose();
    return port.close();
  }

  List<Map<String, Object?>> channelRows() => organizationChannelRows(
    _channelCards,
    _channelLogos,
    _selected,
    (item) => button('打开组织会话', (_) async {
      if (_selected == item.targetRef) return;
      changeScope();
      _chatData.active?.setReadingContext(visible: false, foreground: false);
      _chatData.active = null;
      _selected = item.targetRef;
      _selectedLogo = _channelLogos[item.targetRef];
      _chatData.failedVisibleMessageRef = null;
      _chatData.sentRevision = 0;
      _chatData.sendStatus = 'idle';
    }),
  );

  Future<void> _readNavigation(int epoch) async {
    final cards = await _shell.readCards(
      (cursor) =>
          _directoryLogos.readDirectory(view: 'mine', query: '', after: cursor),
      () {
        if (!current(epoch)) throw StateError('retired');
      },
    );
    for (final previous in _channelCards) {
      final matches = cards.where((c) => sameMenuOrganization(previous, c));
      if (matches.length != 1 ||
          currentMenuOrganization(_channelCards, previous) == null) {
        continue;
      }
      final renewed = matches.single;
      if (previous.targetRef == renewed.targetRef) continue;
      _previews?.rebind(previous.targetRef, renewed.targetRef);
      _chatData.rebind(previous.targetRef, renewed.targetRef);
      if (_selected != previous.targetRef) continue;
      _shell.rebind(previous.targetRef, renewed);
      _chatData.portraits.rebind(previous.targetRef, renewed.targetRef);
      _chatData.clearProfiles();
      _selected = renewed.targetRef;
    }
    for (final target in _chatData.targets.toList()) {
      if (!cards.any((c) => c.targetRef == target)) {
        _chatData.remove(target);
        _chatData.views.remove(target);
        _chatData.portraits.remove(target);
      }
    }
    if (_selected != null && !cards.any((c) => c.targetRef == _selected)) {
      _chatData.remove(_selected!);
      _chatData.active = null;
      _avatars.clear();
      _selected = null;
      _query = '';
      _offset = 0;
      changeScope();
    }
    _selected ??= cards.firstOrNull?.targetRef;
    _channelCards = cards;
    _directoryLogos.retain(cards);
    _channelLogos.removeWhere(
      (key, _) => !cards.any((c) => c.targetRef == key),
    );
    final navigation = <Map<String, Object?>>[];
    // First paint uses authorized metadata; previews never hold it hostage.
    for (final card in cards) {
      final logo = await _directoryLogos.read(card);
      if (!current(epoch)) throw StateError('retired');
      _channelLogos[card.targetRef] = logo;
      if (card.targetRef == _selected) _selectedLogo = logo;
      final action = button('切换组织', (_) async {
        final active = currentMenuOrganization(_channelCards, card);
        if (active == null || _selected == active.targetRef) return;
        if ((_previews?.value(active.targetRef)['unread'] as int? ?? 0) > 0) {
          _tab = 'chat';
        }
        _chatData.active?.setReadingContext(visible: false, foreground: false);
        _chatData.active = null;
        _selected = active.targetRef;
        _chatData.sendStatus = 'idle';
        _chatData.sentRevision = 0;
        _selectedLogo = _channelLogos[active.targetRef];
        _query = '';
        _offset = 0;
        _avatars.clear();
        changeScope();
      });
      navigation.add(<String, Object?>{
        'name': card.name,
        ...?_previews?.value(card.targetRef),
        'avatar': _channelLogos[card.targetRef] ?? logo,
        'selected': card.targetRef == _selected,
        'key': action['key'],
      });
    }
    if (!current(epoch)) throw StateError('retired');
    _navigation = navigation;
    _navigationTargets = cards.map((card) => card.targetRef).toList();
  }

  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation;
    _readStage = 'directory';
    if (!chatOnly) await _readNavigation(epoch);
    _profiles.clear();
    final actions = <Map<String, Object?>>[], rows = <Map<String, Object?>>[];
    final sections = <String, Object?>{};
    final presentation = <Map<String, Object?>>[];
    Map<String, Object?>? fleetStatistics;
    final receipts = <String, String>{};
    final messageProfiles = <String, String>{};
    final messagePresentation = <Map<String, Object?>>[];
    if (_selected == null) {
      final directory = await _directoryLogos.readDirectory(
        view: 'mine',
        query: _directoryQuery,
        after: _after,
      );
      final logos = await Future.wait(directory.items.map(_directoryLogo));
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
    if (chatOnly && archive != null && !_chatData.views.containsKey(target)) {
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
          _chatData.views[target] = cached;
          emit(cached);
        }
      } on Object {
        if (!current(epoch)) throw StateError('retired');
      }
    }
    if (chatOnly &&
        (_channelCards.isEmpty ||
            !_channelCards.any((c) => c.targetRef == target))) {
      final directory = await _directoryLogos.readDirectory(
        view: 'mine',
        query: '',
        after: _after,
      );
      if (!current(epoch)) throw StateError('retired');
      _channelCards = directory.items;
      _channelNext = directory.next;
      final logos = await Future.wait(directory.items.map(_directoryLogo));
      if (!current(epoch)) throw StateError('retired');
      for (var i = 0; i < directory.items.length; i++) {
        _channelLogos[directory.items[i].targetRef] = logos[i];
      }
      _selectedLogo = _channelLogos[target];
    }
    // The authenticated chat endpoint checks membership itself. Chat must not
    // wait for member presence, roster media or a second directory round trip.
    _readStage = 'workspace';
    final workspace = chatOnly || _tab == 'chat'
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
          _reset(keepDeliveries: true);
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
    for (final entry in organizationSections(port).entries) {
      if (chatOnly) continue;
      final action = button(entry.value, (_) async {
        if (_tab == entry.key) return;
        changeScope();
        _tab = entry.key;
        if (_tab != 'ships') _ships.statisticsOpen = false;
        _selectPage(0, '');
      });
      actions.add(action);
      sections[entry.key] = action['key'];
    }
    String notice = '';
    var total = workspace?.totalCount ?? 0,
        matched = workspace?.matchedCount ?? 0;
    if (_tab == 'members') {
      actions.add(
        button('搜索成员', (value) async {
          _selectPage(0, value.trim());
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
        final display = organizationMemberPresentation(
          member,
          avatars[i],
          profileKey,
        );
        rows.add(display.row);
        presentation.add(_avatars.bind(display.presentation, target, member));
      }
      actions.addAll(_pageButtons(workspace.next));
    } else if (_tab == 'announcements' && port is CommunityAnnouncementsPort) {
      final page = await (port as CommunityAnnouncementsPort).readAnnouncements(
        target,
        offset: _offset,
      );
      if (!current(epoch) || page.targetRef != target) {
        throw StateError('retired');
      }
      final announcements = [?page.current, ...page.history];
      _announcementDetails.sync(
        port as CommunityAnnouncementsPort,
        target,
        announcements,
      );
      for (final item in announcements) {
        rows.add({'title': item.title, 'detail': item.content});
        presentation.add({
          'announcement': _announcementDetails.binding(item),
          'announcementState': item.state,
          'announcementTime':
              (item == page.current ? item.publishedAt : item.updatedAt)
                  .toUtc()
                  .toIso8601String(),
          'currentAnnouncement': item == page.current,
        });
      }
      actions.addAll(_pageButtons(page.next));
    } else if (_tab == 'chat' && port is CommunityChatPort) {
      _readStage = 'chat';
      final chat = await _chatData.read(target, epoch);
      if (!current(epoch)) throw StateError('retired');
      rows.addAll(chat.rows);
      actions.addAll(chat.actions);
      messagePresentation.addAll(chat.messages);
      messageProfiles.addAll(chat.profiles);
      receipts.addAll(chat.receipts);
      notice = chat.notice;
    } else if (_tab == 'ships' && port is CommunityShipsPort) {
      final fleet = await _ships.read(
        port as CommunityShipsPort,
        port as CommunityWorkspacePort,
        _avatars,
        target,
        _offset,
        _query,
        () {
          if (!current(epoch)) throw StateError('retired');
        },
      );
      final page = fleet.page;
      rows.addAll(fleet.rows);
      presentation.addAll(fleet.presentation);
      fleetStatistics = fleet.statistics;
      notice = fleet.notice;
      total = page.totalCount;
      matched = page.matchedCount;
      actions.add(
        button('搜索舰船', (value) async {
          _selectPage(0, value.trim());
        }, input: '搜索舰船、所有者或用途'),
      );
      actions.add(
        button('舰队统计', (_) async {
          _ships.statisticsOpen = true;
          _shell.sectionTransition = true;
        }),
      );
      actions.add(
        button('关闭统计', (_) async {
          _ships.statisticsOpen = false;
        }, silent: true),
      );
      if (page.next != null) {
        actions.add(
          button('下一页', (_) async {
            _selectPage(page.next!);
          }),
        );
      }
      if (_offset > 0) {
        actions.add(
          button('首页', (_) async {
            _selectPage(0);
          }),
        );
      }
    } else {
      throw StateError('unsupported');
    }
    final card = _channelCards.where((c) => c.targetRef == target).firstOrNull;
    final result = <String, Object?>{
      if (chatOnly) 'channels': channelRows(),
      'title':
          workspace?.name ??
          _navigation
              .where((row) => row['selected'] == true)
              .firstOrNull?['name'] ??
          card?.name ??
          '组织频道',
      'rows': rows,
      'buttons': actions,
      'notice': notice,
      if (_tab == 'chat')
        'chat': {
          ..._chatData.deliveryProjection(_chatData.active!, coherent: true),
          'status': _chatData.sendStatus,
          'availability': _chatData.active?.canSubmit == true
              ? 'ready'
              : 'denied',
          'revision': _chatData.sentRevision,
          'messages': messagePresentation,
          'profiles': messageProfiles,
          'receipts': receipts,
        },
      'organization': {
        'tab': _tab,
        'sections': sections,
        'navigation': _navigation,
        ..._shell.project(target, workspace, card),
        'logo': _selectedLogo,
        'query': _query,
        'total': total,
        'matched': matched,
        'offset': _offset,
        'rows': presentation.isEmpty
            ? [for (final _ in rows) <String, Object?>{}]
            : presentation,
        'fleetStatistics': fleetStatistics,
      },
    };
    if (_tab == 'chat') _chatData.cache(target, result);
    if (!chatOnly && !_shell.reusingDirectory) {
      _previews?.refresh(
        _navigationTargets,
        observedTarget: _tab == 'chat' ? target : null,
      );
    }
    return result;
  }
}
