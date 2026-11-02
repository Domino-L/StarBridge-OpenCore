import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/color_choice_icon.dart';
import '../../design_system/icons/native_dropdown_indicator_icon.dart';
import 'overlay_workspace_appearance_entry.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';
import 'overlay_menu_trigger.dart';
import 'overlay_workspace_module.dart';
import 'overlay_scene_controller.dart';
import 'overlay_preset_settings_dialog.dart';
import 'overlay_preset_name.dart';
import 'overlay_workspace_preset_cards.dart';

class OverlayWorkspacePresetBar extends StatefulWidget {
  const OverlayWorkspacePresetBar({
    required this.projection,
    required this.module,
    required this.onImport,
    required this.onExport,
    required this.onOpenAppearance,
    this.onImportSource,
    this.onExportSource,
    this.showLegacyScene = true,
    this.compact = false,
    this.sourceSelector,
    this.scenes,
    super.key,
  });

  final OverlayWorkspaceProjection projection;
  final OverlayWorkspaceModule module;
  final VoidCallback onImport;
  final ValueChanged<InteractionSource>? onImportSource;
  final ValueChanged<InteractionSource>? onExportSource;
  final VoidCallback onExport;
  final VoidCallback onOpenAppearance;
  final bool showLegacyScene;
  final bool compact;
  final Widget? sourceSelector;
  final OverlaySceneController? scenes;

  @override
  State<OverlayWorkspacePresetBar> createState() =>
      _OverlayWorkspacePresetBarState();
}

class _OverlayWorkspacePresetBarState extends State<OverlayWorkspacePresetBar> {
  late final TextEditingController _nameController;
  late String _boundPresetId;
  late String _boundPresetName;
  // What the name field was last set to: the stored name, or the built-in
  // name in the reader's language.
  String _shownName = '';

  OverlayWorkspaceProjection get projection => widget.projection;
  OverlayWorkspaceModule get module => widget.module;
  VoidCallback get onImport => widget.onImport;
  VoidCallback get onExport => widget.onExport;
  VoidCallback get onOpenAppearance => widget.onOpenAppearance;

  @override
  void initState() {
    super.initState();
    final preset = _activePreset(projection.snapshot!);
    _boundPresetId = preset.id;
    _boundPresetName = preset.name;
    _nameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = _shown(_activePreset(projection.snapshot!));
    if (_nameController.text == _shownName) _showName(shown);
  }

  String _shown(OverlayWorkspacePreset preset) =>
      preset.shownName(AppStrings.of(context));

