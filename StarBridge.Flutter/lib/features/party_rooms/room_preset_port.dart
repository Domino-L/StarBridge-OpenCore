import 'room_chat_module.dart';

final class RoomPresetChoice {
  const RoomPresetChoice(this.id, this.name);
  final String id, name;
}

final class RoomPresetCatalog {
  const RoomPresetCatalog(this.revision, this.presets);
  final int revision;
  final List<RoomPresetChoice> presets;
}

/// Device-local packages, not appearance grants. Example adapters never use Host.
abstract interface class RoomPresetPort {
  bool get presetsAvailable;
  Future<RoomPresetCatalog> readPresets();
  Future<Map<String, Object?>> exportPreset(String id, int revision);
  Future<String> importPreset(String package, int revision);
  Future<RoomChatMessage> sendPreset(
    String roomId,
    String text,
    Map<String, Object?> attachment,
  );
}
