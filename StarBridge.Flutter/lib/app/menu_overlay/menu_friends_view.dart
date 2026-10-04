import 'dart:convert';

import 'package:flutter/material.dart';

import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../shell/chrome/presence_color.dart';

import 'menu_bridge_style.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import 'menu_loading.dart';
import 'menu_avatar_actions.dart';
import 'menu_friends_controls.dart';
import 'menu_friend_details.dart';
import '../localization/app_strings.dart';
import '../../features/common/social_identity_text.dart';

typedef MenuFriend = ({
  String name,
  String presence,
  String? key,
  String? avatar,
});

// The menu keeps its dark surface even in a light client. Reuse the client's
// dark status tokens and mapping, never the menu's decorative cyan palette.
final _presenceColors = FutureRestraintStyle.resolve(AppearanceMode.dark)
    .colors;
Color menuPresenceColor(String presence, {BuildContext? context}) {
  final colors = context == null
      ? _presenceColors
      : Theme.of(context).extension<StarBridgeTokens>()?.colors ??
            _presenceColors;
  return switch (presence) {
    'inGame' ||
    'online' ||
    'away' ||
    'offline' => presenceColor(colors, 'presence.$presence'),
    'invisible' => colors.offline,
    _ => context == null ? BridgeInk.muted : MenuBridgeColors.of(context).muted,
  };
}

