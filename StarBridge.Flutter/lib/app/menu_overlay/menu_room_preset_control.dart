import 'package:flutter/material.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../features/party_rooms/room_action_dialogs.dart';
import '../../features/party_rooms/room_preset_choices.dart';
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

  Future<void> _open() async {
    if (!widget.enabled || widget.view.open == null || _dialog != null) return;
    _selected = false;
    _openedRevision = widget.view.revision;
    final state = _dialog = ValueNotifier<MenuRoomPresetView?>(widget.view);
    widget.dispatch(widget.view.open!, '');
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => _PresetPicker(
          view: state,
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
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('menu-room-share-preset'),
    onPressed: widget.enabled && widget.view.open != null ? _open : null,
    icon: const StarBridgeIcon(StarBridgeIconSemantic.overlay),
    label: Text(roomActionText(context, 'sharePreset')),
  );
}

class _PresetPicker extends StatefulWidget {
  const _PresetPicker({required this.view, required this.select});
  final ValueNotifier<MenuRoomPresetView?> view;
  final ValueChanged<String> select;
  @override
  State<_PresetPicker> createState() => _PickerState();
}

class _PickerState extends State<_PresetPicker> {
  bool _working = false, _closing = false;
  @override
  void initState() {
    super.initState();
    widget.view.addListener(_changed);
  }

  void _changed() {
    if (widget.view.value == null && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
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
                const LinearProgressIndicator()
              else if (view.error != null)
                Text(t(view.error!))
              else if (view.choices.isEmpty)
                Text(t('noPresets'))
              else
                RoomPresetChoices(
                  choices: view.choices,
                  enabled: !_working,
                  onSelected: (choice) {
                    if (_working) return;
                    setState(() => _working = true);
                    widget.select(choice.id);
                  },
                ),
              if (_working) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
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
    trailing: IconButton(
      key: const ValueKey('menu-room-clear-preset'),
      tooltip: roomActionText(context, 'removeAttachment'),
      onPressed: enabled && view.clear != null
          ? () => dispatch(view.clear!, '')
          : null,
      icon: const StarBridgeIcon(StarBridgeIconSemantic.windowClose),
    ),
  );
}
