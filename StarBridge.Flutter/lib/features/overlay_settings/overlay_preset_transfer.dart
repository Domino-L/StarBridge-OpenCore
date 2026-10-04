import 'dart:convert';

import 'overlay_workspace_models.dart';

/// Clipboard package, distinct from the WPF CSV chat package. The sanitized
/// result is also the exact read-only preview used before any import write.
final class OverlayPresetTransfer {
  OverlayPresetTransfer({
    required this.name,
    required this.settings,
    required List<OverlayWorkspaceLayoutItem> layout,
    OverlayPresetSources? sources,
    bool removedOrganizationBindings = false,
  }) : layout = List.unmodifiable(layout),
       sources = sources?.forTransfer(),
       removedOrganizationBindings =
           removedOrganizationBindings ||
           (sources?.hasOrganizationBindings ?? false);

  final String name;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayPresetSources? sources;
  final bool removedOrganizationBindings;

  String serialize() => jsonEncode({
    'schemaVersion': sources == null ? 1 : 2,
    'name': name,
    'settings': settings.toMap(),
    'layout': layout.map((item) => item.toMap()).toList(),
    if (sources != null) ...{
      'sources': sources!.toMap(),
      'removedOrganizationBindings': removedOrganizationBindings,
    },
  });

  factory OverlayPresetTransfer.parse(String payload) {
    if (payload.length > 131072) throw const FormatException();
    final document = jsonDecode(payload);
    if (document is! Map) throw const FormatException();
    final data = stringMap(document);
    final version = data['schemaVersion'];
    final keys = {
      'schemaVersion',
      'name',
      'settings',
      'layout',
      if (version == 2) ...['sources', 'removedOrganizationBindings'],
    };
    if ((version != 1 && version != 2) ||
        data.length != keys.length ||
        data.keys.any((key) => !keys.contains(key))) {
      throw const FormatException();
    }
    final settings = OverlayWorkspaceSettings.fromMap(
      stringMap(data['settings']),
    );
    final layout = objectList(data['layout'])
        .map((item) => OverlayWorkspaceLayoutItem.fromMap(stringMap(item)))
        .toList(growable: false);
    final name = data['name'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.trim().length > 24 ||
        name.contains(RegExp(r'[\x00-\x1F\x7F-\x9F]'))) {
      throw const FormatException();
    }
    const moduleKeys = {'Notice', 'Squads', 'Members', 'Chat'};
    if (layout.length != moduleKeys.length ||
        layout.map((item) => item.key).toSet().length != moduleKeys.length ||
        layout.any((item) => !moduleKeys.contains(item.key))) {
      throw const FormatException();
    }
    if (version == 2 && data['removedOrganizationBindings'] is! bool) {
      throw const FormatException();
    }
    return OverlayPresetTransfer(
      name: name.trim(),
      settings: settings,
      layout: layout,
      sources: version == 2
          ? OverlayPresetSources.fromMap(stringMap(data['sources']))
          : null,
      removedOrganizationBindings: data['removedOrganizationBindings'] == true,
    );
  }
}
