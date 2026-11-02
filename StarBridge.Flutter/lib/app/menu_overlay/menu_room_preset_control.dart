import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../features/party_rooms/room_action_dialogs.dart';
import '../../features/party_rooms/room_preset_choices.dart';
import '../../features/common/social_read_activity.dart';
import 'menu_room_preset_view.dart';

class MenuRoomPresetControl extends StatefulWidget {
  const MenuRoomPresetControl({
    super.key,
    required this.view,
    required this.scope,
    required this.enabled,
    required this.dispatch,
  });
  final MenuRoomPresetView view;
  final String scope;
  final bool enabled;
  final void Function(String, String) dispatch;
  @override
  State<MenuRoomPresetControl> createState() => _PresetControlState();
}

class _PresetControlState extends State<MenuRoomPresetControl> {
  ValueNotifier<MenuRoomPresetView?>? _dialog;
  bool _selected = false;
  int _openedRevision = 0;
  @override
  void didUpdateWidget(MenuRoomPresetControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dialog?.value =
        oldWidget.scope != widget.scope ||
            widget.view.open == null ||
            _selected && widget.view.revision != _openedRevision
        ? null
        : widget.view;
  }

  Future<void> _open(InteractionSource source) async {
    if (!widget.enabled || widget.view.open == null || _dialog != null) return;
    _selected = false;
    _openedRevision = widget.view.revision;
    final state = _dialog = ValueNotifier<MenuRoomPresetView?>(widget.view);
    widget.dispatch(widget.view.open!, '');
    try {
      await showStarBridgeDialog<void>(
        context,
        source: source,
        useRootNavigator: false,
        builder: (_) => _PresetPicker(
          view: state,
          openingSource: source,
          select: (action) {
            _selected = true;
            widget.dispatch(action, '');
          },
        ),
      );
    } finally {
      if (identical(_dialog, state)) _dialog = null;
      state.dispose();
    }
  }

  @override
  void dispose() {
    _dialog?.value = null;
    _dialog = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeActionButton(
    kind: StarBridgeActionKind.quiet,
    controlKey: const ValueKey('menu-room-share-preset'),
    onActivate: widget.enabled && widget.view.open != null ? _open : null,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StarBridgeIcon(StarBridgeIconSemantic.overlay),
        const SizedBox(width: 8),
        Text(roomActionText(context, 'sharePreset')),
      ],
    ),
  );
}

class _PresetPicker extends StatefulWidget {
  const _PresetPicker({
    required this.view,
    required this.select,
    required this.openingSource,
  });
  final ValueNotifier<MenuRoomPresetView?> view;
  final ValueChanged<String> select;
  final InteractionSource openingSource;
  @override
  State<_PresetPicker> createState() => _PickerState();
}

class _PickerState extends State<_PresetPicker> {
  bool _working = false, _closing = false;
  InteractionSource _source = InteractionSource.pointer;
  @override
  void initState() {
    super.initState();
    widget.view.addListener(_changed);
  }

  void _changed() {
    if (widget.view.value == null && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) dismissStarBridgeDialog(context, source: _source);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          if (widget.view.value?.error != null) _working = false;
        });
      }
    });
  }

  @override
  void dispose() {
    widget.view.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view.value;
    String t(String key) => roomActionText(context, key);
    return AlertDialog(
      title: Text(t('sharePreset')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('sharePresetHint')),
              const SizedBox(height: 12),
              if (view == null || !view.loaded && view.error == null)
                SocialReadActivity(
                  key: const Key('menu-room-preset-catalog-wait'),
                  source: widget.openingSource,
                  opening: false,
                  label: t('working'),
                  height: 4,
                )
              else if (view.error != null)
                Text(t(view.error!))
              else if (view.choices.isEmpty)
                Text(t('noPresets'))
              else
                RoomPresetChoices(
                  choices: view.choices,
                  enabled: !_working,
                  onSelected: (choice, source) {
                    if (_working) return;
                    _source = source;
                    setState(() => _working = true);
                    widget.select(choice.id);
                  },
                ),
              if (_working)
                SocialReadActivity(
                  key: const Key('menu-room-preset-prepare-wait'),
                  source: _source,
                  opening: false,
                  label: t('working'),
                  height: 4,
                ),
            ],
          ),
        ),
      ),
      actions: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(t('cancel')),
        ),
      ],
    );
  }
}

class MenuRoomPresetAttachment extends StatelessWidget {
  const MenuRoomPresetAttachment({
    super.key,
    required this.view,
    required this.enabled,
    required this.dispatch,
  });
  final MenuRoomPresetView view;
  final bool enabled;
  final void Function(String, String) dispatch;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: const StarBridgeIcon(StarBridgeIconSemantic.overlay),
    title: Text(view.draftName ?? ''),
    subtitle: Text(roomActionText(context, 'presetDraft')),
    trailing: StarBridgeIconAction(
      controlKey: const ValueKey('menu-room-clear-preset'),
      label: roomActionText(context, 'removeAttachment'),
      onActivate: enabled && view.clear != null
          ? (_) => dispatch(view.clear!, '')
          : null,
      icon: const StarBridgeIcon(StarBridgeIconSemantic.windowClose),
    ),
  );
}
