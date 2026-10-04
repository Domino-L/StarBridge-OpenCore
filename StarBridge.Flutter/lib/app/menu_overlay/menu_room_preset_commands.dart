import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_chat_module.dart';
import '../../features/party_rooms/room_preset_port.dart';
import 'menu_feature_session.dart';
import 'menu_room_management_session.dart';

// Owned solely by the primary engine. Never serialize this state wholesale.
final class _RoomPresetDraft {
  RoomPresetCatalog? catalog;
  Map<String, Object?>? attachment;
  String? name, error;
  int revision = 0;
  void clear() {
    catalog = null;
    attachment = null;
    name = error = null;
    revision++;
  }
}

final class MenuRoomPresetCommands {
  MenuRoomPresetCommands(this._session, this.port, this._state);
  final MenuFeatureSession _session;
  final PartyRoomsPort port;
  final MenuRoomCommandState _state;
  final _roomPreset = _RoomPresetDraft();
  Map<String, Object?>? get attachment => _roomPreset.attachment;
  void clear() => _roomPreset.clear();
  void sent() {
    _roomPreset.attachment = null;
    _roomPreset.name = null;
    _roomPreset.revision++;
  }

  RoomPresetPort? get presetPort {
    final source = port;
    if (source is! RoomChatProvider) return null;
    final chat = (source as RoomChatProvider).roomChat;
    return chat.available &&
            chat is RoomPresetPort &&
            (chat as RoomPresetPort).presetsAvailable
        ? chat as RoomPresetPort
        : null;
  }

  Future<bool> checkAuthority(String roomId, int account, int epoch) async {
    final snapshot = await port.read();
    if (!_session.currentAccount(account) ||
        !_session.current(epoch) ||
        _state.selected != roomId) {
      return false;
    }
    if (snapshot.state != RoomReadState.ready ||
        snapshot.directory?.currentRoomId != roomId ||
        snapshot.directory?.rooms.any((room) => room.id == roomId) != true ||
        presetPort == null) {
      _roomPreset.clear();
      return false;
    }
    return true;
  }

  Map<String, Object?>? projection(String roomId) {
    if (presetPort == null) {
      _roomPreset.clear();
      return null;
    }
    final revision = _roomPreset.revision;
    bool valid() =>
        _state.selected == roomId && _roomPreset.revision == revision;
    return {
      'revision': _roomPreset.revision,
      'loaded': _roomPreset.catalog != null,
      'error': _roomPreset.error,
      'draftName': _roomPreset.name,
      'open': !_state.uncertain
          ? _session.button('分享浮层预设', (_) async {
              if (valid()) await _loadRoomPresets(roomId);
            })['key']
          : null,
      'clear': !_state.uncertain && _roomPreset.attachment != null
          ? _session.button('移除附件', (_) async {
              if (!valid() || _state.uncertain) return;
              _roomPreset.attachment = null;
              _roomPreset.name = null;
              _roomPreset.revision++;
            })['key']
          : null,
      'choices': [
        if (!_state.uncertain)
          if (_roomPreset.catalog case final catalog?)
            for (final choice in catalog.presets)
              {
                'name': choice.name,
                'action': _session.button(choice.name, (_) async {
                  if (valid()) {
                    await _prepareRoomPreset(roomId, catalog, choice);
                  }
                })['key'],
              },
      ],
    };
  }

  Future<void> _loadRoomPresets(String roomId) async {
    final account = _session.accountEpoch, epoch = _session.generation;
    try {
      if (_state.uncertain || !await checkAuthority(roomId, account, epoch)) {
        return;
      }
      final catalog = await presetPort!.readPresets();
      if (!_session.currentAccount(account) ||
          !_session.current(epoch) ||
          _state.selected != roomId) {
        return;
      }
      _roomPreset.catalog = catalog;
      _roomPreset.error = null;
    } on Object {
      if (_session.currentAccount(account) && _session.current(epoch)) {
        _roomPreset.catalog = null;
        _roomPreset.error = 'unavailable';
      }
    }
  }

  Future<void> _prepareRoomPreset(
    String roomId,
    RoomPresetCatalog catalog,
    RoomPresetChoice choice,
  ) async {
    final account = _session.accountEpoch, epoch = _session.generation;
    try {
      if (_state.uncertain ||
          !identical(catalog, _roomPreset.catalog) ||
          !await checkAuthority(roomId, account, epoch)) {
        return;
      }
      final attachment = await presetPort!.exportPreset(
        choice.id,
        catalog.revision,
      );
      if (!_session.currentAccount(account) ||
          !_session.current(epoch) ||
          _state.selected != roomId) {
        return;
      }
      _roomPreset.attachment = Map.unmodifiable(attachment);
      _roomPreset.name = choice.name;
      _roomPreset.error = null;
      _roomPreset.revision++;
    } on Object {
      if (_session.currentAccount(account) && _session.current(epoch)) {
        _roomPreset.error = 'unavailable';
      }
    }
  }
}
