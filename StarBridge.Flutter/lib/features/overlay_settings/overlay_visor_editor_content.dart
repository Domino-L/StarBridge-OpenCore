import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../design_system/styles/overlay_visor_sim_palette.dart';

import 'overlay_workspace_models.dart';

/// What the visor would show, read from the Host for the layout editor's own
/// simplified panels (11-12 user: "编辑里还是要用模拟面板，只不过信息都一致",
/// "可以是简化版的面板，只有框和背景那种，其他都按照真实的来"): the real fleet
/// members when there are any, else samples; sample events filling the events
/// box; the chat, else samples; the decoration colour. Text only: the editor
/// draws it, so nothing blurs or blinks while blocks move.
abstract interface class OverlayVisorEditorContentPort {
  bool get supportsVisorEditorContent;

  /// The content for [draft] in [language].
  Future<OverlayVisorEditorContent> readVisorEditorContent({
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  });
}

/// A member row as the visor shows it.
final class OverlayVisorEditorMember {
  const OverlayVisorEditorMember({
    required this.name,
    required this.ship,
    required this.place,
    required this.status,
    required this.state,
    required this.sameServer,
    required this.pinned,
    this.vitals = 'Unknown',
    this.health = 0,
  });

  final String name, ship, place, status;

  /// InGame, AppOnly, Away or Offline.
  final String state;
  final bool sameServer, pinned;

  /// Unknown, Alive, Downed or Dead (only your own row may know it).
  final String vitals;
  final double health;
}

final class OverlayVisorEditorEvent {
  const OverlayVisorEditorEvent(this.title, this.detail, this.time, this.tone);
  final String title, detail, time;

  /// The kind's title colour: None, Place, Ship, Server, SameServer, Bad,
  /// Good or Reminder.
  final String tone;
}

final class OverlayVisorEditorChatLine {
  const OverlayVisorEditorChatLine(this.who, this.text);
  final String who, text;
}

final class OverlayVisorEditorContent {
  const OverlayVisorEditorContent({
    required this.sample,
    required this.decoration,
    required this.membersTitle,
    required this.youAt,
    required this.online,
    required this.inGame,
    required this.sameServer,
    required this.page,
    this.countLabels = const ['在线', '游戏中', '同服'],
    required this.members,
    required this.eventsTitle,
    this.eventsSample = true,
    required this.events,
    required this.chatTitle,
    required this.chatSample,
    required this.chat,
  });

  /// No fleet members to show: the members are samples.
  final bool sample;

  /// The colour the visor decorates with (theme or ship palette).
  final Color decoration;
  final String membersTitle, youAt, page;

  /// The count labels (online, in game, same server) in the visor's language.
  final List<String> countLabels;
  final int online, inGame, sameServer;
  final List<OverlayVisorEditorMember> members;
  final String eventsTitle;

  /// No events show right now: the events are samples filling the box.
  final bool eventsSample;
  final List<OverlayVisorEditorEvent> events;
  final String chatTitle;
  final bool chatSample;
  final List<OverlayVisorEditorChatLine> chat;

  static String _text(Object? value) =>
      value is String ? value : throw const FormatException('text');
  static int _count(Object? value) =>
      value is int && value >= 0 ? value : throw const FormatException('count');
  static List<Object?> _list(Object? value) =>
      value is List ? value : throw const FormatException('list');
  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? value : throw const FormatException('map');
  static bool _bool(Object? value) =>
      value is bool ? value : throw const FormatException('bool');
  static String _one(Object? value, Set<String> allowed) =>
      value is String && allowed.contains(value)
      ? value
      : throw const FormatException('value');
  static double _share(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 1
      ? value.toDouble()
      : throw const FormatException('share');

  static const _states = {'InGame', 'AppOnly', 'Away', 'Offline'};
  static const _vitals = {'Unknown', 'Alive', 'Downed', 'Dead'};
  static const _tones = {
    'None',
    'Place',
    'Ship',
    'Server',
    'SameServer',
    'Bad',
    'Good',
    'Reminder',
  };

  /// The Host's reply.
  static OverlayVisorEditorContent fromMap(Map<String, Object?> body) {
    if (body['schemaVersion'] != 1 || body['sample'] is! bool) {
      throw const FormatException('Invalid visor editor content.');
    }
    final members = _map(body['members']);
    final events = _map(body['events']);
    final chat = _map(body['chat']);
    final colour = _text(body['decoration']);
    final rgb = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(colour);
    if (rgb == null || chat['sample'] is! bool) {
      throw const FormatException('Invalid visor editor content.');
    }
    return OverlayVisorEditorContent(
      sample: body['sample'] as bool,
      decoration: OverlayVisorSimPalette.opaque(
        int.parse(rgb.group(1)!, radix: 16),
      ),
      membersTitle: _text(members['title']),
      youAt: _text(members['youAt']),
      online: _count(members['online']),
      inGame: _count(members['inGame']),
      sameServer: _count(members['sameServer']),
      page: _text(members['page']),
      countLabels: switch (members['counts']) {
        final List<Object?> labels when labels.length == 3 => [
          for (final label in labels) _text(label),
        ],
        _ => throw const FormatException('counts'),
      },
      members: [
        for (final row in _list(members['rows']).map(_map))
          OverlayVisorEditorMember(
            name: _text(row['name']),
            ship: _text(row['ship']),
            place: _text(row['place']),
            status: _text(row['status']),
            state: _one(row['state'], _states),
            sameServer: _bool(row['sameServer']),
            pinned: _bool(row['pinned']),
            vitals: _one(row['vitals'], _vitals),
            health: _share(row['health']),
          ),
      ],
      eventsTitle: _text(events['title']),
      eventsSample: _bool(events['sample']),
      events: [
        for (final row in _list(events['rows']).map(_map))
          OverlayVisorEditorEvent(
            _text(row['title']),
            _text(row['detail']),
            _text(row['time']),
            _one(row['tone'], _tones),
          ),
      ],
      chatTitle: _text(chat['title']),
      chatSample: chat['sample'] as bool,
      chat: [
        for (final row in _list(chat['rows']).map(_map))
          OverlayVisorEditorChatLine(_text(row['who']), _text(row['text'])),
      ],
    );
  }
}

/// Asks the Host for the content of the current draft: when the editor opens,
/// after a draft change (waiting [debounce] for the next), and every [refresh]
/// while it stays open, so live members stay current. One request at a time;
/// the content shown stays until the next arrives (a failure keeps it too), so
/// the panels never blink.
final class OverlayVisorEditorContentSource extends ChangeNotifier {
  OverlayVisorEditorContentSource({
    required this.port,
    required this.language,
    required this.draft,
    this.debounce = const Duration(milliseconds: 300),
    this.refresh = const Duration(seconds: 10),
  });

