import 'menu_overlay_locale.dart';
import '../localization/app_strings.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../platform/window/menu_read_feedback.dart';

import 'menu_bridge_style.dart';
import 'menu_organization_view.dart';
import 'menu_room_view.dart';
import 'menu_room_lobby_view.dart';
import 'menu_loading.dart';
import 'menu_channel_outbox.dart';
import 'menu_room_preset_view.dart';
import 'menu_hud_quick_view.dart';

typedef MenuFeatureButton = ({
  String key,
  String label,
  String? role,
  bool secret,
  String? confirm,
  String? input,
  int limit,
});
typedef MenuFeatureRow = ({
  String title,
  String detail,
  bool selected,
  String? avatar,
  List<MenuFeatureButton> buttons,
});

final class MenuFeatureView {
  const MenuFeatureView(
    this.state, {
    this.title = '',
    this.notice = '',
    this.busy = false,
    this.refreshing = false,
    this.readFeedback,
    this.scope = '',
    this.rows = const [],
    this.buttons = const [],
    this.organization,
    this.room,
    this.lobby,
    this.chat,
    this.channels = const [],
    this.rejectedAction,
    this.hudEnabled,
    this.hudQuick,
  });
  final String state, title, notice, scope;
  final bool busy;
  final bool refreshing;
  final MenuReadFeedback? readFeedback;
  final String? rejectedAction;
  final bool? hudEnabled;
  final MenuHudQuickView? hudQuick;
  final List<MenuFeatureRow> rows;
  final List<MenuFeatureButton> buttons;
  final MenuOrganizationView? organization;
  final MenuRoomView? room;
  final MenuRoomLobbyView? lobby;
  final MenuChannelView? chat;
  final List<MenuFeatureRow> channels;
  MenuFeatureView withoutOrganizationImages() => MenuFeatureView(
    state,
    title: title,
    notice: notice,
    scope: scope,
    busy: busy,
    refreshing: refreshing,
    readFeedback: readFeedback,
    rows: rows,
    buttons: buttons,
    organization: organization?.withoutDownloadedImages(),
    room: room,
    lobby: lobby,
    chat: chat,
    channels: [
      for (final row in channels)
        (
          title: row.title,
          selected: row.selected,
          detail: row.detail,
          avatar: null,
          buttons: row.buttons,
        ),
    ],
    rejectedAction: rejectedAction,
    hudEnabled: hudEnabled,
    hudQuick: hudQuick,
  );
  static MenuFeatureView parse(Object? value, {Locale? locale}) {
    try {
      if (value is! Map ||
          !const {
            'idle',
            'loading',
            'ready',
            'unavailable',
          }.contains(value['state'])) {
        throw const FormatException();
      }
      String text(Map map, String key, int max) {
        final v = map[key] ?? '';
        if (v is! String || v.length > max) throw const FormatException();
        return v;
      }

      final keys = <String>{};
      List<MenuFeatureButton> buttons(Object? raw) {
        if (raw == null) return const [];
        if (raw is! List || raw.length > 100) throw const FormatException();
        return raw.map((entry) {
          if (entry is! Map) throw const FormatException();
          final key = text(entry, 'key', 32), limit = entry['limit'];
          if (!RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(key) ||
              !keys.add(key) ||
              limit is! int ||
              limit < 1 ||
              limit > 2048) {
            throw const FormatException();
          }
          return (
            key: key,
            role: _role(entry),
            secret: _boolean(entry, 'secret'),
            label: text(entry, 'label', 128),
            confirm: entry['confirm'] == null
                ? null
                : text(entry, 'confirm', 512),
            input: entry['input'] == null ? null : text(entry, 'input', 128),
            limit: limit,
          );
        }).toList();
      }

      final rawRows = value['rows'] ?? const [];
      if (rawRows is! List || rawRows.length > 500) {
        throw const FormatException();
      }
      final portraits = value['portraits'] ?? const {};
      if (portraits is! Map || portraits.length > 64) {
        throw const FormatException();
      }
      final photos = <String, String>{};
      var photoBytes = 0;
      for (final entry in portraits.entries) {
        if (entry.key is! String ||
            !RegExp(r'^p[0-9]{1,3}$').hasMatch(entry.key)) {
          throw const FormatException();
        }
        final photo = _avatar(entry.value);
        photoBytes += photo.length;
        if (photoBytes > 400000) throw const FormatException();
        photos[entry.key as String] = photo;
      }
      final channelView = value['channels'] == null
          ? null
          : parse({'state': 'ready', 'rows': value['channels']}, locale: locale);
      if (channelView?.state == 'unavailable') throw const FormatException();
      return MenuFeatureView(
        value['state'] as String,
        title: text(value, 'title', 512),
        notice: text(value, 'notice', 512),
        busy: value['busy'] == true,
        hudEnabled: value['hudEnabled'] is bool
            ? value['hudEnabled'] as bool
            : null,
        hudQuick: MenuHudQuickView.parse(value['quick']),
        refreshing: value['refreshing'] == true,
        readFeedback: MenuReadFeedback.parse(value['readFeedback']),
        scope: text(value, 'scope', 32),
        rejectedAction: MenuChannelOutbox.action(value['rejectedAction']),
        buttons: buttons(value['buttons']),
        room: value['room'] == null ? null : MenuRoomView.parse(value['room']),
        lobby: value['lobby'] == null
            ? null
            : MenuRoomLobbyView.parse(
                value['lobby'],
                busy: value['busy'] == true || value['refreshing'] == true,
                rejectedAction: value['rejectedAction'] as String?,
              ),
        organization: value['organization'] == null
            ? null
            : MenuOrganizationView.parse(
                value['organization'],
                rawRows.length,
                keys,
              ),
        chat: value['chat'] == null
            ? null
            : MenuChannelView.parse(value['chat'], rawRows.length),
        channels: channelView?.rows ?? const [],
        rows: rawRows.map((row) {
          if (row is! Map) throw const FormatException();
          return (
            title: text(row, 'title', 512),
            selected: _boolean(row, 'selected'),
            detail: text(row, 'detail', 8192),
            avatar: row['avatar'] == null
                ? photos[row['portrait']]
                : _avatar(row['avatar']),
            buttons: buttons(row['buttons']),
          );
        }).toList(),
      );
    } on Object {
      return MenuFeatureView(
        'unavailable',
        notice: value is Map && value['organization'] != null
            ? AppStrings.resolve(locale ?? const Locale('zh', 'CN'))
                  .text('menu.overlay.errors.organizationData')
            : '',
      );
    }
  }

