import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/party_rooms_page.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_invitations.dart';
import 'menu_room_lobby_view.dart';

/// Reuses the client page/controller/dialogs; this port carries display data and
/// opaque actions only. It has no Host session, service target or credentials.
class MenuRoomLobbyPanel extends StatefulWidget {
  const MenuRoomLobbyPanel({
    super.key,
    required this.view,
    required this.onAction,
  });
  final MenuRoomLobbyView view;
  final void Function(String, String) onAction;
  @override
  State<MenuRoomLobbyPanel> createState() => _LobbyState();
}

class _LobbyState extends State<MenuRoomLobbyPanel> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _port = MenuRoomLobbyPort(
    widget.view,
    (key, value) => widget.onAction(key, value),
  );
  late final _module = PartyRoomsModule(
    _port,
    refreshInterval: const Duration(days: 1),
  );
  @override
  void didUpdateWidget(MenuRoomLobbyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _port.update(widget.view);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (oldWidget.view.actions.containsKey(RoomOperation.invitePreview) &&
          !widget.view.actions.containsKey(RoomOperation.invitePreview) &&
          !widget.view.busy) {
        _navigator.currentState?.popUntil((route) => route.isFirst);
      }
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
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (_) => PartyRoomsPage(
        module: _module,
        onRefresh: () => widget.onAction('refresh', ''),
      ),
    ),
  );
}

class MenuRoomLobbyPort
    implements PartyRoomsPort, RoomCommandsPort, RoomInvitationsPort {
  MenuRoomLobbyPort(this.view, this.dispatch);
  MenuRoomLobbyView view;
  final void Function(String, String) dispatch;
  Completer<RoomCommandResult>? _pending;
  String? _request, _action;
  bool _preview = false;
  bool get pending => _pending != null;
  // Correlation belongs to this window, never a process-global business lane.
  int _serial = Random.secure().nextInt(1 << 32) * 1000;
  bool _closed = false;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get supportsCommands => !_closed && view.actions.isNotEmpty;
  @override
  bool get supportsInvitations =>
      !_closed && view.actions.containsKey(RoomOperation.invitePreview);
  @override
  Future<RoomReadResult> read() async => RoomReadResult(
    _closed ? RoomReadState.unavailable : RoomReadState.ready,
    directory: _closed ? null : view.directory,
  );
  void update(MenuRoomLobbyView next) {
    view = next;
    if (_pending?.isCompleted == false && next.rejectedAction == _action) {
      _pending!.complete(
        const RoomCommandResult('rejected', error: 'refreshRequired'),
      );
      return;
    }
    final reply = next.invitationReply?['request'] == _request
        ? next.invitationReply
        : next.reply;
    // Wait for renewed grants after a successful read-only preview, so the
    // client's next preview in its sequential list can use a live action.
    if ((_preview || next.invitationReply?['request'] == _request) && next.busy) {
      return;
    }
    if (_pending == null ||
        _pending!.isCompleted ||
        reply?['request'] != _request) {
      return;
    }
    try {
      final preview = reply!['preview'];
      _pending!.complete(
        RoomCommandResult(
          reply['status'] as String,
          error: reply['error'] as String?,
          directory:
              next.invitationReply?['request'] == _request &&
                  reply['status'] == 'declined'
              ? next.directory
              : null,
          preview: preview == null
              ? null
              : MenuRoomLobbyView.readDirectory(preview).rooms.single,
        ),
      );
    } on Object {
      _pending!.complete(
        RoomCommandResult(
          _preview ? 'rejected' : 'unknown',
          error: _preview ? 'unavailable' : 'outcomeUnknown',
        ),
      );
    }
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    final key = view.actions[command.operation];
    if (_closed || _pending != null || key == null) {
      return const RoomCommandResult('rejected', error: 'unavailable');
    }
    final pending = _pending = Completer<RoomCommandResult>();
    _action = key;
    _preview = command.operation == RoomOperation.invitePreview;
    final request = _request = 'q${++_serial}';
    final value = jsonEncode({'request': request, 'data': command.data});
    if (value.length > 2048) {
      _pending = null;
      return const RoomCommandResult('rejected', error: 'invalidInput');
    }
    dispatch(key, value);
    try {
      return await pending.future.timeout(
        const Duration(seconds: 17),
        onTimeout: () => RoomCommandResult(
          _preview ? 'rejected' : 'unknown',
          error: _preview ? 'unavailable' : 'outcomeUnknown',
        ),
      );
    } finally {
      if (_request == request) {
        _pending = null;
        _request = null;
        _action = null;
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (_pending?.isCompleted == false) {
      _pending!.complete(
        const RoomCommandResult('stale', error: 'contextChanged'),
      );
    }
  }
}
