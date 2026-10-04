import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_scene_controller.dart';
import 'overlay_source_binding_field.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

class OverlayPresetSettingsDialog extends StatefulWidget {
  const OverlayPresetSettingsDialog({
    required this.module,
    required this.preset,
    this.scenes,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayWorkspacePreset preset;
  final OverlaySceneController? scenes;
  @override
  State<OverlayPresetSettingsDialog> createState() =>
      _OverlayPresetSettingsDialogState();
}

class _OverlayPresetSettingsDialogState
    extends State<OverlayPresetSettingsDialog> {
  late final _name = TextEditingController(text: widget.preset.name);
  late var _binding = widget.preset.sources!.binding;
  late var _autoSwitch = widget.preset.sources!.autoSwitch;
  late final int? _revision;
  bool _saving = false, _failed = false;
  @override
  void initState() {
    super.initState();
    _revision = widget.module.projection.value.snapshot?.revision;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppStrings.of(context).text;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(copy('overlay.source.presetSettings')),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                enabled: !_saving,
                maxLength: 24,
                decoration: InputDecoration(
                  labelText: copy('overlay.workspace.presetName'),
                ),
                onChanged: (_) => setState(() => _failed = false),
              ),
              SizedBox(height: context.tokens.space.md),
              OverlaySourceBindingField(
                value: _binding,
                scenes: widget.scenes,
                presetBinding: true,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _binding = value;
                        _failed = false;
                        if (value.mode != OverlaySourceMode.room &&
                            value.mode != OverlaySourceMode.community) {
                          _autoSwitch = false;
                        }
                      }),
              ),
              SizedBox(height: context.tokens.space.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(copy('overlay.source.autoSwitch')),
                subtitle: Text(
                  copy(
                    _binding.mode == OverlaySourceMode.room ||
                            _binding.mode == OverlaySourceMode.community
                        ? 'overlay.source.autoSwitchHelp'
                        : 'overlay.source.autoSwitchRequiresBinding',
                  ),
                ),
                value:
                    _autoSwitch &&
                    (_binding.mode == OverlaySourceMode.room ||
                        _binding.mode == OverlaySourceMode.community),
                onChanged:
                    _saving ||
                        (_binding.mode != OverlaySourceMode.room &&
                            _binding.mode != OverlaySourceMode.community)
                    ? null
                    : (value) => setState(() => _autoSwitch = value),
              ),
              if (_failed)
                Padding(
                  padding: EdgeInsets.only(top: context.tokens.space.sm),
                  child: Text(
                    copy('overlay.source.saveFailed'),
                    key: const Key('overlay-preset-settings-error'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(copy('overlay.workspace.cancel')),
          ),
          FilledButton(
            key: const Key('overlay-preset-settings-save'),
            onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
            child: Text(copy('overlay.source.save')),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final projection = widget.module.projection.value;
    if (projection.busy || projection.snapshot?.sourcePresetsEnabled != true) {
      return;
    }
    if (projection.snapshot?.revision != _revision) {
      setState(() => _failed = true);
      return;
    }
    final conflicts = projection.snapshot!.presets
        .where(
          (p) =>
              p.id != widget.preset.id &&
              _autoSwitch &&
              p.sources?.autoSwitch == true &&
              p.sources?.binding == _binding,
        )
        .toList();
    if (conflicts.length > 1) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _saving = true);
    if (conflicts.isNotEmpty) {
      final copy = AppStrings.of(context).text;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(copy('overlay.source.presetSettings')),
          content: Text(
            copy('overlay.source.replaceAutoSwitch')
                .replaceAll('{name}', conflicts.single.name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy('overlay.workspace.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy('overlay.source.replace')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _saving = false);
        return;
      }
    }
    final saved = await widget.module.configurePreset(
      widget.preset.id,
      _name.text.trim(),
      _binding,
      _autoSwitch,
      replaceAutoSwitchPresetId: conflicts.firstOrNull?.id,
      expectedRevision: _revision,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }
}