  static bool _boolean(Map map, String key) {
    if (!map.containsKey(key)) return false;
    if (map[key] is! bool) throw const FormatException();
    return map[key] as bool;
  }

  static String? _role(Map map) {
    if (!map.containsKey('role')) return null;
    final role = map['role'];
    if (role is! String || !RegExp(r'^[a-z][A-Za-z]{0,31}$').hasMatch(role)) {
      throw const FormatException();
    }
    return role;
  }

  static String _avatar(Object? value) {
    if (value is! String ||
        value.length > 28000 ||
        !value.startsWith('data:image/png;base64,')) {
      throw const FormatException();
    }
    return value;
  }

  static (String, MenuFeatureView)? envelope(Object? raw, {Locale? locale}) {
    try {
      if (raw is! String || raw.length > 1048576) return null;
      final map = jsonDecode(raw);
      if (map is! Map ||
          !const {
            'organizations',
            'rooms',
            'hud',
            'organizationChat',
            'roomChat',
          }.contains(map['tool'])) {
        return null;
      }
      return (map['tool'] as String, parse(map, locale: locale));
    } on Object {
      return null;
    }
  }
}

final class MenuChannelView {
  const MenuChannelView(
    this.status,
    this.revision,
    this.messages,
    this.receipts, {
    this.availability = 'denied',
    this.profiles = const {},
    this.systemMessages = const {},
    this.outbox,
    this.ownAvatar,
    this.preset,
  });
  final String status;
  final String availability;
  final int revision;
  final List<({bool self, DateTime time, String role, int? roleColor})>
  messages;
  final Map<int, String> receipts;
  final Map<int, String> profiles;
  final Set<int> systemMessages;
  final MenuChannelOutbox? outbox;
  final String? ownAvatar;
  final MenuRoomPresetView? preset;
  static MenuChannelView parse(Object? raw, int count) {
    if (raw is! Map ||
        !const {
          'idle',
          'sent',
          'rejected',
          'unknown',
        }.contains(raw['status']) ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 0 ||
        raw['messages'] is! List ||
        (raw['messages'] as List).length != count) {
      throw const FormatException();
    }
    final systemMessages = <int>{};
    final messages =
        <({bool self, DateTime time, String role, int? roleColor})>[];
    for (final row in raw['messages'] as List) {
      if (row is! Map || row['self'] is! bool || row['time'] is! String) {
        throw const FormatException();
      }
      final role = row['role'] ?? '', color = row['roleColor'];
      final kind = row['kind'] ?? 'player';
      if (!const {'player', 'system'}.contains(kind)) {
        throw const FormatException();
      }
      if (kind == 'system') systemMessages.add(messages.length);
      if (role is! String ||
          role.length > 128 ||
          color != null &&
              (color is! String ||
                  !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color))) {
        throw const FormatException();
      }
      messages.add((
        self: row['self'] as bool,
        time: DateTime.parse(row['time'] as String),
        role: role,
        roleColor: color == null
            ? null
            : int.parse((color as String).substring(1), radix: 16) | 0xff000000,
      ));
    }
    final receipts = <int, String>{}, values = raw['receipts'] ?? const {};
    if (values is! Map || values.length > count) throw const FormatException();
    for (final entry in values.entries) {
      final index = int.tryParse('${entry.key}');
      if (index == null ||
          index < 0 ||
          index >= count ||
          messages[index].self ||
          systemMessages.contains(index) ||
          entry.value is! String ||
          !RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(entry.value as String)) {
        throw const FormatException();
      }
      receipts[index] = entry.value as String;
    }
    final profiles = <int, String>{};
    final rawProfiles = raw['profiles'] ?? const {};
    if (rawProfiles is! Map || rawProfiles.length > count) {
      throw const FormatException();
    }
    for (final entry in rawProfiles.entries) {
      final index = int.tryParse('${entry.key}');
      if (index == null ||
          index < 0 ||
          index >= count ||
          entry.value is! String ||
          !RegExp(r'^om[1-9][0-9]{0,13}$').hasMatch(entry.value as String)) {
        throw const FormatException();
      }
      profiles[index] = entry.value as String;
    }
    return MenuChannelView(
      raw['status'] as String,
      raw['revision'] as int,
      messages,
      receipts,
      profiles: profiles,
      systemMessages: systemMessages,
      outbox: MenuChannelOutbox.parse(raw),
      preset: MenuRoomPresetView.parse(raw['preset']),
      ownAvatar: raw['ownAvatar'] == null
          ? null
          : MenuFeatureView._avatar(raw['ownAvatar']),
      availability:
          const {'ready', 'denied', 'checking'}.contains(raw['availability'])
          ? raw['availability'] as String
          : 'denied',
    );
  }
}

