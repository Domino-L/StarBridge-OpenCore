import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_settings_models.dart';
import 'overlay_scene_controller.dart';
import 'overlay_scene_picker.dart';
import 'overlay_workspace_appearance_center.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_editor_state.dart';
import 'overlay_workspace_fullscreen.dart';
import 'overlay_workspace_group_navigation.dart';
import 'overlay_workspace_layout_editor.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_module_style_controls.dart';
import 'overlay_workspace_preset_bar.dart';
import 'overlay_workspace_preview_stage.dart';
import 'overlay_workspace_runtime_card.dart';
import 'overlay_workspace_schema.dart';

class OverlayWorkspacePage extends StatefulWidget {
  const OverlayWorkspacePage({required this.module, this.scenes, super.key});

  final OverlayWorkspaceModule module;
  final OverlaySceneController? scenes;

  @override
  State<OverlayWorkspacePage> createState() => _OverlayWorkspacePageState();
}

class _OverlayWorkspacePageState extends State<OverlayWorkspacePage> {
  String _group = overlayWorkspaceGroupOrder.first;
  bool _appearanceCenterOpen = false;
  final _editor = OverlayWorkspaceEditorState();

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Widget get _fullscreenButton =>
      OverlayWorkspaceFullscreenButton(module: widget.module, editor: _editor);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OverlayWorkspaceProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        if (projection.operation == OverlayWorkspaceOperation.reading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!projection.available) {
          return _Unavailable(
            failure: projection.failure,
            onRetry: widget.module.refresh,
          );
        }
        return _content(context, projection);
      },
    );
  }

  Widget _content(BuildContext context, OverlayWorkspaceProjection projection) {
    final snapshot = projection.snapshot!;
    final active = snapshot.presets.singleWhere(
      (preset) => preset.id == snapshot.activePresetId,
    );
    final fields = overlayWorkspaceFieldSpecs
        .where((field) => field.group == _group && (widget.scenes == null || field.field != 'scenePreference'))
        .toList(growable: false);
    return Stack(
      children: [
        if (_appearanceCenterOpen)
          OverlayWorkspaceAppearanceCenter(
            projection: projection,
            module: widget.module,
            onBack: () => setState(() => _appearanceCenterOpen = false),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 1280
                ? _wideWorkspace(context, projection, active, fields)
                : _compactWorkspace(context, projection, active, fields),
          ),
        Align(
          alignment: AlignmentDirectional.bottomCenter,
          child: _SaveBar(projection: projection, module: widget.module),
        ),
      ],
    );
  }

  Widget _wideWorkspace(
    BuildContext context,
    OverlayWorkspaceProjection projection,
    OverlayWorkspacePreset active,
    List<OverlayWorkspaceFieldSpec> fields,
  ) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        88,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _Header(activePresetName: active.name)),
              SizedBox(width: tokens.space.lg),
              Expanded(
                child: OverlayWorkspaceRuntimeCard(
                  projection: projection,
                  onAction: () => _runRuntimeAction(projection),
                ),
              ),
            ],
          ),
          if (projection.failure case final failure?) ...[
            SizedBox(height: tokens.space.md),
            _Failure(failure: failure, onRetry: widget.module.refresh),
          ],
          SizedBox(height: tokens.space.md),
          OverlayWorkspacePresetBar(
            projection: projection,
            module: widget.module,
            onImport: () => _importPreset(projection),
            onExport: () => _exportPreset(active),
            onOpenAppearance: () =>
                setState(() => _appearanceCenterOpen = true),
          ),
          SizedBox(height: tokens.space.md),
          Expanded(
            child: KeyedSubtree(
              key: const Key('overlay-workspace-content'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 190,
                    child: OverlayWorkspaceGroupNavigation(
                      selected: _group,
                      onSelected: (value) => setState(() => _group = value),
                    ),
                  ),
                  SizedBox(width: tokens.space.md),
                  SizedBox(
                    width: 400,
                    child: SingleChildScrollView(
                      key: const Key('overlay-settings-dock'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OverlayWorkspaceSettingsGroup(
                            group: _group,
                            fields: fields,
                            settings: projection.settings!,
                            appearances: projection.snapshot!.appearances,
                            onChanged: widget.module.updateSetting,
                            onExperiencePreset:
                                widget.module.applyExperiencePreset,
                            footer: _moduleStyleControls(projection),
                          ),
                          if (_group == 'startup') ...[
                            SizedBox(height: tokens.space.md),
                            OverlayWorkspaceHotkeyCard(
                              hotkey: projection.hotkey!,
                              onBindingChanged: (value) =>
                                  widget.module.updateHotkey(binding: value),
                              onEnabledChanged: (value) =>
                                  widget.module.updateHotkey(enabled: value),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.space.md),
                  Expanded(
                    child: OverlayWorkspacePreviewStage(
                      editorCanvas: OverlayWorkspaceInteractivePreview(
                        module: widget.module,
                        editor: _editor,
                      ),
                      projection: projection,
                      fullscreenButton: _fullscreenButton,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactWorkspace(
    BuildContext context,
    OverlayWorkspaceProjection projection,
    OverlayWorkspacePreset active,
    List<OverlayWorkspaceFieldSpec> fields,
  ) {
    final tokens = context.tokens;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 720
        ? tokens.space.md
        : tokens.space.xl;
    return SingleChildScrollView(
      key: const Key('overlay-workspace-content'),
      padding: EdgeInsetsDirectional.fromSTEB(
        horizontalPadding,
        tokens.space.lg,
        horizontalPadding,
        104,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(activePresetName: active.name),
          SizedBox(height: tokens.space.md),
          OverlayWorkspaceRuntimeCard(
            projection: projection,
            onAction: () => _runRuntimeAction(projection),
            showPreview: true,
            editorCanvas: OverlayWorkspaceInteractivePreview(
              module: widget.module,
              editor: _editor,
            ),
            fullscreenButton: _fullscreenButton,
          ),
          if (projection.failure case final failure?) ...[
            SizedBox(height: tokens.space.md),
            _Failure(failure: failure, onRetry: widget.module.refresh),
          ],
          SizedBox(height: tokens.space.md),
          OverlayWorkspacePresetBar(
            projection: projection,
            module: widget.module,
            onImport: () => _importPreset(projection),
            onExport: () => _exportPreset(active),
            onOpenAppearance: () =>
                setState(() => _appearanceCenterOpen = true),
          ),
          SizedBox(height: tokens.space.md),
          _GroupSelector(
            selected: _group,
            onSelected: (value) => setState(() => _group = value),
          ),
          SizedBox(height: tokens.space.md),
          OverlayWorkspaceSettingsGroup(
            group: _group,
            fields: fields,
            settings: projection.settings!,
            appearances: projection.snapshot!.appearances,
            onChanged: widget.module.updateSetting,
            onExperiencePreset: widget.module.applyExperiencePreset,
            footer: _moduleStyleControls(projection),
          ),
          if (_group == 'startup') ...[
            SizedBox(height: tokens.space.md),
            OverlayWorkspaceHotkeyCard(
              hotkey: projection.hotkey!,
              onBindingChanged: (value) =>
                  widget.module.updateHotkey(binding: value),
              onEnabledChanged: (value) =>
                  widget.module.updateHotkey(enabled: value),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _moduleStyleControls(OverlayWorkspaceProjection projection) {
    if (_group == 'startup' && widget.scenes != null) {
      return OverlayScenePicker(controller: widget.scenes!);
    }
    if (!const {
      'notice',
      'fleetOverview',
      'members',
      'chat',
      'events',
    }.contains(_group)) {
      return null;
    }
    return OverlayWorkspaceModuleStyleControls(
      group: _group,
      layout: projection.layout,
      settings: projection.settings!,
      onLayoutChanged: (item, coalesce) =>
          widget.module.updateLayoutItem(item, coalesce: coalesce),
      onSettingChanged: widget.module.updateSetting,
    );
  }

  Future<void> _runRuntimeAction(OverlayWorkspaceProjection projection) async {
    final language = Localizations.localeOf(context).toLanguageTag();
    switch (projection.runtime.windowState) {
      case 'open':
        await widget.module.closeRuntime(language);
        return;
      case 'failed':
        await widget.module.retryRuntime(language);
        return;
      case 'unavailable':
        await widget.module.refreshRuntime(language);
        return;
      default:
        await widget.module.openRuntime(language);
        return;
    }
  }

  Future<void> _exportPreset(OverlayWorkspacePreset preset) async {
    final package = jsonEncode({
      'schemaVersion': 1,
      'name': preset.name,
      'settings': preset.settings.toMap(),
      'layout': preset.layout.map((item) => item.toMap()).toList(),
    });
    await Clipboard.setData(ClipboardData(text: package));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_copy(context, 'overlay.workspace.exported'))),
    );
  }

  Future<void> _importPreset(OverlayWorkspaceProjection projection) async {
    final controller = TextEditingController();
    final payload = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_copy(context, 'overlay.workspace.importTitle')),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              labelText: _copy(context, 'overlay.workspace.importLabel'),
              helperText: _copy(context, 'overlay.workspace.importHelp'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_copy(context, 'overlay.workspace.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_copy(context, 'overlay.workspace.import')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (payload == null || payload.trim().isEmpty) return;
    try {
      final document = jsonDecode(payload);
      if (document is! Map || document['schemaVersion'] != 1) {
        throw const FormatException();
      }
      final data = Map<String, Object?>.from(document.cast<String, Object?>());
      final settings = OverlayWorkspaceSettings.fromMap(
        stringMap(data['settings']),
      );
      final layout = objectList(data['layout'])
          .map((item) => OverlayWorkspaceLayoutItem.fromMap(stringMap(item)))
          .toList(growable: false);
      final name = data['name'];
      if (name is! String || name.trim().isEmpty) throw const FormatException();
      await widget.module.importPreset(
        name: name,
        settings: settings,
        layout: layout,
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_copy(context, 'overlay.workspace.importInvalid')),
        ),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.activePresetName});

  final String activePresetName;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _copy(context, 'overlay.title'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        SizedBox(height: tokens.space.xs),
        Text(
          _copy(context, 'overlay.workspace.description'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
      ],
    );
    final preset = Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.colors.accent),
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        _copy(
          context,
          'overlay.workspace.currentPreset',
        ).replaceAll('{name}', activePresetName),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              SizedBox(height: tokens.space.sm),
              preset,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: copy),
            SizedBox(width: tokens.space.md),
            preset,
          ],
        );
      },
    );
  }
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Wrap(
      spacing: tokens.space.xs,
      runSpacing: tokens.space.xs,
      children: overlayWorkspaceNavigationGroupOrder
          .map(
            (group) => ChoiceChip(
              selected: selected == group,
              label: Text(overlayWorkspaceGroupName(context, group)),
              onSelected: (_) => onSelected(group),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.projection, required this.module});

  final OverlayWorkspaceProjection projection;
  final OverlayWorkspaceModule module;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      elevation: 12,
      color: tokens.surfaces.floating.fill,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.xl,
            vertical: tokens.space.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (projection.busy) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: tokens.space.sm),
              ],
              Text(
                _copy(
                  context,
                  projection.dirty
                      ? 'overlay.workspace.dirty'
                      : 'overlay.workspace.saved',
                ),
              ),
              SizedBox(width: tokens.space.md),
              IconButton(
                tooltip: _copy(context, 'overlay.workspace.undo'),
                onPressed: module.canUndo && !projection.busy
                    ? module.undo
                    : null,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.undo),
              ),
              IconButton(
                tooltip: _copy(context, 'overlay.workspace.redo'),
                onPressed: module.canRedo && !projection.busy
                    ? module.redo
                    : null,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.redo),
              ),
              SizedBox(width: tokens.space.xs),
              TextButton(
                onPressed: projection.dirty && !projection.busy
                    ? module.discardChanges
                    : null,
                child: Text(_copy(context, 'overlay.workspace.discard')),
              ),
              SizedBox(width: tokens.space.xs),
              FilledButton(
                onPressed: projection.dirty && !projection.busy
                    ? module.save
                    : null,
                child: Text(_copy(context, 'overlay.workspace.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.failure, required this.onRetry});

  final OverlaySettingsFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _copy(context, 'overlay.unavailable.title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(_failureText(context, failure)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(_copy(context, 'overlay.retry')),
          ),
        ],
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.failure, required this.onRetry});

  final OverlaySettingsFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(_failureText(context, failure)),
    actions: [
      TextButton(
        onPressed: onRetry,
        child: Text(_copy(context, 'overlay.retry')),
      ),
    ],
  );
}

String _failureText(BuildContext context, OverlaySettingsFailure? failure) =>
    _copy(context, switch (failure) {
      OverlaySettingsFailure.writeConflict => 'overlay.error.writeConflict',
      OverlaySettingsFailure.invalidValue => 'overlay.error.invalidValue',
      OverlaySettingsFailure.writeFailed => 'overlay.error.writeFailed',
      OverlaySettingsFailure.readFailed => 'overlay.error.readFailed',
      _ => 'overlay.error.hostUnavailable',
    });

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