/// Display capabilities only; the primary engine revalidates every command.
final class MenuFriendsView {
  const MenuFriendsView(
    this.state, {
    this.incoming = 0,
    this.rows = const [],
    this.requests = const [],
    this.identity,
    this.scope = '',
    this.interactive = false,
    this.busy = false,
    this.refreshing = false,
    this.requiresRefresh = false,
    this.section = 'friends',
    this.query = '',
    this.feedback = '',
    this.actions = const {},
    this.chatKeys = const {},
    this.self,
    this.confirmation,
    this.details = const {},
    this.gameIds = const {},
  });
  final String state;
  final String scope;
  final int incoming;
  final List<MenuFriend> rows;
  final List<MenuFriend> requests;
  final Map<String, MenuFriendDetails> details;
  final Map<String, String> gameIds;
  final ({String name, String handle, String? avatar})? identity;
  final bool interactive, busy, requiresRefresh;
  final bool refreshing;
  final String section, query, feedback;
  final Map<String, List<String>> actions;
  final Set<String> chatKeys;
  final ({String key, String status, bool change, bool busy, bool failed})?
  self;
  final ({String token, String name, String action})? confirmation;
  static const commandNames = {
    'send',
    'accept',
    'reject',
    'cancel',
    'remove',
    'block',
    'unblock',
  };
  static MenuFriendsView parse(Object? wire) {
    try {
      if (wire is! String || wire.length > 1048576) {
        throw const FormatException();
      }
      final data = jsonDecode(wire);
      if (data is! Map ||
          !const [
            'idle',
            'loading',
            'ready',
            'signedOut',
            'unavailable',
          ].contains(data['state'])) {
        throw const FormatException();
      }
      final interactive = data['interactive'] == true;
      final scope = data['scope'] ?? '';
      if (scope is! String ||
          (scope.isNotEmpty &&
              !RegExp(r'^friends[0-9]{1,13}$').hasMatch(scope))) {
        throw const FormatException();
      }
      final section = interactive ? data['section'] : 'friends';
      final query = interactive ? data['query'] : '';
      final feedback = interactive ? data['feedback'] : '';
      final busy = interactive ? data['busy'] : false;
      final refresh = interactive ? data['requiresRefresh'] : false;
      final allowed = <String, List<String>>{};
      ({String token, String name, String action})? confirmation;
      if (!const {
            'friends',
            'incoming',
            'outgoing',
            'blocked',
            'search',
          }.contains(section) ||
          query is! String ||
          query.length > 128 ||
          feedback is! String ||
          !{
            '',
            'invalidSearch',
            'expired',
            'rejected',
            'unknown',
            'reviewed',
            for (final action in commandNames) 'success.$action',
          }.contains(feedback) ||
          busy is! bool ||
          refresh is! bool) {
        throw const FormatException();
      }
      if (interactive) {
        final raw = data['actions'];
        if (raw is! Map || raw.length > 5000) throw const FormatException();
        for (final entry in raw.entries) {
          if (entry.key is! String ||
              (entry.key as String).isEmpty ||
              (entry.key as String).length > 64 ||
              entry.value is! List ||
              (entry.value as List).length > 7 ||
              (entry.value as List).any((v) => !commandNames.contains(v))) {
            throw const FormatException();
          }
          allowed[entry.key as String] = List<String>.unmodifiable(
            entry.value as List,
          );
        }
        final pending = data['confirmation'];
        if (pending != null) {
          if (pending is! Map ||
              pending['token'] is! String ||
              !RegExp(r'^confirm[1-9][0-9]{0,12}$')
                  .hasMatch(pending['token'] as String) ||
              pending['name'] is! String ||
              (pending['name'] as String).length > 128 ||
              !commandNames.contains(pending['action'])) {
            throw const FormatException();
          }
          confirmation = (
            token: pending['token'] as String,
            name: pending['name'] as String,
            action: pending['action'] as String,
          );
        }
      }
      final ready = data['state'] == 'ready';
      final rows = ready ? data['rows'] : const [],
          incoming = ready ? data['incoming'] : 0;
      if (rows is! List ||
          rows.length > 5000 ||
          incoming is! int ||
          incoming < 0) {
        throw const FormatException();
      }
      final parsed = [for (final row in rows) _row(row)];
      final details = <String, MenuFriendDetails>{};
      final gameIds = <String, String>{};
      for (var i = 0; i < parsed.length; i++) {
        final row = parsed[i];
        final raw = rows[i] as Map;
        if (section == 'friends' && row.key != null) {
          final gameId = raw['gameId'];
          if (gameId != null) {
            if (gameId is! String ||
                gameId.length > 128 ||
                gameId.runes.any((code) => code < 32 || code == 127)) {
              throw const FormatException();
            }
            gameIds[row.key!] = gameId;
          }
        }
        if (row.presence == 'inGame' &&
            row.key != null &&
            section == 'friends') {
          final detail = MenuFriendDetails.parse(
            raw['details'],
            raw['detailLabels'],
          );
          if (detail != null) details[row.key!] = detail;
        }
      }
      final requests = ready ? data['requests'] ?? const [] : const [];
      if (requests is! List || requests.length + rows.length > 5000) {
        throw const FormatException();
      }
      final parsedRequests = [for (final row in requests) _row(row)];
      final keys = <String>{};
      if ([
        ...parsed,
        ...parsedRequests,
      ].any((r) => r.key != null && !keys.add(r.key!))) {
        throw const FormatException();
      }
      final chats = data['chatKeys'] ?? const [];
      if (chats is! List ||
          chats.length > 5000 ||
          chats.any((key) => key is! String || !keys.contains(key))) {
        throw const FormatException();
      }
      final own = data['self'];
      final identity = data['identity'];
      MenuFriend? identityRow;
      if (identity != null) {
        if (identity is! Map ||
            identity['handle'] is! String ||
            (identity['handle'] as String).length > 128) {
          throw const FormatException();
        }
        identityRow = _row({...identity, 'key': null, 'presence': 'unknown'});
      }
      if (own != null &&
          (own is! Map ||
              own['key'] is! String ||
              !RegExp(r'^self[0-9]{1,13}$').hasMatch(own['key'] as String) ||
              !const {
                'presence.online',
                'presence.inGame',
                'presence.away',
                'presence.offline',
                'presence.unknown',
                'presence.invisible',
              }.contains(own['status']) ||
              own['change'] is! bool ||
              own['busy'] is! bool ||
              own['failed'] is! bool)) {
        throw const FormatException();
      }
      return MenuFriendsView(
        data['state'] as String,
        incoming: incoming,
        scope: scope,
        rows: List.unmodifiable(parsed),
        details: Map.unmodifiable(details),
        gameIds: Map.unmodifiable(gameIds),
        requests: List.unmodifiable(parsedRequests),
        identity: identityRow == null
            ? null
            : (
                name: identityRow.name,
                handle: identity['handle'] as String,
                avatar: identityRow.avatar,
              ),
        interactive: interactive,
        section: section as String,
        query: query,
        feedback: feedback,
        busy: busy,
        refreshing: data['refreshing'] == true,
        requiresRefresh: refresh,
        actions: Map.unmodifiable(allowed),
        confirmation: confirmation,
        chatKeys: Set<String>.unmodifiable(chats.cast<String>()),
        self: own == null
            ? null
            : (
                key: own['key'] as String,
                status: own['status'] as String,
                change: own['change'] as bool,
                busy: own['busy'] as bool,
                failed: own['failed'] as bool,
              ),
      );
    } on Object {
      return const MenuFriendsView('unavailable');
    }
  }

