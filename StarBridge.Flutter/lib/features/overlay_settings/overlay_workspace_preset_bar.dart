import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/styles/approved_appearance_thumbnail.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

class OverlayWorkspacePresetBar extends StatefulWidget {
  const OverlayWorkspacePresetBar({
    required this.projection,
    required this.module,
    required this.onImport,
    required this.onExport,
    required this.onOpenAppearance,
    super.key,
  });

  final OverlayWorkspaceProjection projection;
  final OverlayWorkspaceModule module;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onOpenAppearance;

  @override
  State<OverlayWorkspacePresetBar> createState() =>
      _OverlayWorkspacePresetBarState();
}

class _OverlayWorkspacePresetBarState extends State<OverlayWorkspacePresetBar> {
  late final TextEditingController _nameController;
  late String _boundPresetId;
  late String _boundPresetName;

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
    _nameController = TextEditingController(text: preset.name);
  }

  @override
  void didUpdateWidget(covariant OverlayWorkspacePresetBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preset = _activePreset(projection.snapshot!);
    if (preset.id != _boundPresetId ||
        (preset.name != _boundPresetName &&
            _nameController.text == _boundPresetName)) {
      _boundPresetId = preset.id;
      _boundPresetName = preset.name;
      _nameController.value = TextEditingValue(
        text: preset.name,
        selection: TextSelection.collapsed(offset: preset.name.length),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = projection.snapshot!;
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
                    child: _QuickPresetCard(
                      preset: preset,
                      selected: preset.id == snapshot.activePresetId,
                      enabled: !projection.busy,
                      onPressed: () => _activatePreset(context, preset.id),
                    ),
                  ),
                ),
                _AddPresetCard(
                  enabled: !projection.busy,
                  onPressed: () => _createPreset(context),
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
                    child: _PresetNameEditor(
                      controller: _nameController,
                      currentName: _boundPresetName,
                      enabled: !projection.busy,
                      onSave: _renameCurrentPreset,
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  PopupMenuButton<_PresetAction>(
                    key: const Key('overlay-preset-manage'),
                    enabled: !projection.busy,
                    tooltip: _copy(context, 'overlay.workspace.managePresets'),
                    onSelected: (action) => _handleAction(context, action),
                    itemBuilder: (context) => [
                      _menuItem(context, _PresetAction.copy),
                      _menuItem(context, _PresetAction.reset),
                      _menuItem(
                        context,
                        _PresetAction.delete,
                        enabled: snapshot.presets.length > 1,
                      ),
                      const PopupMenuDivider(),
                      _menuItem(context, _PresetAction.import),
                      _menuItem(context, _PresetAction.export),
                    ],
                    child: Container(
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
              final appearance = _AppearanceEntry(
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

  Future<void> _activatePreset(BuildContext context, String presetId) async {
    final snapshot = projection.snapshot!;
    if (presetId == snapshot.activePresetId || projection.busy) return;
    if (projection.dirty &&
        !await _confirm(
          context,
          _copy(context, 'overlay.workspace.switchConfirm'),
        )) {
      return;
    }
    await module.activatePreset(presetId);
  }

  Future<void> _createPreset(BuildContext context) async {
    if (projection.busy) return;
    final defaultName = _copy(context, 'overlay.workspace.newPresetName');
    if (projection.dirty &&
        !await _confirm(
          context,
          _copy(context, 'overlay.workspace.switchConfirm'),
        )) {
      return;
    }
    await module.createPreset(defaultName);
  }

  Future<void> _renameCurrentPreset() async {
    if (projection.busy) return;
    final name = _nameController.text.trim();
    if (name.isEmpty || name == _boundPresetName) return;
    final renamed = await module.renamePreset(_boundPresetId, name);
    if (!mounted) return;
    if (renamed) {
      setState(() {
        _boundPresetName = name;
        _nameController.value = TextEditingValue(
          text: name,
          selection: TextSelection.collapsed(offset: name.length),
        );
      });
    }
  }

  PopupMenuItem<_PresetAction> _menuItem(
    BuildContext context,
    _PresetAction action, {
    bool enabled = true,
  }) => PopupMenuItem(
    value: action,
    enabled: enabled,
    child: Text(_copy(context, 'overlay.workspace.${action.name}')),
  );

  Future<void> _handleAction(BuildContext context, _PresetAction action) async {
    final snapshot = projection.snapshot!;
    switch (action) {
      case _PresetAction.copy:
        await _nameAction(
          context,
          _copy(context, 'overlay.workspace.copyTitle'),
          (name) => module.duplicatePreset(snapshot.activePresetId!, name),
        );
        return;
      case _PresetAction.reset:
        if (await _confirm(
          context,
          _copy(context, 'overlay.workspace.resetConfirm'),
        )) {
          await module.resetPreset(snapshot.activePresetId!);
        }
        return;
      case _PresetAction.delete:
        if (await _confirm(
          context,
          _copy(context, 'overlay.workspace.deleteConfirm'),
        )) {
          await module.deletePreset(snapshot.activePresetId!);
        }
        return;
      case _PresetAction.import:
        onImport();
        return;
      case _PresetAction.export:
        onExport();
        return;
    }
  }

  static Future<void> _nameAction(
    BuildContext context,
    String title,
    Future<bool> Function(String name) action,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 24,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _copy(context, 'overlay.workspace.presetName'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_copy(context, 'overlay.workspace.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_copy(context, 'overlay.workspace.confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) await action(name.trim());
  }

  static Future<bool> _confirm(BuildContext context, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_copy(context, 'overlay.workspace.confirmTitle')),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_copy(context, 'overlay.workspace.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
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

class _AppearanceEntry extends StatelessWidget {
  const _AppearanceEntry({required this.projection, required this.onPressed});

  final OverlayWorkspaceProjection projection;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = projection.snapshot!;
    final skin = projection.settings!['skin'] as String;
    final appearance = snapshot.appearances
        .cast<OverlayWorkspaceAppearance?>()
        .firstWhere(
          (entry) => entry?.id == skin,
          orElse: () =>
              snapshot.appearances.isEmpty ? null : snapshot.appearances.first,
        );
    final locale = Localizations.localeOf(context);
    final english = locale.languageCode == 'en';
    final name = appearance == null
        ? _copy(context, 'overlay.workspace.appearance.unknown')
        : english
        ? appearance.displayNameEn
        : appearance.displayNameZh;
    final status = appearance?.isAvailable == false
        ? _copy(context, 'overlay.workspace.appearance.requiresQualification')
        : _copy(context, 'overlay.workspace.appearance.available');
    final statusColor = appearance?.isAvailable == false
        ? tokens.colors.warning
        : tokens.colors.success;
    return SizedBox(
      height: tokens.density.controlHeight + tokens.space.sm,
      child: Material(
        color: tokens.surfaces.ground.fill,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.surfaces.panel.border),
          borderRadius: tokens.shape.small,
        ),
        child: InkWell(
          key: const Key('overlay-appearance-center-entry'),
          onTap: onPressed,
          borderRadius: tokens.shape.small,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
            child: Row(
              children: [
                ApprovedAppearanceThumbnail(skinId: skin),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _copy(context, 'overlay.workspace.appearance.current'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: tokens.colors.textSecondary),
                      ),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: tokens.space.sm),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: statusColor),
                ),
                SizedBox(width: tokens.space.xs),
                StarBridgeIcon(
                  StarBridgeIconSemantic.forward,
                  size: tokens.icons.small,
                  color: tokens.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PresetAction { copy, reset, delete, import, export }

class _PresetNameEditor extends StatelessWidget {
  const _PresetNameEditor({
    required this.controller,
    required this.currentName,
    required this.enabled,
    required this.onSave,
  });

  final TextEditingController controller;
  final String currentName;
  final bool enabled;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final name = value.text.trim();
        final canSave = enabled && name.isNotEmpty && name != currentName;
        return TextField(
          key: const Key('overlay-active-preset-name'),
          controller: controller,
          enabled: enabled,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          onSubmitted: canSave ? (_) => onSave() : null,
          decoration: InputDecoration(
            labelText: _copy(context, 'overlay.workspace.currentPresetName'),
            isDense: true,
            counterText: '',
            suffixIconConstraints: const BoxConstraints(minHeight: 40),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _copy(context, 'overlay.workspace.renamePresetHint'),
                  key: const Key('overlay-preset-name-save-hint'),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.colors.textDisabled),
                ),
                IconButton(
                  key: const Key('overlay-active-preset-rename'),
                  tooltip: _copy(context, 'overlay.workspace.savePresetName'),
                  onPressed: canSave ? onSave : null,
                  icon: StarBridgeIcon(
                    StarBridgeIconSemantic.save,
                    size: tokens.icons.small,
                    color: canSave
                        ? tokens.colors.accent
                        : tokens.colors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddPresetCard extends StatelessWidget {
  const _AddPresetCard({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surfaces.ground.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: enabled
              ? tokens.colors.accent.withValues(alpha: 0.72)
              : tokens.colors.textDisabled,
        ),
        borderRadius: tokens.shape.medium,
      ),
      child: InkWell(
        key: const Key('overlay-add-preset'),
        onTap: enabled ? onPressed : null,
        borderRadius: tokens.shape.medium,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.md,
            vertical: tokens.space.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.add,
                size: tokens.icons.small,
                color: enabled
                    ? tokens.colors.accent
                    : tokens.colors.textDisabled,
              ),
              SizedBox(width: tokens.space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _copy(context, 'overlay.workspace.addPreset'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    _copy(context, 'overlay.workspace.addPresetDefault'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPresetCard extends StatelessWidget {
  const _QuickPresetCard({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final OverlayWorkspacePreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scene = preset.settings['scenePreference'] as String;
    return Material(
      color: selected
          ? tokens.colors.accent.withValues(alpha: 0.14)
          : tokens.surfaces.ground.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? tokens.colors.accent : tokens.surfaces.panel.border,
        ),
        borderRadius: tokens.shape.medium,
      ),
      child: InkWell(
        key: Key('overlay-quick-preset-${preset.id}'),
        onTap: enabled ? onPressed : null,
        borderRadius: tokens.shape.medium,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.md,
            vertical: tokens.space.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? tokens.colors.accent : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? tokens.colors.accent
                        : tokens.colors.textSecondary,
                    width: tokens.stroke.regular,
                  ),
                ),
              ),
              SizedBox(width: tokens.space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    _copy(context, 'overlay.workspace.option.$scene'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
