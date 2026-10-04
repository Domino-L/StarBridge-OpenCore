import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';

/// Shared controls for the app settings and the menu's settings window.
class MenuToolbarEditor extends StatelessWidget {
  const MenuToolbarEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.showTitle = true,
  });
  final MenuToolbarPreferences value;
  final bool showTitle;
  final ValueChanged<MenuToolbarPreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) => AppStrings.of(context).text('menu.toolbar.$key');
    Widget choice(
      String key,
      String selected,
      List<String> choices,
      ValueChanged<String> changed,
    ) => DropdownButtonFormField<String>(
      key: ValueKey('menu-toolbar-$key-$selected'),
      initialValue: selected,
      decoration: InputDecoration(labelText: text(key)),
      items: [
        for (final option in choices)
          DropdownMenuItem(value: option, child: Text(text(option))),
      ],
      onChanged: (v) {
        if (v != null) changed(v);
      },
    );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Text(text('title'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          OverlaySettingsHelp(text('hint')),
          SwitchListTile(
            key: const ValueKey('menu-toolbar-unread'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('showUnreadBadges')),
            value: value.showUnreadBadges,
            onChanged: (v) => onChanged(value.copyWith(showUnreadBadges: v)),
          ),
          const SizedBox(height: 12),
          choice('density', value.density, const [
            'compact',
            'standard',
            'comfortable',
          ], (v) => onChanged(value.copyWith(density: v))),
          const SizedBox(height: 12),
          choice('labels', value.labels, const [
            'auto',
            'iconsOnly',
          ], (v) => onChanged(value.copyWith(labels: v))),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: value.order.length,
            onReorderItem: (from, to) {
              final order = [...value.order];
              final id = order.removeAt(from);
              order.insert(to, id);
              onChanged(value.copyWith(order: order));
            },
            itemBuilder: (context, index) {
              final id = value.order[index];
              final title = AppStrings.of(context).text('menu.tools.$id');
              return ListTile(
                key: ValueKey('menu-toolbar-item-$id'),
                contentPadding: EdgeInsets.zero,
                leading: id == 'hud'
                    ? Semantics(
                        label: text('alwaysVisible'),
                        toggled: true,
                        child: SizedBox(
                          width: 60,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: StarBridgeIcon(
                              StarBridgeIconSemantic.overlay,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    : Switch(
                        key: ValueKey('menu-toolbar-visible-$id'),
                        value: !value.hidden.contains(id),
                        onChanged: (visible) => onChanged(
                          value.copyWith(
                            hidden: visible
                                ? value.hidden
                                      .where((item) => item != id)
                                      .toList()
                                : [...value.hidden, id],
                          ),
                        ),
                      ),
                title: Text(title),
                subtitle: id == 'hud' ? Text(text('alwaysVisible')) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: text('earlier'),
                      icon: const RotatedBox(
                        quarterTurns: 2,
                        child: StarBridgeIcon(
                          StarBridgeIconSemantic.menuDown,
                          size: 18,
                        ),
                      ),
                      onPressed: index == 0
                          ? null
                          : () {
                              final order = [...value.order];
                              order[index] = order[index - 1];
                              order[index - 1] = id;
                              onChanged(value.copyWith(order: order));
                            },
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Tooltip(
                        message: text('move'),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: StarBridgeIcon(
                            StarBridgeIconSemantic.dragHandle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          TextButton(
            onPressed: () => onChanged(const MenuToolbarPreferences()),
            child: Text(text('reset')),
          ),
        ],
      ),
    );
  }
}