  void _showName(String name) {
    _shownName = name;
    _nameController.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  @override
  void didUpdateWidget(covariant OverlayWorkspacePresetBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preset = _activePreset(projection.snapshot!);
    if (oldWidget.module != widget.module ||
        preset.id != _boundPresetId ||
        (preset.name != _boundPresetName &&
            _nameController.text == _shownName)) {
      _boundPresetId = preset.id;
      _boundPresetName = preset.name;
      _showName(_shown(preset));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// A plan saved with a fixed source keeps it (never changed for the user);
  /// it is flagged where the plan is chosen. Released from the source pickers.
  String? _fixedSource(BuildContext context, OverlayWorkspacePreset active) {
    final binding = active.sources?.binding;
    if (binding == null || binding.mode == OverlaySourceMode.none) return null;
    final name = switch (binding.mode) {
      OverlaySourceMode.room => _copy(context, 'overlay.source.room'),
      OverlaySourceMode.fleet =>
        widget.scenes?.projection.value.fleetLabel(
              (key) => _copy(context, key),
            ) ??
            _copy(context, 'overlay.source.fleet'),
      OverlaySourceMode.community =>
        widget.scenes?.projection.value.targets
                .where((t) => t.code == binding.communityCode)
                .firstOrNull
                ?.name ??
            _copy(context, 'overlay.source.missing'),
      _ => _copy(context, 'overlay.source.auto'),
    };
    return _copy(
      context,
      'overlay.source.planFixedLabel',
    ).replaceAll('{source}', name);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = projection.snapshot!;
    if (widget.compact) {
      final active = _activePreset(snapshot);
      final native =
          resolveStarBridgeInteraction(context).suite ==
          InteractionSuite.standard;
      final presetDecoration = InputDecoration(
        isDense: true,
        enabled: !projection.busy,
        labelText: _copy(context, 'overlay.workspace.quickPresets'),
        suffixIconConstraints: native
            ? const BoxConstraints(minWidth: 42, minHeight: 24)
            : null,
        suffixIcon: native
            ? Padding(
                padding: const EdgeInsetsDirectional.only(end: 18),
                child: IconTheme(
                  data: IconThemeData(
                    size: 24,
                    color: Theme.brightnessOf(context) == Brightness.dark
                        ? (projection.busy ? Colors.white10 : Colors.white70)
                        : (projection.busy
                              ? Colors.grey.shade400
                              : Colors.grey.shade700),
                  ),
                  child: const NativeDropdownIndicatorIcon(),
                ),
              )
            : null,
      );
      final appearance = snapshot.appearances
          .where((a) => a.id == projection.settings!['skin'])
          .firstOrNull;
      final name = Localizations.localeOf(context).languageCode == 'en'
          ? appearance?.displayNameEn
          : appearance?.displayNameZh;
      return Wrap(
        key: const Key('overlay-preset-toolbar'),
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: StarBridgeMenuAnchor(
              semanticLabel: _copy(context, 'overlay.workspace.quickPresets'),
              enabled: !projection.busy,
              entries: [
                for (final preset in snapshot.presets)
                  StarBridgeMenuEntry(
                    id: 'overlay-preset-select-${preset.id}',
                    label: _shown(preset),
                    onActivate: projection.busy
                        ? null
                        : (source) =>
                              _activatePreset(context, preset.id, source),
                    child: Semantics(
                      selected: preset.id == active.id,
                      child: Row(
                        children: [
                          if (preset.id == active.id)
                            const ColorChoiceIcon.selection(
                              selected: true,
                              size: 16,
                            ),
                          Flexible(
                            child: Text(
                              _shown(preset),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                StarBridgeMenuEntry(
                  id: 'overlay-preset-select-new',
                  label: _copy(context, 'overlay.workspace.addPreset'),
                  onActivate: projection.busy
                      ? null
                      : (source) => _createPreset(context, source),
                  child: Text(_copy(context, 'overlay.workspace.addPreset')),
                ),
              ],
              builder: (context, controller, focus, toggle) => StarBridgeActionRow(
                key: ValueKey('overlay-preset-selector-${active.id}'),
                focusNode: focus,
                semanticLabel:
                    '${_copy(context, 'overlay.workspace.quickPresets')} · ${_shown(active)}',
                onActivate: projection.busy
                    ? null
                    : (_, source) => toggle(source),
                child: InputDecorator(
                  decoration: presetDecoration,
                  child: ExcludeSemantics(
                    child: native
                        ? IgnorePointer(
                            child: ExcludeFocus(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: active.id,
                                  isDense: true,
                                  isExpanded: true,
                                  icon: const SizedBox.shrink(),
                                  iconSize: 24,
                                  onChanged: projection.busy ? null : (_) {},
                                  items: [
                                    for (final p in snapshot.presets)
                                      DropdownMenuItem(
                                        value: p.id,
                                        child: Text(_shown(p)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _shown(active),
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: projection.busy
                                            ? tokens.colors.textDisabled
                                            : tokens.colors.textPrimary,
                                      ),
                                ),
                              ),
                              const StarBridgeIcon(
                                StarBridgeIconSemantic.menuDown,
                                size: 18,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: _manageMenu(
              context,
              snapshot,
              OverlayMenuTrigger(
                enabled: !projection.busy,
                label: _copy(context, 'overlay.workspace.managePresets'),
              ),
            ),
          ),
          if (snapshot.sourcePresetsEnabled && active.sources != null)
            StarBridgeActionButton(
              key: const Key('overlay-preset-settings-entry'),
              onActivate: projection.busy
                  ? null
                  : (source) =>
                        _handleAction(context, _PresetAction.settings, source),
              child: Text(_copy(context, 'overlay.source.presetSettings')),
            ),
          StarBridgeActionButton(
            key: const Key('overlay-appearance-center-entry'),
            onActivate: (_) => onOpenAppearance(),
            child: Text(
              '${_copy(context, 'overlay.workspace.appearance.current')} · ${name ?? _copy(context, 'overlay.workspace.appearance.unknown')}',
            ),
          ),
          if (widget.sourceSelector != null) widget.sourceSelector!,
          if (_fixedSource(context, active) case final fixed?)
            Text(
              fixed,
              key: const Key('overlay-preset-fixed-source'),
              // A plan's own choice, not a problem: quiet, not warning colored.
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          // Edits save on their own; this only reports it. Undo and redo are
          // always here because there is no save bar to hold them.
          Text(
            _copy(
              context,
              !projection.dirty
                  ? 'overlay.workspace.savedShort'
                  : projection.failure == null
                  ? 'overlay.workspace.saving'
                  : 'overlay.workspace.saveFailed',
            ),
            key: const Key('overlay-preset-save-status'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: projection.dirty && projection.failure != null
                  ? tokens.colors.warning
                  : null,
            ),
          ),
          StarBridgeIconAction(
            controlKey: const Key('overlay-preset-undo'),
            label: _copy(context, 'overlay.workspace.undo'),
            onActivate: module.canUndo && !projection.busy
                ? (_) => module.undo()
                : null,
            icon: const StarBridgeIcon(StarBridgeIconSemantic.undo),
          ),
          StarBridgeIconAction(
            controlKey: const Key('overlay-preset-redo'),
            label: _copy(context, 'overlay.workspace.redo'),
            onActivate: module.canRedo && !projection.busy
                ? (_) => module.redo()
                : null,
            icon: const StarBridgeIcon(StarBridgeIconSemantic.redo),
          ),
        ],
      );
    }
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _copy(context, 'overlay.workspace.quickPresets'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            _copy(context, 'overlay.workspace.quickPresetsHelp'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...snapshot.presets.map(
                  (preset) => Padding(
                    padding: EdgeInsets.only(right: tokens.space.sm),
                    child: OverlayQuickPresetCard(
                      preset: preset,
                      showLegacyScene: widget.showLegacyScene,
                      selected: preset.id == snapshot.activePresetId,
                      enabled: !projection.busy,
                      onPressed: (source) =>
                          _activatePreset(context, preset.id, source),
                    ),
                  ),
                ),
                OverlayAddPresetCard(
                  enabled: !projection.busy,
                  onPressed: (source) => _createPreset(context, source),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.space.md),
          Divider(color: tokens.surfaces.panel.border, height: 1),
          SizedBox(height: tokens.space.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final presetControls = Row(
                children: [
                  Expanded(
                    child: OverlayPresetNameEditor(
                      controller: _nameController,
                      currentName: _shownName,
                      enabled: !projection.busy,
                      onSave: _renameCurrentPreset,
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  _manageMenu(
                    context,
                    snapshot,
                    Container(
                      height: tokens.density.controlHeight + tokens.space.sm,
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.space.md,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: projection.busy
                              ? tokens.colors.textDisabled
                              : tokens.surfaces.panel.border,
                          width: tokens.stroke.regular,
                        ),
                        borderRadius: tokens.shape.small,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StarBridgeIcon(
                            StarBridgeIconSemantic.settings,
                            size: tokens.icons.small,
                            color: projection.busy
                                ? tokens.colors.textDisabled
                                : tokens.colors.textPrimary,
                          ),
                          SizedBox(width: tokens.space.xs),
                          Text(
                            _copy(context, 'overlay.workspace.managePresets'),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: projection.busy
                                      ? tokens.colors.textDisabled
                                      : tokens.colors.textPrimary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
              final appearance = OverlayWorkspaceAppearanceEntry(
                projection: projection,
                onPressed: onOpenAppearance,
              );
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    presetControls,
                    SizedBox(height: tokens.space.sm),
                    appearance,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: presetControls),
                  SizedBox(width: tokens.space.md),
                  SizedBox(width: 300, child: appearance),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _activatePreset(
    BuildContext context,
    String presetId,
    InteractionSource source,
  ) async {
    final snapshot = projection.snapshot!;
    if (presetId == snapshot.activePresetId || projection.busy) return;
    // Pending edits are saved to the current plan before switching.
    await module.activatePreset(presetId);
  }

  Future<void> _createPreset(
    BuildContext context,
    InteractionSource source,
  ) async {
    if (projection.busy) return;
    final defaultName = _copy(context, 'overlay.workspace.newPresetName');
    await module.createPreset(defaultName);
  }

  Future<void> _renameCurrentPreset() async {
    if (projection.busy) return;
    final currentModule = module;
    final presetId = _boundPresetId;
    final name = _nameController.text.trim();
    if (name.isEmpty || name == _shownName) return;
    final renamed = await currentModule.renamePreset(presetId, name);
    if (!mounted || module != currentModule || _boundPresetId != presetId) {
      return;
    }
    if (renamed) {
      setState(() {
        _boundPresetName = name;
        _showName(name);
      });
    }
  }

  Widget _manageMenu(
    BuildContext context,
    OverlayWorkspaceSnapshot snapshot,
    Widget child,
  ) {
    final label = _copy(context, 'overlay.workspace.managePresets');
    return StarBridgeMenuAnchor(
      semanticLabel: label,
      enabled: !projection.busy,
      entries: [
        for (final action in [
          if (widget.compact &&
              snapshot.sourcePresetsEnabled &&
              _activePreset(snapshot).sources != null)
            _PresetAction.settings,
          if (widget.compact) _PresetAction.rename,
          _PresetAction.copy,
          _PresetAction.reset,
          _PresetAction.delete,
          _PresetAction.import,
          _PresetAction.export,
        ])
          StarBridgeMenuEntry(
            id: 'overlay-preset-${action.name}',
            label: _copy(
              context,
              action == _PresetAction.settings
                  ? 'overlay.source.presetSettings'
                  : 'overlay.workspace.${action.name}',
            ),
            onActivate:
                projection.busy ||
                    (action == _PresetAction.delete &&
                        snapshot.presets.length <= 1)
                ? null
                : (source) => _handleAction(context, action, source),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (action == _PresetAction.import) const Divider(),
                Text(
                  _copy(
                    context,
                    action == _PresetAction.settings
                        ? 'overlay.source.presetSettings'
                        : 'overlay.workspace.${action.name}',
                  ),
                ),
              ],
            ),
          ),
      ],
      builder: (context, controller, focus, toggle) => StarBridgeActionRow(
        key: const Key('overlay-preset-manage'),
        focusNode: focus,
        semanticLabel: label,
        onActivate: projection.busy ? null : (_, source) => toggle(source),
        child: ExcludeSemantics(child: child),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    _PresetAction action,
    InteractionSource source,
  ) async {
    if (!mounted || projection.busy) return;
    final snapshot = projection.snapshot!;
    switch (action) {
      case _PresetAction.settings:
        // The dialog rejects a plan changed while it is open; pending edits
        // save first so that check only reacts to changes made elsewhere.
        if (projection.dirty && !await module.save()) return;
        if (!context.mounted) return;
        await showStarBridgeDialog<void>(
          context,
          source: source,
          barrierDismissible: false,
          builder: (_) => OverlayPresetSettingsDialog(
            module: module,
            preset: _activePreset(module.projection.value.snapshot!),
            scenes: widget.scenes,
          ),
        );
        return;
      case _PresetAction.rename:
        await _nameAction(
          context,
          _copy(context, 'overlay.workspace.renameTitle'),
          (name) => module.renamePreset(
            snapshot.activePresetId!,
            _activePreset(snapshot).savedName(name, AppStrings.of(context)),
          ),
          initialName: _shown(_activePreset(snapshot)),
          source: source,
        );
        return;
      case _PresetAction.copy:
        await _nameAction(
          context,
          _copy(context, 'overlay.workspace.copyTitle'),
          (name) => module.duplicatePreset(snapshot.activePresetId!, name),
          source: source,
        );
        return;
      case _PresetAction.reset:
        if (await _confirm(
          context,
          _copy(context, 'overlay.workspace.resetConfirm'),
          source: source,
        )) {
          await module.resetPreset(snapshot.activePresetId!);
        }
        return;
      case _PresetAction.delete:
        if (await _confirm(
          context,
          _copy(context, 'overlay.workspace.deleteConfirm'),
          source: source,
        )) {
          await module.deletePreset(snapshot.activePresetId!);
        }
        return;
      case _PresetAction.import:
        if (widget.onImportSource case final callback?) {
          callback(source);
        } else {
          onImport();
        }
        return;
      case _PresetAction.export:
        if (widget.onExportSource case final callback?) {
          callback(source);
        } else {
          onExport();
        }
        return;
    }
  }

  static Future<void> _nameAction(
    BuildContext context,
    String title,
    Future<bool> Function(String name) action, {
    String initialName = '',
    required InteractionSource source,
  }) async {
    final controller = TextEditingController(text: initialName);
    final route = StarBridgeDialogRoute<String>(
      data:
          InteractionScope.maybeOf(context) ??
          resolveStarBridgeInteraction(context),
      link: InteractionScope.linkOf(context),
      instant: source == InteractionSource.keyboard,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: StarBridgeFieldFrame(
          builder: (context, focus) => TextField(
            controller: controller,
            focusNode: focus,
            maxLength: 24,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _copy(context, 'overlay.workspace.presetName'),
            ),
          ),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog<String>(context, source: source),
            child: Text(_copy(context, 'overlay.workspace.cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            onActivate: (source) => dismissStarBridgeDialog(
              context,
              source: source,
              result: controller.text,
            ),
            child: Text(_copy(context, 'overlay.workspace.confirm')),
          ),
        ],
      ),
    );
    final name = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) await action(name.trim());
  }

  static Future<bool> _confirm(
    BuildContext context,
    String message, {
    InteractionSource? source,
  }) async =>
      await showStarBridgeDialog<bool>(
        context,
        source: source,
        builder: (context) => AlertDialog(
          title: Text(_copy(context, 'overlay.workspace.confirmTitle')),
          content: Text(message),
          actions: [
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: false,
              ),
              child: Text(_copy(context, 'overlay.workspace.cancel')),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: true,
              ),
              child: Text(_copy(context, 'overlay.workspace.continue')),
            ),
          ],
        ),
      ) ??
      false;

  static OverlayWorkspacePreset _activePreset(
    OverlayWorkspaceSnapshot snapshot,
  ) => snapshot.presets.firstWhere(
    (preset) => preset.id == snapshot.activePresetId,
    orElse: () => snapshot.presets.first,
  );
}

enum _PresetAction { settings, rename, copy, reset, delete, import, export }

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