class MenuFeaturePanel extends StatelessWidget {
  const MenuFeaturePanel({
    super.key,
    required this.view,
    required this.onAction,
    this.actionsAfterRows = false,
  });
  final MenuFeatureView view;
  final bool actionsAfterRows;
  final void Function(String, String) onAction;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: BridgePlate(
      framed: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  view.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              BridgeMenuAction(
                label: menuText(context, 'friends.refresh'),
                onPressed: view.busy ? null : () => onAction('refresh', ''),
                child: Text(menuText(context, 'friends.refresh')),
              ),
            ],
          ),
          if (view.notice.isNotEmpty) BridgeCaption(view.notice),
          if (view.state == 'loading' ||
              view.state == 'idle' ||
              view.refreshing)
            MenuLoading(feedback: view.readFeedback),
          if (view.state != 'ready')
            BridgeCaption(
              view.state == 'unavailable'
                  ? menuText(context, 'menu.overlay.errors.readFailed')
                  : menuText(context, 'menu.overlay.window.readingEllipsis'),
            ),
          if (view.busy) BridgeCaption(menuText(context, 'menu.display.busy')),
          for (final action
              in actionsAfterRows ? <MenuFeatureButton>[] : view.buttons)
            MenuFeatureAction(
              key: ValueKey('${view.scope}/${action.role ?? action.label}'),
              identity: view.scope,
              action: action,
              enabled: !view.busy,
              onAction: onAction,
            ),
          if (view.state == 'ready' && view.rows.isEmpty)
            BridgeCaption(menuText(context, 'menu.overlay.window.empty')),
          for (final row in view.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    row.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (row.detail.isNotEmpty) Text(row.detail),
                  for (final action in row.buttons)
                    MenuFeatureAction(
                      key: ValueKey(
                        '${view.scope}/${row.title}/${action.role ?? action.label}',
                      ),
                      identity: view.scope,
                      action: action,
                      enabled: !view.busy,
                      onAction: onAction,
                    ),
                  const Divider(color: BridgeInk.divider),
                ],
              ),
            ),
          if (actionsAfterRows)
            for (final action in view.buttons)
              MenuFeatureAction(
                key: ValueKey('${view.scope}/${action.role ?? action.label}'),
                identity: view.scope,
                action: action,
                enabled: !view.busy,
                onAction: onAction,
              ),
        ],
      ),
    ),
  );
}