  static MenuFriend _row(dynamic row) {
    if (row is! Map ||
        row['name'] is! String ||
        (row['name'] as String).length > 128 ||
        !const [
          'inGame',
          'online',
          'away',
          'offline',
          'unknown',
        ].contains(row['presence'])) {
      throw const FormatException();
    }
    final key = row['key'], avatar = row['avatar'];
    if ((key != null && (key is! String || key.isEmpty || key.length > 64)) ||
        (avatar != null &&
            (avatar is! String ||
                avatar.length > 128 * 1024 ||
                !(avatar.startsWith('data:image/png;base64,') ||
                    avatar.startsWith('data:image/jpeg;base64,'))))) {
      throw const FormatException();
    }
    return (
      name: row['name'] as String,
      presence: row['presence'] as String,
      key: key as String?,
      avatar: avatar as String?,
    );
  }
}

class MenuFriendsPanel extends StatefulWidget {
  const MenuFriendsPanel({
    super.key,
    required this.view,
    required this.onClose,
    this.onProfile,
    this.embedded = false,
    this.onAction,
    this.onChat,
  });
  final MenuFriendsView view;
  final VoidCallback onClose;
  final ValueChanged<String>? onProfile;
  final ValueChanged<String>? onChat;
  final bool embedded;
  final void Function(String action, String key, String value)? onAction;
  @override
  State<MenuFriendsPanel> createState() => _MenuFriendsPanelState();
}

class _MenuFriendsPanelState extends State<MenuFriendsPanel> {
  MenuBridgeColors get ink => MenuBridgeColors.of(context);
  Color _statusColor(String value) =>
      menuPresenceColor(value, context: context);

