import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_bridge_style.dart';
import 'menu_organization_view.dart';
import 'menu_loading.dart';

typedef MenuFeatureButton = ({
  String key,
  String label,
  String? confirm,
  String? input,
  int limit,
});
typedef MenuFeatureRow = ({
  String title,
  String detail,
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
    this.scope = '',
    this.rows = const [],
    this.buttons = const [],
    this.organization,
    this.chat,
    this.channels = const [],
  });
  final String state, title, notice, scope;
  final bool busy;
  final bool refreshing;
  final List<MenuFeatureRow> rows;
  final List<MenuFeatureButton> buttons;
  final MenuOrganizationView? organization;
  final MenuChannelView? chat;
  final List<MenuFeatureRow> channels;
  static MenuFeatureView parse(Object? value) {
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
      return MenuFeatureView(
        value['state'] as String,
        title: text(value, 'title', 512),
        notice: text(value, 'notice', 512),
        busy: value['busy'] == true,
        refreshing: value['refreshing'] == true,
        scope: text(value, 'scope', 32),
        buttons: buttons(value['buttons']),
        organization: value['organization'] == null
            ? null
            : MenuOrganizationView.parse(value['organization'], rawRows.length),
        chat: value['chat'] == null
            ? null
            : MenuChannelView.parse(value['chat'], rawRows.length),
        channels: value['channels'] == null
            ? const []
            : parse({'state': 'ready', 'rows': value['channels']}).rows,
        rows: rawRows.map((row) {
          if (row is! Map) throw const FormatException();
          return (
            title: text(row, 'title', 512),
            detail: text(row, 'detail', 8192),
            avatar: row['avatar'] == null
                ? photos[row['portrait']]
                : _avatar(row['avatar']),
            buttons: buttons(row['buttons']),
          );
        }).toList(),
      );
    } on Object {
      return const MenuFeatureView('unavailable');
    }
  }

  static String _avatar(Object? value) {
    if (value is! String ||
        value.length > 28000 ||
        !value.startsWith('data:image/png;base64,')) {
      throw const FormatException();
    }
    return value;
  }

  static (String, MenuFeatureView)? envelope(Object? raw) {
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
      return (map['tool'] as String, parse(map));
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
  });
  final String status;
  final String availability;
  final int revision;
  final List<({bool self, DateTime time, String role, int? roleColor})>
  messages;
  final Map<int, String> receipts;
  final Map<int, String> profiles;
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
    final messages =
        <({bool self, DateTime time, String role, int? roleColor})>[];
    for (final row in raw['messages'] as List) {
      if (row is! Map || row['self'] is! bool || row['time'] is! String) {
        throw const FormatException();
      }
      final role = row['role'] ?? '', color = row['roleColor'];
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
                label: '刷新',
                onPressed: view.busy ? null : () => onAction('refresh', ''),
                child: const Text('刷新'),
              ),
            ],
          ),
          if (view.notice.isNotEmpty) BridgeCaption(view.notice),
          if (view.state == 'loading' ||
              view.state == 'idle' ||
              view.refreshing)
            const MenuLoading(),
          if (view.state != 'ready')
            BridgeCaption(
              view.state == 'unavailable' ? '暂时无法读取，请刷新重试。' : '正在读取…',
            ),
          if (view.busy) const BridgeCaption('正在处理…'),
          for (final action
              in actionsAfterRows ? <MenuFeatureButton>[] : view.buttons)
            MenuFeatureAction(
              key: ValueKey('${view.scope}/${action.label}'),
              action: action,
              enabled: !view.busy,
              onAction: onAction,
            ),
          if (view.state == 'ready' && view.rows.isEmpty)
            const BridgeCaption('暂无内容'),
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
                        '${view.scope}/${row.title}/${action.label}',
                      ),
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
                key: ValueKey('${view.scope}/${action.label}'),
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
  });
  final MenuFeatureButton action;
  final bool enabled;
  final void Function(String, String) onAction;
  @override
  State<MenuFeatureAction> createState() => _FeatureActionState();
}

class _FeatureActionState extends State<MenuFeatureAction> {
  final input = TextEditingController();
  String? pending;
  @override
  void didUpdateWidget(MenuFeatureAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action.key != widget.action.key) pending = null;
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (action.input != null)
            TextField(
              controller: input,
              enabled: widget.enabled,
              maxLines: action.limit > 128 ? 3 : 1,
              obscureText: action.input == '房间密码',
              inputFormatters: [LengthLimitingTextInputFormatter(action.limit)],
              decoration: InputDecoration(hintText: action.input),
            ),
          if (pending != null) ...[
            Text(action.confirm!),
            Wrap(
              children: [
                BridgeMenuAction(
                  label: '取消',
                  onPressed: () => setState(() => pending = null),
                  child: const Text('取消'),
                ),
                BridgeMenuAction(
                  label: '确认${action.label}',
                  onPressed: !widget.enabled
                      ? null
                      : () {
                          widget.onAction(action.key, pending!);
                          setState(() => pending = null);
                        },
                  child: Text('确认${action.label}'),
                ),
              ],
            ),
          ] else
            BridgeMenuAction(
              label: action.label,
              onPressed: !widget.enabled
                  ? null
                  : () {
                      if (action.confirm != null) {
                        setState(() => pending = input.text);
                      } else {
                        widget.onAction(action.key, input.text);
                      }
                    },
              child: Text(action.label),
            ),
        ],
      ),
    );
  }
}
