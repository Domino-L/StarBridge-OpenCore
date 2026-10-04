import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_invitations.dart';
import 'menu_feature_view.dart';

/// Display-only settings capability. The primary engine retains the room ID.
final class MenuRoomSettingsView {
  const MenuRoomSettingsView(this.action, this.tags, this.reply);
  final String? action;
  final List<RoomTag> tags;
  final Map<String, Object?>? reply;
  static MenuRoomSettingsView parse(Object? raw) {
    if (raw is! Map) throw const FormatException();
    final action = raw['action'],
        tags = raw['tagOptions'],
        reply = raw['reply'];
    if (action != null &&
        (action is! String ||
            !RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(action))) {
      throw const FormatException();
    }
    if (tags is! List || tags.length > 500) throw const FormatException();
    if (reply != null &&
        (reply is! Map ||
            reply['request'] is! String ||
            !RegExp(r'^q[1-9][0-9]{0,13}$').hasMatch(reply['request']) ||
            !const {
              'updated',
              'rejected',
              'unknown',
              'stale',
            }.contains(reply['status']) ||
            (reply['error'] != null &&
                (reply['error'] is! String ||
                    (reply['error'] as String).length > 128)))) {
      throw const FormatException();
    }
    return MenuRoomSettingsView(action as String?, [
      for (final tag in tags) _tag(tag),
    ], reply == null ? null : Map<String, Object?>.from(reply));
  }

  static RoomTag _tag(Object? raw) {
    if (raw is! Map ||
        raw['id'] is! String ||
        (raw['id'] as String).length > 128 ||
        raw['text'] is! String ||
        (raw['text'] as String).length > 512 ||
        raw['isGameplay'] is! bool) {
      throw const FormatException();
    }
    return RoomTag(
      id: raw['id'],
      text: raw['text'],
      isGameplay: raw['isGameplay'],
    );
  }
}

/// Reuses the client controller/editor, but never starts a second network lane.
class MenuRoomSettingsHost extends StatefulWidget {
  const MenuRoomSettingsHost({
    super.key,
    required this.view,
    required this.dispatch,
    required this.builder,
  });
  final MenuFeatureView view;
  final void Function(String, String) dispatch;
  final Widget Function(BuildContext, PartyRoomsModule) builder;
  @override
  State<MenuRoomSettingsHost> createState() => _SettingsState();
}

class _SettingsState extends State<MenuRoomSettingsHost> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _port = MenuRoomSettingsPort(
    widget.view,
    (key, value) => widget.dispatch(key, value),
  );
  late final _module = PartyRoomsModule(_port);
  @override
  void initState() {
    super.initState();
    unawaited(_module.refresh());
  }

  @override
  void didUpdateWidget(MenuRoomSettingsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lost =
        ((oldWidget.view.room?.settings?.action != null &&
                widget.view.room?.settings?.action == null) ||
            (oldWidget.view.room?.management?.actions.containsKey(
                      'inviteDecline',
                    ) ==
                    true &&
                widget.view.room?.management?.actions.containsKey(
                      'inviteDecline',
                    ) !=
                    true)) &&
        !widget.view.busy;
    _port.update(widget.view);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (lost) _navigator.currentState?.popUntil((route) => route.isFirst);
      if (!widget.view.busy && !_port.pending && !_module.writing) {
        unawaited(_module.refresh());
      }
    });
  }

  @override
  void dispose() {
    _module.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigator,
    pages: [
      MaterialPage<void>(
        child: ListenableBuilder(
          listenable: _module,
          builder: (context, _) => widget.builder(context, _module),
        ),
      ),
    ],
    onDidRemovePage: (_) {},
  );
}

