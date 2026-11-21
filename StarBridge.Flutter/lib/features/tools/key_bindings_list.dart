import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'key_bindings_index.dart';
import 'key_bindings_labels.dart';
import 'key_bindings_port.dart';
import 'key_bindings_split.dart' show KeyBindingsMeasured;

/// Below the keyboard: how to read it and which files were read, then the
/// searchable list that follows the device and situation on screen.
final class KeyBindingsLower extends StatelessWidget {
  const KeyBindingsLower({
    required this.index,
    required this.snapshot,
    required this.query,
    required this.scene,
    required this.device,
    required this.onlyChanged,
    required this.blocked,
    required this.search,
    required this.onSearch,
    required this.onOnlyChanged,
    required this.onOpen,
    required this.width,
    required this.listHeight,
    required this.helpOpen,
    required this.onHelp,
    this.mouse,
    this.instance,
    this.chrome = 56,
    this.onToolbarHeight,
    super.key,
  });

  /// The bar above the rows with the gap under it: the notes beside the list are as
  /// tall as the bar and the rows together.
  final double chrome;

  /// The bar's measured height, for the page to share the window by (review
  /// CX-KEYBIND-SPLIT-073-R1 P2).
  final ValueChanged<double>? onToolbarHeight;

  /// Keyboard view lists keys only, mouse view mouse inputs only; null: either.
  final bool? mouse;

  /// Which stick, like the drawing; null for other devices.
  final int? instance;
  final KeyBindingsIndex? index;
  final KeyBindingsSnapshot? snapshot;
  final String query, scene;

  /// The Host's device name: 'keyboardMouse', 'gamepad' or 'joystick'.
  final String device;
  final bool onlyChanged, blocked;
  final TextEditingController search;
  final VoidCallback onSearch;
  final ValueChanged<bool> onOnlyChanged;
  final ValueChanged<KeyBindingRef> onOpen;
  final double width;