  final OverlayVisorEditorContentPort port;
  final String Function() language;
  final OverlayWorkspaceRuntimeDraft? Function() draft;
  final Duration debounce, refresh;

  OverlayVisorEditorContent? _content;
  Object? _wanted, _asked;
  Timer? _timer, _refresh;
  bool _running = false, _disposed = false;

  /// The latest content, or null before the first reply.
  OverlayVisorEditorContent? get content => _content;

  /// Called while the editor builds with what the content depends on (the
  /// draft's sources and display settings, and the language): a change asks
  /// again after [debounce].
  void sync(Object? key) {
    if (_disposed) return;
    final wanted = (key, language());
    if (_wanted == wanted && (_content != null || _running)) return;
    _wanted = wanted;
    _timer?.cancel();
    _timer = Timer(_content == null ? Duration.zero : debounce, _ask);
    _refresh ??= Timer.periodic(refresh, (_) {
      if (!_running) _ask(force: true);
    });
  }

  Future<void> _ask({bool force = false}) async {
    if (_disposed || _running) return;
    final wanted = _wanted;
    if (!force && wanted == _asked && _content != null) return;
    _running = true;
    _asked = wanted;
    try {
      final next = await port.readVisorEditorContent(
        language: language(),
        draft: draft(),
      );
      if (_disposed) return;
      _content = next;
      notifyListeners();
    } on Object {
      // keep what is shown; the next change or refresh asks again
    } finally {
      _running = false;
    }
    if (!_disposed && _wanted != _asked) unawaited(_ask());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _refresh?.cancel();
    super.dispose();
  }
}

/// What the editor shows before the Host answers, or without a Host: sample
/// members, events and chat with names that are plainly samples (user: "示例
/// 数据就写全用示例名字/模拟名字"), the decoration the default colour.
OverlayVisorEditorContent overlayVisorSampleContent(
  String Function(String key) text,
) {
  String name(int n) =>
      '${text('overlay.sample.visorMember')} ${n.toString().padLeft(2, '0')}';
  final ship = text('overlay.sample.memberShip');
  final place = text('overlay.sample.orison');
  const tones = ['Place', 'Ship', 'Server', 'Place', 'SameServer'];
  const times = ['20:41', '20:39', '20:37', '20:35', '20:33'];
  return OverlayVisorEditorContent(
    sample: true,
    decoration: OverlayVisorSimPalette.defaultDecoration,
    membersTitle: text('overlay.sample.visorMembersTitle'),
    youAt: '${text('overlay.sample.usServer')} #001',
    online: 6,
    inGame: 5,
    sameServer: 3,
    page: '',
    countLabels: [
      text('overlay.sample.online'),
      text('overlay.sample.inGame'),
      text('overlay.sample.visorSameServer'),
    ],
    members: [
      for (var i = 1; i <= 6; i++)
        OverlayVisorEditorMember(
          name: name(i),
          ship: ship,
          place: place,
          status: '',
          state: 'InGame',
          sameServer: i <= 3,
          pinned: false,
        ),
    ],
    eventsTitle: text('overlay.sample.eventsTitle'),
    events: [
      for (var i = 0; i < 5; i++)
        OverlayVisorEditorEvent(
          text('overlay.sample.visorEvent${i + 1}Type'),
          text('overlay.sample.visorEvent${i + 1}Detail'),
          times[i],
          tones[i],
        ),
    ],
    chatTitle: text('overlay.sample.visorChatTitle'),
    chatSample: true,
    chat: [
      OverlayVisorEditorChatLine(name(1), text('overlay.sample.chat1')),
      OverlayVisorEditorChatLine(name(2), text('overlay.sample.chat2')),
    ],
  );
}