class MenuFeatureAction extends StatefulWidget {
  const MenuFeatureAction({
    super.key,
    required this.action,
    required this.enabled,
    required this.onAction,
    this.outlined = false,
    this.buttonStyle,
    this.identity,
    this.tone,
  });
  final MenuFeatureButton action;
  final bool enabled;
  final void Function(String, String) onAction;
  final bool outlined;
  final ButtonStyle? buttonStyle;

  /// Existing presentation context, separate from rotating command grants.
  final Object? identity;
  final ActionTone? tone;
  @override
  State<MenuFeatureAction> createState() => _FeatureActionState();
}

final class _FeatureDecision {
  _FeatureDecision(this.action, this.identity, this.value);
  final MenuFeatureButton action;
  final Object? identity;
  final String value;
}

class _FeatureActionState extends State<MenuFeatureAction> {
  final input = TextEditingController();
  _FeatureDecision? pending;
  Widget _button({
    required String label,
    required VoidCallback? onPressed,
    required Widget child,
  }) => widget.outlined
      ? StarBridgeActionButton(
          onActivate: onPressed == null ? null : (_) => onPressed(),
          semanticLabel: label,
          nativeStyle: widget.buttonStyle,
          tone: widget.tone,
          child: child,
        )
      : BridgeMenuAction(label: label, onPressed: onPressed, child: child);
  @override
  void didUpdateWidget(MenuFeatureAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged = oldWidget.identity != widget.identity;
    if (contextChanged || oldWidget.action != widget.action) pending = null;
    // A quiet grant renewal keeps the same-context input. Never carry an old
    // context's password/draft into another target or another input purpose.
    if (contextChanged || oldWidget.action.input != widget.action.input) {
      input.clear();
    }
  }

  void _begin() {
    if (!mounted || !widget.enabled) return;
    final action = widget.action;
    if (action.confirm != null) {
      setState(
        () => pending = _FeatureDecision(action, widget.identity, input.text),
      );
    } else {
      widget.onAction(action.key, input.text);
    }
  }

  void _cancel(_FeatureDecision decision) {
    if (!mounted || !identical(pending, decision)) return;
    setState(() => pending = null);
  }

  void _confirm(_FeatureDecision decision) {
    if (!mounted ||
        !widget.enabled ||
        !identical(pending, decision) ||
        widget.identity != decision.identity ||
        widget.action != decision.action) {
      return;
    }
    // Consume only this decision before dispatch; stale/double callbacks cannot
    // act on a later decision. This is not a business-success acknowledgement.
    setState(() => pending = null);
    widget.onAction(decision.action.key, decision.value);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return Padding(
      padding: widget.outlined
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: widget.outlined ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: widget.outlined
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.stretch,
        children: [
          if (action.input != null)
            StarBridgeFieldFrame(
              enabled: widget.enabled,
              builder: (context, focus) => TextField(
                focusNode: focus,
                controller: input,
                enabled: widget.enabled,
                maxLines: action.limit > 128 ? 3 : 1,
                obscureText: action.secret,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(action.limit),
                ],
                decoration: InputDecoration(hintText: action.input),
              ),
            ),
          if (pending case final decision?) ...[
            Text(decision.action.confirm!),
            Wrap(
              children: [
                BridgeMenuAction(
                  label: menuText(context, 'menu.overlay.window.cancel'),
                  onPressed: () => _cancel(decision),
                  child: Text(menuText(context, 'menu.overlay.window.cancel')),
                ),
                BridgeMenuAction(
                  label: menuText(
                    context,
                    'menu.overlay.window.confirmAction',
                    {'action': action.label},
                  ),
                  onPressed: !widget.enabled ? null : () => _confirm(decision),
                  child: Text(
                    menuText(context, 'menu.overlay.window.confirmAction', {
                      'action': action.label,
                    }),
                  ),
                ),
              ],
            ),
          ] else
            _button(
              label: action.label,
              onPressed: !widget.enabled ? null : _begin,
              child: Text(action.label),
            ),
        ],
      ),
    );
  }
}
