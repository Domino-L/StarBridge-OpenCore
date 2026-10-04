import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/color_choice_icon.dart';
import 'overlay_workspace_layout_editor.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_schema.dart';
import 'overlay_workspace_value_format.dart';

/// Inspection only: no runtime, network reads, preference writes or draft mutation.
class OverlayPresetImportPreview extends StatelessWidget {
  const OverlayPresetImportPreview({
    required this.name,
    required this.settings,
    required this.layout,
    required this.currentSettings,
    this.sources,
    this.removedOrganizationBindings = false,
    super.key,
  });

  final String name;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayWorkspaceSettings? currentSettings;
  final OverlayPresetSources? sources;
  final bool removedOrganizationBindings;

  static const _modules = {
    'notice': 'showNotice',
    'fleetOverview': 'showSquads',
    'members': 'showMembers',
    'chat': 'showChat',
    'events': 'showEventNotifications',
    'crosshair': 'showCrosshair',
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String copy(String key) => strings.text('overlay.importPreview.$key');
    final fields = overlayWorkspaceFieldSpecs
        .where((field) => field.userVisible && field.field != 'scenePreference')
        .toList();
    final changes = currentSettings == null
        ? null
        : fields
              .where(
                (field) =>
                    jsonEncode(settings[field.field]) !=
                    jsonEncode(currentSettings![field.field]),
              )
              .length;
    final scheme = Theme.of(context).colorScheme;
    final safeSources =
        (sources ??
                OverlayPresetSources.fromLegacy(settings['scenePreference']))
            .forTransfer();
    String sourceName(OverlaySourceBinding value, {bool module = false}) =>
        switch (value.mode) {
          OverlaySourceMode.none =>
            module
                ? strings.text('overlay.source.followPreset')
                : copy('follow'),
          OverlaySourceMode.auto => strings.text('overlay.source.auto'),
          OverlaySourceMode.room => copy('room'),
          OverlaySourceMode.community => throw StateError(
            'Unsanitized transfer source.',
          ),
        };
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(copy('title')),
      content: SizedBox(
        width: 820,
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.only(end: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(copy('consequence')),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: SizedBox(
                  height: 230,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: FocusScope(
                        canRequestFocus: false,
                        child: IgnorePointer(
                          child: OverlayWorkspaceLayoutWorkbench(
                            layout: layout,
                            settings: settings,
                            sources: sources,
                            canvasOnly: true,
                            showHiddenModules: false,
                            onChanged: (_, _) {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                copy('sample'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final module in _modules.entries)
                    Chip(
                      avatar: ColorChoiceIcon.selection(
                        selected: settings[module.value] == true,
                      ),
                      label: Text(
                        '${strings.text('overlay.workspace.group.${module.key}')} · ${copy(settings[module.value] == true ? 'on' : 'off')}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              row(
                strings.text('overlay.workspace.field.requestedSkin'),
                strings.text(
                  'overlay.workspace.option.${settings['requestedSkin']}',
                ),
              ),
              Text(
                copy('appearanceHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              row(copy('source'), sourceName(safeSources.binding)),
              if (sources != null) ...[
                for (final module in OverlaySourceModule.values)
                  row(
                    strings.text(
                      'overlay.workspace.group.${module == OverlaySourceModule.overview ? 'fleetOverview' : module.name}',
                    ),
                    module == OverlaySourceModule.chat &&
                            safeSources.chatSources.isNotEmpty
                        ? safeSources.chatSources
                              .map((source) => sourceName(source, module: true))
                              .join(' · ')
                        : sourceName(
                            safeSources.forModule(module),
                            module: true,
                          ),
                  ),
              ],
              if (removedOrganizationBindings ||
                  (sources?.hasOrganizationBindings ?? false))
                Text(
                  copy('removedBindings'),
                  key: const Key('overlay-import-removed-bindings'),
                ),
              row(copy('autoSwitch'), copy('off')),
              if (sources?.chatSources.isNotEmpty == true &&
                  sources!.chatSources.every(
                    (source) => source.mode == OverlaySourceMode.community,
                  ))
                Text(strings.text('overlay.source.chatTransferFallback')),
              Text(
                copy('privacy'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (changes != null) row(copy('changes'), changes.toString()),
              const Divider(height: 24),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(copy('details')),
                children: [
                  for (final field in fields)
                    row(
                      strings.text('overlay.workspace.field.${field.field}'),
                      _value(context, field),
                    ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(copy('geometry')),
                children: [
                  for (final item in layout)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          strings.text('overlay.workspace.module.${item.key}'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        row(
                          copy('position'),
                          '${_percent(item.x)} / ${_percent(item.y)}',
                        ),
                        row(
                          copy('size'),
                          '${_percent(item.width)} × ${_percent(item.height)}',
                        ),
                        row(
                          strings.text(
                            'overlay.workspace.layout.lockPositionSize',
                          ),
                          copy(item.isLocked ? 'on' : 'off'),
                        ),
                        row(
                          strings.text('overlay.workspace.layout.textOpacity'),
                          _percent(item.textOpacity),
                        ),
                        row(
                          strings.text(
                            'overlay.workspace.layout.backgroundOpacity',
                          ),
                          _percent(item.backgroundOpacity),
                        ),
                        row(
                          strings.text(
                            'overlay.workspace.layout.decorationOpacity',
                          ),
                          _percent(item.decorationOpacity),
                        ),
                        const Divider(),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.text('overlay.workspace.cancel')),
        ),
        FilledButton(
          key: const Key('overlay-import-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(copy('confirm')),
        ),
      ],
    );
  }

  String _value(BuildContext context, OverlayWorkspaceFieldSpec field) {
    final strings = AppStrings.of(context);
    final value = settings[field.field];
    if (value is bool) {
      return strings.text('overlay.importPreview.${value ? 'on' : 'off'}');
    }
    if (field.kind == OverlayWorkspaceFieldKind.choice ||
        field.kind == OverlayWorkspaceFieldKind.readOnlyChoice) {
      return strings.text('overlay.workspace.option.$value');
    }
    if (field.kind == OverlayWorkspaceFieldKind.eventTypes && value is int) {
      final count = value
          .toRadixString(2)
          .split('')
          .where((bit) => bit == '1')
          .length;
      return strings
          .text('overlay.importPreview.eventCount')
          .replaceAll('{count}', '$count');
    }
    if (field.kind == OverlayWorkspaceFieldKind.eventDurations &&
        value is Map) {
      return strings
          .text('overlay.importPreview.durationCount')
          .replaceAll(
            '{count}',
            '${value.values.where((v) => v is num && v > 0).length}',
          );
    }
    if (value is num) {
      return overlayWorkspaceFormatValue(field, value, strings);
    }
    return '$value';
  }

  static String _percent(num value) => '${_number(value * 100)}%';
  static String _number(num value) =>
      value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
