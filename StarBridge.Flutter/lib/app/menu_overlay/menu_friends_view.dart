import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../shell/chrome/presence_color.dart';

import 'menu_bridge_style.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import 'menu_loading.dart';
import 'menu_avatar_actions.dart';
import 'menu_friends_controls.dart';
import 'menu_friends_projection.dart';

export 'menu_friends_projection.dart' show MenuFriend, MenuFriendsView;
import '../localization/app_strings.dart';
import '../../features/common/social_identity_text.dart';

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
    'manualOffline' => colors.danger,
    _ => context == null ? BridgeInk.muted : MenuBridgeColors.of(context).muted,
  };
}

/// Display capabilities only; the primary engine revalidates every command.
class MenuFriendsPanel extends StatefulWidget {
  const MenuFriendsPanel({
    super.key,
    required this.view,
    required this.onClose,
    this.onProfile,
    this.embedded = false,
    this.onAction,
    this.onChat,
    this.sort = 'onlineFirst',
  });
  final MenuFriendsView view;
  final VoidCallback onClose;
  final ValueChanged<String>? onProfile;
  final ValueChanged<String>? onChat;
  final bool embedded;
  final String sort;
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
    final ordered = view.rows.indexed.toList();
    if (view.section == 'friends') {
      int rank(String presence) => switch (presence) {
        'inGame' => 0,
        'online' => 1,
        'away' => 2,
        _ => 3,
      };
      ordered.sort((a, b) {
        final status = widget.sort == 'alphabetical'
            ? 0
            : rank(a.$2.presence).compareTo(rank(b.$2.presence));
        if (status != 0) return status;
        final name = a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
        return name != 0 ? name : a.$1.compareTo(b.$1);
      });
    }
    final rows = ordered
        .map((entry) => entry.$2)
        .where((r) => r.name.toLowerCase().contains(query.toLowerCase()));
    final content = <Widget>[
      if (!widget.embedded)
        Row(
          children: [
            Expanded(
              child: Text(
                menuText(context, 'menu.tools.friends'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            if (view.state == 'ready')
              BridgeCaption(
                menuText(context, 'menu.overlay.friends.onlineCount', {
                  'count': onlineCount,
                }),
              ),
            BridgeMenuAction(
              key: ValueKey('menu-panel-close'),
              label: menuText(context, 'menu.overlay.friends.close'),
              onPressed: widget.onClose,
              padding: EdgeInsets.all(10),
              child: MenuGlyphView(MenuGlyph.close, size: 16),
            ),
          ],
        ),
      if (!widget.embedded) SizedBox(height: 20),
      if (view.state == 'idle' || view.state == 'loading' || view.refreshing)
        MenuLoading(feedback: view.readFeedback),
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
          'idle' || 'loading' => menuText(context, 'friends.loading'),
          'signedOut' => menuText(context, 'menu.overlay.friends.signIn'),
          _ =>
            view.requiresRefresh
                ? menuText(context, 'menu.overlay.friends.checkList')
                : menuText(context, 'menu.overlay.friends.unavailable'),
        })
      else ...[
        if (!view.interactive)
          StarBridgeFieldFrame(
            key: const ValueKey('menu-friends-filter-frame'),
            builder: (_, focus) => TextField(
              focusNode: focus,
              key: ValueKey('menu-friends-filter'),
              style: DefaultTextStyle.of(context).style,
              cursorColor: ink.blue,
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                hintText: menuText(context, 'menu.overlay.friends.filter'),
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
          ),
        if (view.section == 'friends') ...[
          BridgeMenuAction(
            key: ValueKey('friends-requests'),
            label: menuText(context, 'menu.overlay.friends.requestCount', {
              'count': view.incoming,
            }),
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
                    menuText(context, 'menu.overlay.friends.requests'),
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
        ] else if (view.section == 'search')
          ..._searchResults(view)
        else
          _section(
            switch (view.section) {
              'incoming' => menuText(context, 'friends.incoming'),
              'outgoing' => menuText(context, 'menu.overlay.friends.outgoing'),
              'blocked' => menuText(context, 'menu.overlay.friends.blocked'),
              _ => menuText(context, 'menu.overlay.friends.results'),
            },
            view.rows.length,
            view.section == 'incoming' ? ink.amber : ink.blue,
          ),
        if (view.rows.isEmpty && view.section != 'search')
          BridgeCaption(
            view.section == 'friends'
                ? menuText(context, 'menu.overlay.friends.empty')
                : menuText(context, 'menu.overlay.friends.noRecords'),
          ),
        if (view.rows.isNotEmpty && rows.isEmpty)
          BridgeCaption(menuText(context, 'menu.overlay.friends.noMatch')),
        if (view.section != 'friends' && view.section != 'search')
          for (final row in rows)
            _person(row, request: view.section == 'incoming'),
        if (view.section == 'friends') ...[
          _section(
            menuText(context, 'menu.overlay.friends.online'),
            onlineCount,
            _statusColor('online'),
          ),
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
            label: menuText(context, 'menu.overlay.friends.toggleOffline'),
            onPressed: () => setState(() => offline = !offline),
            padding: EdgeInsets.zero,
            child: _section(
              menuText(context, 'menu.overlay.friends.offlineSection', {
                'arrow': offline ? '▾' : '▸',
              }),
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
        if (!view.interactive)
          BridgeCaption(menuText(context, 'menu.overlay.friends.readOnly')),
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

  List<Widget> _searchResults(MenuFriendsView view) {
    final friends = view.rows.take(view.matched);
    final others = view.rows.skip(view.matched).toList();
    return [
      if (friends.isNotEmpty) ...[
        _section(
          menuText(context, 'menu.overlay.friends.searchFriends'),
          friends.length,
          ink.muted,
        ),
        for (final row in friends) _person(row),
      ],
      _section(
        menuText(
          context,
          friends.isEmpty
              ? 'menu.overlay.friends.results'
              : 'menu.overlay.friends.searchOthers',
        ),
        others.length,
        ink.blue,
      ),
      for (final row in others) _person(row),
      if (others.isEmpty) ...[
        BridgeCaption(
          friends.isEmpty
              ? menuText(context, 'menu.overlay.friends.noneFound', {
                  'query': view.query,
                })
              : menuText(context, 'menu.overlay.friends.noOthers'),
        ),
        Container(
          margin: EdgeInsets.only(top: 8),
          padding: EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ink.line)),
          ),
          child: BridgeCaption(
            menuText(context, 'menu.overlay.friends.searchRule'),
          ),
        ),
      ],
    ];
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
                identity: (widget.view.scope, row.key),
                name: row.name,
                actions: [
                  if (row.key != null &&
                      widget.view.chatKeys.contains(row.key) &&
                      widget.onChat != null)
                    StarBridgeMenuEntry(
                      id: 'friend-chat-${row.key}',
                      controlKey: ValueKey('friend-chat-${row.key}'),
                      label: menuText(context, 'menu.overlay.friends.message'),
                      onActivate: (_) => widget.onChat!(row.key!),
                      child: Text(
                        menuText(context, 'menu.overlay.friends.message'),
                      ),
                    ),
                  if (row.key != null &&
                      widget.onAction != null &&
                      !widget.view.busy &&
                      !widget.view.requiresRefresh)
                    for (final action
                        in widget.view.actions[row.key] ?? <String>[])
                      StarBridgeMenuEntry(
                        id: 'friend-$action-${row.key}',
                        controlKey: ValueKey('friend-$action-${row.key}'),
                        label: menuFriendActionLabel(context, action),
                        onActivate: (_) =>
                            widget.onAction!('prepare', row.key!, action),
                        child: Text(
                          menuFriendActionLabel(context, action),
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
                  label: canChat
                      ? menuText(context, 'menu.overlay.friends.openChat', {
                          'name': row.name,
                        })
                      : row.name,
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
                                      ? menuText(
                                          context,
                                          'menu.overlay.friends.requested',
                                        )
                                      : switch (row.presence) {
                                          'inGame' => menuText(
                                            context,
                                            'presence.inGame',
                                          ),
                                          'online' => menuText(
                                            context,
                                            'presence.online',
                                          ),
                                          'away' => menuText(
                                            context,
                                            'presence.away',
                                          ),
                                          'offline' => menuText(
                                            context,
                                            'presence.offline',
                                          ),
                                          _ => menuText(
                                            context,
                                            'presence.offline',
                                          ),
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
          if (widget.view.notAddable.contains(row.key))
            Padding(
              padding: EdgeInsets.only(left: 48, top: 4),
              child: BridgeCaption(
                menuText(context, 'menu.overlay.friends.notAddableHere'),
              ),
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
                      label: menuFriendActionLabel(context, action),
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
                        menuFriendActionLabel(context, action),
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
