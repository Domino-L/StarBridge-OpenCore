import 'community_chat_port.dart';

final class CommunityPresetChoice {
  const CommunityPresetChoice(this.id, this.name);
  final String id, name;
}

final class CommunityPresetCatalog {
  CommunityPresetCatalog.parse(Map<String, Object?> row) {
    final version = row['revision'];
    final values = row['presets'];
    if (row['schemaVersion'] != 1 ||
        version is! int ||
        version < 0 ||
        values is! List ||
        values.length > 1024) {
      throw const FormatException();
    }
    revision = version;
    final seen = <String>{};
    presets = List.unmodifiable(
      values.map((value) {
        if (value is! Map) throw const FormatException();
        final id = presetText(value['id'], 128),
            name = presetText(value['name'], 64);
        if (!seen.add(id)) throw const FormatException();
        return CommunityPresetChoice(id, name);
      }),
    );
  }
  late final int revision;
  late final List<CommunityPresetChoice> presets;
}

String presetText(Object? value, int limit) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > limit ||
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}

/// Device-local, additive preset operations. No room capability or skin grants.
abstract interface class CommunityPresetPort {
  Stream<void> get invalidations;
  bool get communityPresetsAvailable;
  Future<CommunityPresetCatalog> readCommunityPresets();
  Future<Map<String, Object?>> exportCommunityPreset(String id, int revision);
  Future<String> importCommunityPreset(
    Map<String, Object?> attachment,
    int revision,
  );
}

Map<String, Object?> checkedCommunityPreset(Map<String, Object?> attachment) =>
    CommunityChatDetail.parse({'attachment': attachment}).attachment!;