  String query = '';
  bool offline = true;
  @override
  void didUpdateWidget(MenuFriendsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.section != widget.view.section ||
        oldWidget.view.scope != widget.view.scope) {
      query = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final onlineCount = view.rows
        .where((r) => ['online', 'inGame', 'away'].contains(r.presence))
        .length;
    final rows = view.rows.where(
      (r) => r.name.toLowerCase().contains(query.toLowerCase()),
    );
    final content = <Widget>[
      if (!widget.embedded)
        Row(
          children: [
            Expanded(
              child: Text(
                '好友',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            if (view.state == 'ready') BridgeCaption('$onlineCount 在线'),
            BridgeMenuAction(
              key: ValueKey('menu-panel-close'),
              label: '关闭好友面板',
              onPressed: widget.onClose,
              padding: EdgeInsets.all(10),
              child: MenuGlyphView(MenuGlyph.close, size: 16),
            ),
          ],
        ),
      if (!widget.embedded) SizedBox(height: 20),
      if (view.state == 'idle' || view.state == 'loading' || view.refreshing)
        MenuLoading(),
      if (view.interactive && widget.onAction != null)
        MenuFriendsControls(
          key: ValueKey(view.scope),
          view: view,
          onAction: widget.onAction!,
          onFilter: (value) =>
              setState(() => query = view.section == 'friends' ? value : ''),
        ),
      if (view.state != 'ready')
        BridgeCaption(switch (view.state) {
          'idle' || 'loading' => '正在读取好友…',
          'signedOut' => '请先在客户端登录。',
          _ => view.requiresRefresh ? '请刷新列表核对当前关系。' : '暂时无法读取好友，将自动重试。',
        })
      else ...[
        if (!view.interactive)
          TextField(
            key: ValueKey('menu-friends-filter'),
            style: DefaultTextStyle.of(context).style,
            cursorColor: ink.blue,
            onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(
              hintText: '筛选已有好友',
              hintStyle: TextStyle(color: ink.muted, fontSize: 14),
              filled: true,
              fillColor: ink.ground,
              contentPadding: EdgeInsets.all(10),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: ink.line),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: ink.line),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: ink.blue),
              ),
              isDense: true,
            ),
          ),
        if (view.section == 'friends') ...[
          BridgeMenuAction(
            key: ValueKey('friends-requests'),
            label: '好友申请 · ${view.incoming}',
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            onPressed: widget.onAction == null || view.busy
                ? null
                : () => widget.onAction!('section', '', 'incoming'),
            child: Row(
              children: [
                MenuGlyphView(
                  MenuGlyph.addFriend,
                  size: 18,
                  color: view.incoming > 0 ? ink.amber : ink.muted,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '好友申请',
                    style: TextStyle(
                      fontSize: 13,
                      color: view.incoming > 0 ? ink.amber : ink.text,
                    ),
                  ),
                ),
                Text(
                  '${view.incoming}',
                  style: TextStyle(
                    color: view.incoming > 0 ? ink.amber : ink.muted,
                  ),
                ),
                SizedBox(width: 8),
                MenuGlyphView(MenuGlyph.next, size: 16, color: ink.muted),
              ],
            ),
          ),
          for (final row in view.requests) _person(row, request: true),
        ] else
          _section(
            switch (view.section) {
              'incoming' => '收到的申请',
              'outgoing' => '已发出的申请',
              'blocked' => '屏蔽名单',
              _ => '搜索结果',
            },
            view.rows.length,
            view.section == 'incoming' ? ink.amber : ink.blue,
          ),
        if (view.rows.isEmpty)
          BridgeCaption(view.section == 'friends' ? '暂无好友' : '暂无记录'),
        if (view.rows.isNotEmpty && rows.isEmpty) BridgeCaption('没有匹配的好友'),
        if (view.section != 'friends')
          for (final row in rows)
            _person(row, request: view.section == 'incoming'),
        if (view.section == 'friends') ...[
          _section('在线', onlineCount, _statusColor('online')),
          for (final row in rows.where(
            (r) => ['online', 'inGame', 'away'].contains(r.presence),
          ))
            _person(row),
        ],
        if (view.section == 'friends' &&
            rows.any(
              (r) => r.presence == 'offline' || r.presence == 'unknown',
            )) ...[
          BridgeMenuAction(
            label: '展开或收起离线好友',
            onPressed: () => setState(() => offline = !offline),
            padding: EdgeInsets.zero,
            child: _section(
              '${offline ? '▾' : '▸'} 离线',
              rows
                  .where(
                    (r) => r.presence == 'offline' || r.presence == 'unknown',
                  )
                  .length,
              ink.muted,
            ),
          ),
          if (offline)
            for (final row in rows.where(
              (r) => r.presence == 'offline' || r.presence == 'unknown',
            ))
              _person(row),
        ],
        SizedBox(height: 12),
        if (!view.interactive) BridgeCaption('只读试用 · 好友操作请在客户端进行'),
      ],
    ];
    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    Widget plate(Widget child) => BridgePlate(
      framed: !widget.embedded,
      padding: EdgeInsets.all(12),
      child: child,
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (!bounds.hasBoundedHeight) return plate(column(content));
        final controls = content.indexWhere(
          (item) => item is MenuFriendsControls,
        );
        // Keep identity/search reachable in normal windows; very short windows,
        // large text and confirmations use one scrollable surface instead.
        final pinned =
            controls >= 0 &&
            bounds.maxHeight >= 440 &&
            MediaQuery.textScalerOf(context).scale(14) <= 21 &&
            view.confirmation == null &&
            view.feedback.isEmpty;
        if (pinned) {
          return plate(
            column([
              ...content.take(controls + 1),
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey('menu-scroll-friends'),
                  child: column(content.skip(controls + 1).toList()),
                ),
              ),
            ]),
          );
        }
        return SingleChildScrollView(
          key: ValueKey('menu-scroll-friends'),
          child: plate(column(content)),
        );
      },
    );
  }

  Widget _section(String label, int count, Color color) => Container(
    margin: EdgeInsets.only(top: 10, bottom: 4),
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    width: double.infinity,
    color: color.withValues(alpha: .08),
    child: Text(
      '$label · $count',
      style: TextStyle(fontSize: 12, color: color),
    ),
  );

  Widget _person(MenuFriend row, {bool request = false}) {
    // Presentation only: retain unknown in the source for privacy/event gates.
    final color = request
        ? ink.amber
        : _statusColor(row.presence == 'unknown' ? 'offline' : row.presence);
    final canChat =
        row.key != null &&
        widget.view.chatKeys.contains(row.key) &&
        widget.onChat != null &&
        !widget.view.busy &&
        !widget.view.requiresRefresh;
    final allowed = widget.view.actions[row.key] ?? <String>[];
    return Container(
      key: ValueKey('friend-row-${row.key ?? row.name}'),
      margin: EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      padding: EdgeInsets.only(left: 8, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MenuAvatarActions(
                key: row.key == null ? null : ValueKey<String>(row.key!),
                name: row.name,
                actions: [
                  if (row.key != null &&
                      widget.view.chatKeys.contains(row.key) &&
                      widget.onChat != null)
                    MenuItemButton(
                      key: ValueKey('friend-chat-${row.key}'),
                      onPressed: () => widget.onChat!(row.key!),
                      child: Text('发消息'),
                    ),
                  if (row.key != null &&
                      widget.onAction != null &&
                      !widget.view.busy &&
                      !widget.view.requiresRefresh)
                    for (final action
                        in widget.view.actions[row.key] ?? <String>[])
                      MenuItemButton(
                        key: ValueKey('friend-$action-${row.key}'),
                        onPressed: () =>
                            widget.onAction!('prepare', row.key!, action),
                        child: Text(
                          menuFriendActionLabel(action),
                          style: TextStyle(
                            color: {'remove', 'block'}.contains(action)
                                ? ink.danger
                                : ink.text,
                          ),
                        ),
                      ),
                ],
                onProfile: row.key == null || widget.onProfile == null
                    ? null
                    : () => widget.onProfile!(row.key!),
                child: MenuInlineAvatar(source: row.avatar, name: row.name),
              ),
              SizedBox(width: 12),
              Expanded(
                child: BridgeMenuAction(
                  key: ValueKey('friend-open-${row.key}'),
                  label: canChat ? '${row.name} · 打开聊天' : row.name,
                  onPressed: canChat ? () => widget.onChat!(row.key!) : null,
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SocialIdentityText(
                              callsign: row.name,
                              gameId: widget.view.gameIds[row.key] ?? '',
                              callsignStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              gameIdColor: ink.muted,
                            ),
                            Wrap(
                              key: ValueKey('friend-shared-details-${row.key}'),
                              spacing: 8,
                              runSpacing: 2,
                              children: [
                                Text(
                                  request
                                      ? '请求添加你为好友'
                                      : switch (row.presence) {
                                          'inGame' => '游戏中',
                                          'online' => '应用在线',
                                          'away' => '暂离',
                                          'offline' => '离线',
                                          _ => '离线',
                                        },
                                  style: TextStyle(fontSize: 12, color: color),
                                ),
                                if (!request && row.presence == 'inGame') ...[
                                  for (final detail
                                      in widget.view.details[row.key]
                                              ?.localized(
                                                AppStrings.of(context),
                                              ) ??
                                          <String>[])
                                    Text(
                                      detail,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (canChat)
                        MenuGlyphView(
                          MenuGlyph.next,
                          size: 16,
                          color: ink.muted,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (widget.onAction != null &&
              (request || widget.view.section != 'friends'))
            Padding(
              padding: EdgeInsets.only(left: 48, top: 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final action in allowed.where(
                    (a) => {
                      'accept',
                      'reject',
                      'send',
                      'cancel',
                      'unblock',
                    }.contains(a),
                  ))
                    BridgeMenuAction(
                      key: ValueKey('friend-inline-$action-${row.key}'),
                      label: menuFriendActionLabel(action),
                      onPressed:
                          widget.view.busy ||
                              widget.view.requiresRefresh ||
                              row.key == null
                          ? null
                          : () => widget.onAction!('prepare', row.key!, action),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        menuFriendActionLabel(action),
                        style: TextStyle(
                          fontSize: 12,
                          color: action == 'accept'
                              ? ink.green
                              : action == 'send'
                              ? ink.blue
                              : ink.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