class MenuRoomSettingsPort
    implements
        PartyRoomsPort,
        RoomCommandsPort,
        RoomManagementPort,
        RoomInvitationsPort {
  MenuRoomSettingsPort(this.view, this.dispatch);
  MenuFeatureView view;
  final void Function(String, String) dispatch;
  final _invalidations = StreamController<void>.broadcast(sync: true);
  Completer<RoomCommandResult>? _pending;
  String? _request, _action;
  int _serial = Random.secure().nextInt(1 << 32) * 1000;
  bool _closed = false;
  bool get pending => _pending != null;
  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  bool get supportsCommands =>
      !_closed &&
      (view.room?.settings?.action != null ||
          (view.room?.management?.actions.isNotEmpty ?? false));
  @override
  bool get supportsManagement =>
      !_closed && view.room?.settings?.action != null;
  @override
  bool get supportsInvitations =>
      !_closed &&
      view.room?.management?.actions.containsKey('inviteDecline') == true;
  @override
  Future<RoomReadResult> read() async {
    final room = view.room;
    if (_closed || room == null) {
      return const RoomReadResult(RoomReadState.unavailable);
    }
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        currentRoomId: view.scope,
        serverTime: room.serverTime ?? DateTime.now().toUtc(),
        rooms: [
          room.presentation(view.title, view.scope, manage: supportsManagement),
        ],
        tagOptions: room.settings?.tags ?? const [],
        receivedInvitations: [
          for (final item in room.management?.received ?? <RoomInvitation>[])
            RoomInvitation(
              id: item.id,
              roomId: item.roomId == room.management?.currentRoomAlias
                  ? view.scope
                  : item.roomId,
              title: item.title,
              inviter: item.inviter,
              recipient: item.recipient,
              expiresAt: item.expiresAt,
            ),
        ],
        sentInvitations: [
          for (final item in room.management?.sent ?? <RoomInvitation>[])
            RoomInvitation(
              id: item.id,
              roomId: view.scope,
              title: item.title,
              inviter: item.inviter,
              recipient: item.recipient,
              expiresAt: item.expiresAt,
            ),
        ],
      ),
    );
  }

  void update(MenuFeatureView next) {
    final changed = next.scope != view.scope;
    view = next;
    if (changed) {
      _complete(const RoomCommandResult('stale', error: 'contextChanged'));
      _invalidations.add(null);
      return;
    }
    if (_pending == null) return;
    if (next.rejectedAction == _action) {
      _complete(const RoomCommandResult('rejected', error: 'refreshRequired'));
      return;
    }
    final reply = next.room?.settings?.reply;
    final management = next.room?.management;
    if (management?.request == _request && management?.reply != null) {
      _complete(management!.reply!);
      return;
    }
    if (reply?['request'] == _request) {
      _complete(
        RoomCommandResult(
          reply!['status'] as String,
          error: reply['error'] as String?,
        ),
      );
    }
  }

  void _complete(RoomCommandResult result) {
    if (_pending?.isCompleted == false) _pending!.complete(result);
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    final action = command.operation == RoomOperation.update
        ? view.room?.settings?.action
        : view.room?.management?.actions[command.operation.name];
    if (!supportsCommands ||
        _pending != null ||
        action == null ||
        (command.operation != RoomOperation.inviteDecline &&
            command.data['roomId'] != view.scope)) {
      return const RoomCommandResult('rejected', error: 'unavailable');
    }
    final data = {...command.data}..remove('roomId');
    final request = 'q${++_serial}';
    final value = jsonEncode({'request': request, 'data': data});
    if (value.length > 2048) {
      return const RoomCommandResult('rejected', error: 'invalidInput');
    }
    final pending = _pending = Completer<RoomCommandResult>();
    _request = request;
    _action = action;
    dispatch(action, value);
    try {
      return await pending.future.timeout(
        const Duration(seconds: 17),
        onTimeout: () =>
            const RoomCommandResult('unknown', error: 'outcomeUnknown'),
      );
    } finally {
      _pending = null;
      _request = _action = null;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _complete(const RoomCommandResult('stale', error: 'contextChanged'));
    await _invalidations.close();
  }
}
