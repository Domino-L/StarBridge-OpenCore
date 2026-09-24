import 'communities_module.dart';

abstract interface class CommunityCreationPort {
  Future<CommunityCreationOptions> creationOptions();
  Future<CommunityCreationOutcome> createCommunity(
    String requestId,
    Map<String, Object?> draft,
  );
}

final class CommunityCreationOutcome {
  const CommunityCreationOutcome(this.status, {this.error, this.organization});
  final String status;
  final String? error;
  final CommunityCard? organization;
}

final class CommunityCreationOptions {
  const CommunityCreationOptions({
    required this.categories,
    required this.tags,
    required this.timeZones,
    required this.defaultTimeZoneId,
    required this.defaultActiveFrom,
    required this.defaultActiveTo,
    required this.defaultSystem,
    required this.maxTags,
  });
  final List<CommunityTagCategory> categories;
  final List<CommunityTagOption> tags;
  final List<CommunityTimeZone> timeZones;
  final String defaultTimeZoneId,
      defaultActiveFrom,
      defaultActiveTo,
      defaultSystem;
  final int maxTags;

  factory CommunityCreationOptions.parse(Map<String, Object?> payload) {
    String text(Map<String, Object?> value, String key, int max) {
      final raw = value[key];
      if (raw is! String || raw.isEmpty || raw.length > max) {
        throw const FormatException('Invalid creation option');
      }
      return raw;
    }

    List<Map<String, Object?>> rows(String key, int max) {
      final raw = payload[key];
      if (raw is! List || raw.isEmpty || raw.length > max) {
        throw const FormatException('Invalid creation options');
      }
      return raw.map((row) => Map<String, Object?>.from(row as Map)).toList();
    }

    if (payload['schemaVersion'] != 1 || payload['maxTags'] != 5) {
      throw const FormatException('Unsupported creation options');
    }
    final categories = rows('categories', 32)
        .map(
          (r) => CommunityTagCategory(
            text(r, 'id', 64),
            text(r, 'name', 128),
            text(r, 'accentHex', 9),
            text(r, 'description', 512),
          ),
        )
        .toList();
    final tags = rows('tags', 512)
        .map(
          (r) => CommunityTagOption(
            text(r, 'id', 64),
            text(r, 'name', 128),
            text(r, 'categoryId', 64),
            text(r, 'description', 512),
          ),
        )
        .toList();
    final zones = rows('timeZones', 1024)
        .map((r) => CommunityTimeZone(text(r, 'id', 128), text(r, 'name', 512)))
        .toList();
    final defaultZone = text(payload, 'defaultTimeZoneId', 128);
    final from = text(payload, 'defaultActiveFrom', 5);
    final to = text(payload, 'defaultActiveTo', 5);
    final system = text(payload, 'defaultSystem', 16);
    final clock = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
    if (categories.map((c) => c.id).toSet().length != categories.length ||
        tags.map((t) => t.id).toSet().length != tags.length ||
        zones.map((z) => z.id).toSet().length != zones.length ||
        tags.any((t) => !categories.any((c) => c.id == t.categoryId)) ||
        !zones.any((z) => z.id == defaultZone) ||
        categories.any(
          (c) => !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(c.accentHex),
        ) ||
        !clock.hasMatch(from) ||
        !clock.hasMatch(to) ||
        !const {'stanton', 'pyro', 'nyx'}.contains(system)) {
      throw const FormatException('Inconsistent creation options');
    }
    return CommunityCreationOptions(
      categories: List.unmodifiable(categories),
      tags: List.unmodifiable(tags),
      timeZones: List.unmodifiable(zones),
      defaultTimeZoneId: defaultZone,
      defaultActiveFrom: from,
      defaultActiveTo: to,
      defaultSystem: system,
      maxTags: 5,
    );
  }
}

final class CommunityTagCategory {
  const CommunityTagCategory(
    this.id,
    this.name,
    this.accentHex,
    this.description,
  );
  final String id, name, accentHex, description;
}

final class CommunityTagOption {
  const CommunityTagOption(
    this.id,
    this.name,
    this.categoryId,
    this.description,
  );
  final String id, name, categoryId, description;
}

final class CommunityTimeZone {
  const CommunityTimeZone(this.id, this.name);
  final String id, name;
}