  /// The list's height; null folds it away and leaves the search line.
  final double? listHeight;
  final bool helpOpen;
  final VoidCallback onHelp;

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.$key');
    final tokens = context.tokens;
    final secondary = TextStyle(color: tokens.colors.textSecondary);
    final help = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('help.title'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (final key in const [
          'help.open',
          'help.layer',
          'help.list',
          'help.layout',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(t(key), style: secondary.copyWith(fontSize: 13)),
          ),
        if (snapshot?.path case final path?) ...[
          const SizedBox(height: 6),
          SelectableText(
            [
              t('file').replaceFirst('{path}', path),
              if (snapshot?.modifiedAt case final modified?)
                t('modified').replaceFirst('{time}', _time(modified)),
              if (snapshot?.namesPath case final namesPath?)
                t('namesFile').replaceFirst('{path}', namesPath),
              if (snapshot?.defaultsVersion case final build?)
                t('defaultsBuild').replaceFirst('{0}', build),
            ].join('\n'),
            key: const Key('key-bindings-file'),
            style: secondary.copyWith(fontSize: 12),
          ),
        ],
      ],
    );
    final list = _list(context, strings, t, secondary);
    if (!helpOpen || listHeight == null) return list;
    if (width < 820) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          help,
          SizedBox(height: tokens.space.md),
          list,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320,
          height: listHeight! + chrome,
          child: SingleChildScrollView(child: help),
        ),
        SizedBox(width: tokens.space.lg),
        Expanded(child: list),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    AppStrings strings,
    String Function(String) t,
    TextStyle secondary,
  ) {
    final tokens = context.tokens;
    final index = this.index;
    final rows = <Widget>[];
    var count = 0;
    for (final map in index?.snapshot.maps ?? const <KeyBindingMap>[]) {
      if (query.isEmpty && !KeyBindingsIndex.inScene(map.name, scene)) {
        continue;
      }
      final names = index!.actionNames[map.name]!;
      final row = <Widget>[];
      for (final action in map.actions) {
        final entries = action.bindings.where((b) {
          if (b.device == 'unknown') return true;
          if (b.device != device) return false;
          if (instance != null && b.instance != instance) return false;
          if (mouse == null || b.cleared) return true;
          return KeyBindingRef(map, action, b, null).isMouse == mouse;
        }).toList();
        final name = names[action.name];
        // A search keeps to this device too; an action bound nowhere still shows, as unbound.
        if (entries.isEmpty && (query.isEmpty || action.bindings.isNotEmpty)) {
          continue;
        }
        if (query.isNotEmpty &&
            !KeyBindingsIndex.matches(
              strings,
              action,
              name,
              query,
              entries: entries,
            )) {
          continue;
        }
        if (onlyChanged && !entries.any((e) => e.customized)) continue;
        final opens = mouse == false
            ? entries.where((e) => !e.cleared && e.device == device).firstOrNull
            : null;
        count++;
        row.add(
          _ListRow(
            action: action,
            name: name,
            entries: entries,
            // Only a keyboard key opens; mouse, pad and stick rows are on the drawing.
            onTap: opens == null
                ? null
                : () => onOpen(KeyBindingRef(map, action, opens, name)),
          ),
        );
      }
      if (row.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 3),
          child: Text(
            index.mapNames[map.name] ?? map.name,
            style: secondary.copyWith(fontSize: 12),
          ),
        ),
      );
      rows.addAll(row);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyBindingsMeasured(
          onHeight: onToolbarHeight ?? (_) {},
          child: Row(
            children: [
              TextButton(
                key: const Key('key-bindings-help'),
                onPressed: onHelp,
                child: Text(t(helpOpen ? 'help.hide' : 'help.show')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StarBridgeFieldFrame(
                  enabled: true,
                  builder: (_, focus) => TextField(
                    key: const Key('key-bindings-search'),
                    focusNode: focus,
                    controller: search,
                    onChanged: (_) => onSearch(),
                    decoration: InputDecoration(labelText: t('search')),
                  ),
                ),
              ),
              if (index?.hasDefaults == true) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 170,
                  child: StarBridgeCheckboxTile(
                    controlKey: const Key('key-bindings-only-changed'),
                    value: onlyChanged,
                    label: t('onlyChanged'),
                    onChanged: onOnlyChanged,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                t('count').replaceFirst('{0}', '$count'),
                key: const Key('key-bindings-count'),
                style: secondary.copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (listHeight case final listHeight?) ...[
          SizedBox(height: tokens.space.xs),
          if (rows.isEmpty && index != null && !blocked)
            Padding(
              key: const Key('key-bindings-no-match'),
              padding: EdgeInsets.all(tokens.space.md),
              child: Text(
                t(index.hasDefaults ? 'noMatch' : 'noMatchChanged'),
                style: secondary,
              ),
            )
          else
            // Built as it scrolls: an official list has hundreds of rows.
            SizedBox(
              height: listHeight,
              // The rows' ink needs a Material above the shell's opaque page ground.
              child: Material(
                type: MaterialType.transparency,
                child: ListView.builder(
                  key: const Key('key-bindings-list'),
                  itemCount: rows.length,
                  itemBuilder: (_, index) => rows[index],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

final class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.action,
    required this.name,
    required this.entries,
    required this.onTap,
  });
  final KeyBindingAction action;
  final String? name;
  final List<KeyBindingEntry> entries;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.$key');
    final tokens = context.tokens;
    return InkWell(
      key: Key('key-binding-${action.name}'),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.sm,
          vertical: tokens.space.xs,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: tokens.surfaces.panel.border),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name ?? t('noName')),
                  Text(
                    action.name,
                    style: TextStyle(
                      color: tokens.colors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: tokens.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (entries.isEmpty)
                    Text(
                      t('unbound'),
                      style: TextStyle(color: tokens.colors.textSecondary),
                    ),
                  for (final entry in entries)
                    Text(
                      entry.customized
                          ? t('changed').replaceFirst(
                              '{0}',
                              keyBindingLabel(strings, entry),
                            )
                          : keyBindingLabel(strings, entry),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: entry.customized
                            ? tokens.colors.warning
                            : tokens.colors.textPrimary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
