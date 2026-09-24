import 'package:flutter/material.dart';

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
    Widget choice(String id, String label) => CheckboxListTile(
      key: ValueKey('room-filter-$id'),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: roomTagColors(context, id).foreground,
      title: Text(label),
      value: selected.contains(id),
      onChanged: (value) => onChanged(
        value == true
            ? catalog.adding(selected, id)
            : (Set<String>.of(selected)..remove(id)),
      ),
    );
    Widget branch(String id) {
      final children = catalog.children(id);
      if (children.isEmpty) return choice(id, catalog.label(id));
      return ExpansionTile(
        key: PageStorageKey('room-filter-branch-$id'),
        title: Text(catalog.label(id)),
        children: [
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
                TextButton(
                  onPressed: selected.isEmpty ? null : () => onChanged({}),
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
                    ExpansionTile(
                      key: PageStorageKey('room-filter-context-$group'),
                      title: Text(tagCopy(context, group)),
                      children: [
                        for (final tag in options)
                          if (!tag.isGameplay &&
                              RoomTagCatalog.group(tag.id) == group)
                            choice(tag.id, tag.text),
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
