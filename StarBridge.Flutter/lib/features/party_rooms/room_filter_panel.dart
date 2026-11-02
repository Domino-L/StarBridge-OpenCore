import '../../app/localization/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import 'room_tag_catalog.dart';
import 'room_tag_colors.dart';
import 'room_tag_picker.dart';

class RoomFilterPanel extends StatelessWidget {
  const RoomFilterPanel({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<RoomTag> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final catalog = RoomTagCatalog(options);
    final tokens = context.tokens;
    Widget choice(String id, String label) => StarBridgeCheckboxTile(
      controlKey: ValueKey('room-filter-$id'),
      label: label,
      activeColor: roomTagColors(context, id).foreground,
      value: selected.contains(id),
      onChanged: (value) => onChanged(
        value == true
            ? catalog.adding(selected, id)
            : (Set<String>.of(selected)..remove(id)),
      ),
      rowBuilder: (control) =>
          ListTile(dense: true, leading: control, title: Text(label)),
    );
    Widget disclosure(String key, String title, List<Widget> children) =>
        Padding(
          // Match the native ExpansionTile's transparent one-pixel borders.
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: StarBridgeExpansionTile(
            key: PageStorageKey(key),
            title: title,
            useNativePageStorage: true,
            headerMinHeight: 0,
            headerBuilder: (context, visual, open) {
              final theme = Theme.of(context);
              final data = InteractionScope.of(context);
              final expansion = ExpansionTileTheme.of(context);
              final progress = SuiteMotion.curve.transform(open);
              return ListTileTheme.merge(
                textColor: Color.lerp(
                  expansion.collapsedTextColor ??
                      (theme.useMaterial3
                          ? theme.colorScheme.onSurface
                          : theme.textTheme.titleMedium?.color),
                  expansion.textColor ??
                      (theme.useMaterial3
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.primary),
                  progress,
                ),
                iconColor: Color.lerp(
                  expansion.collapsedIconColor ??
                      (theme.useMaterial3
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.unselectedWidgetColor),
                  expansion.iconColor ?? theme.colorScheme.primary,
                  progress,
                ),
                child: ListTile(
                  key: ValueKey((
                    data.animates ? null : theme,
                    open <= 0
                        ? 0
                        : open >= 1
                        ? 1
                        : 2,
                  )),
                  mouseCursor: MouseCursor.defer,
                  contentPadding: expansion.tilePadding,
                  title: Text(title),
                  trailing: Transform.rotate(
                    angle: math.pi * progress,
                    child: const StandardIcon(StandardIconSemantic.expandMore),
                  ),
                ),
              );
            },
            children: children,
          ),
        );
    Widget branch(String id) {
      final children = catalog.children(id);
      if (children.isEmpty) {
        return choice(id, catalog.label(id, strings: AppStrings.of(context)));
      }
      return disclosure(
        'room-filter-branch-$id',
        catalog.label(id, strings: AppStrings.of(context)),
        [
          if (catalog.options.containsKey(id))
            choice(id, tagCopy(context, 'add')),
          for (final child in children) branch(child),
        ],
      );
    }

    return Material(
      color: tokens.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(tokens.space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tagCopy(context, 'filter'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                StarBridgeActionButton(
                  controlKey: const Key('room-filter-clear'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: selected.isEmpty ? null : (_) => onChanged({}),
                  child: Text(tagCopy(context, 'clear')),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: const PageStorageKey('room-filter-scroll'),
              children: [
                for (final id in catalog.children(null)) branch(id),
                for (final group in ['pace', 'experience', 'need', 'other'])
                  if (options.any(
                    (tag) =>
                        !tag.isGameplay &&
                        RoomTagCatalog.group(tag.id) == group,
                  ))
                    disclosure(
                      'room-filter-context-$group',
                      tagCopy(context, group),
                      [
                        for (final tag in options)
                          if (!tag.isGameplay &&
                              RoomTagCatalog.group(tag.id) == group)
                            choice(
                              tag.id,
                              RoomTagCatalog.fullText(
                                tag,
                                strings: AppStrings.of(context),
                              ),
                            ),
                      ],
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
