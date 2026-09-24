import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/styles/overlay_appearance_preview.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/overlay_editor_window_port.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_schema.dart';

class OverlayWorkspaceAppearanceCenter extends StatefulWidget {
  const OverlayWorkspaceAppearanceCenter({
    required this.projection,
    required this.module,
    required this.onBack,
    super.key,
  });

  final OverlayWorkspaceProjection projection;
  final OverlayWorkspaceModule module;
  final VoidCallback onBack;

  @override
  State<OverlayWorkspaceAppearanceCenter> createState() =>
      _OverlayWorkspaceAppearanceCenterState();
}

class _OverlayWorkspaceAppearanceCenterState
    extends State<OverlayWorkspaceAppearanceCenter> {
  String? _selectedId;

  List<OverlayWorkspaceAppearance> get _publishedAppearances => widget
      .projection
      .snapshot!
      .appearances
      .where(
        (appearance) =>
            const {'Default', 'NightShadow', 'Verdict'}.contains(appearance.id),
      )
      .toList(growable: false);

  OverlayWorkspaceAppearance? get _selectedAppearance {
    final appearances = _publishedAppearances;
    if (appearances.isEmpty) return null;
    final currentId = widget.projection.settings!['skin'] as String;
    final selectedId = _selectedId ?? currentId;
    return appearances.cast<OverlayWorkspaceAppearance?>().firstWhere(
      (appearance) => appearance?.id == selectedId,
      orElse: () => appearances.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = widget.projection.snapshot!;
    final activePreset = snapshot.presets.singleWhere(
      (preset) => preset.id == snapshot.activePresetId,
    );
    final appearanceFields = overlayWorkspaceFieldSpecs
        .where(
          (field) =>
              field.group == 'appearance' &&
              field.field != 'skin' &&
              field.field != 'opacity',
        )
        .toList(growable: false);
    return SingleChildScrollView(
      key: const Key('overlay-appearance-center'),
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        104,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppearanceHeader(
            presetName: activePreset.name,
            onBack: widget.onBack,
          ),
          SizedBox(height: tokens.space.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final catalog = _AppearanceCatalog(
                editorWindow: widget.module.editorWindow,
                appearances: _publishedAppearances,
                currentId: widget.projection.settings!['skin'] as String,
                selectedId: _selectedAppearance?.id,
                onSelected: (id) => setState(() => _selectedId = id),
              );
              final details = _AppearanceDetails(
                appearance: _selectedAppearance,
                currentId: widget.projection.settings!['skin'] as String,
                busy: widget.projection.busy,
                onApply: (appearance) {
                  widget.module.updateSetting('skin', appearance.id);
                  setState(() => _selectedId = appearance.id);
                },
                settings: OverlayWorkspaceSettingsGroup(
                  group: 'appearance',
                  fields: appearanceFields,
                  settings: widget.projection.settings!,
                  appearances: _publishedAppearances,
                  onChanged: widget.module.updateSetting,
                ),
              );
              if (constraints.maxWidth < 1120) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    catalog,
                    SizedBox(height: tokens.space.md),
                    details,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: catalog),
                  SizedBox(width: tokens.space.lg),
                  SizedBox(width: 420, child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AppearanceHeader extends StatelessWidget {
  const _AppearanceHeader({required this.presetName, required this.onBack});

  final String presetName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          key: const Key('overlay-appearance-center-back'),
          onPressed: onBack,
          tooltip: _copy(context, 'overlay.workspace.appearance.back'),
          icon: const StarBridgeIcon(
            StarBridgeIconSemantic.forward,
            textDirection: TextDirection.rtl,
          ),
        ),
        SizedBox(width: tokens.space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StarBridgeIcon(
                    StarBridgeIconSemantic.marketplace,
                    size: tokens.icons.medium,
                    color: tokens.colors.accent,
                  ),
                  SizedBox(width: tokens.space.sm),
                  Text(
                    _copy(context, 'overlay.workspace.appearance.centerTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                _copy(
                  context,
                  'overlay.workspace.appearance.centerDescription',
                ),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                _copy(
                  context,
                  'overlay.workspace.appearance.forPreset',
                ).replaceAll('{name}', presetName),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceCatalog extends StatelessWidget {
  const _AppearanceCatalog({
    required this.editorWindow,
    required this.appearances,
    required this.currentId,
    required this.selectedId,
    required this.onSelected,
  });

  final List<OverlayWorkspaceAppearance> appearances;
  final OverlayEditorWindowPort editorWindow;
  final String currentId;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _copy(context, 'overlay.workspace.appearance.catalog'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            _copy(context, 'overlay.workspace.appearance.catalogHelp'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 680
                  ? (constraints.maxWidth - tokens.space.md) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: tokens.space.md,
                runSpacing: tokens.space.md,
                children: appearances
                    .map(
                      (appearance) => SizedBox(
                        width: cardWidth,
                        child: _AppearanceCard(
                          editorWindow: editorWindow,
                          appearance: appearance,
                          previewableIds: appearances
                              .where((item) => item.isPreviewAvailable)
                              .map((item) => item.id)
                              .toSet(),
                          selected: selectedId == appearance.id,
                          current: currentId == appearance.id,
                          onPressed: () => onSelected(appearance.id),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.editorWindow,
    required this.appearance,
    required this.previewableIds,
    required this.selected,
    required this.current,
    required this.onPressed,
  });

  final OverlayWorkspaceAppearance appearance;
  final Set<String> previewableIds;
  final OverlayEditorWindowPort editorWindow;
  final bool selected;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final locale = Localizations.localeOf(context);
    final english = locale.languageCode == 'en';
    final name = english ? appearance.displayNameEn : appearance.displayNameZh;
    final summary = english ? appearance.summaryEn : appearance.summaryZh;
    return Material(
      color: selected
          ? tokens.colors.accent.withValues(alpha: 0.08)
          : tokens.surfaces.ground.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? tokens.colors.accent : tokens.surfaces.panel.border,
          width: selected ? tokens.stroke.strong : tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.medium,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('overlay-appearance-card-${appearance.id}'),
        onTap: onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!appearance.isPreviewAvailable)
              _UnavailableAppearanceSpecimen(appearanceId: appearance.id)
            else
              OverlayAppearancePreview(
                editorWindow: editorWindow,
                key: Key('overlay-appearance-specimen-${appearance.id}'),
                appearanceId: appearance.id,
                previewableIds: previewableIds,
              ),
            Padding(
              padding: EdgeInsets.all(tokens.space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _AvailabilityBadge(
                        released: appearance.isReleased,
                        previewAvailable: appearance.isPreviewAvailable,
                        available: appearance.isAvailable,
                        current: current,
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.space.xs),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
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

class _UnavailableAppearanceSpecimen extends StatelessWidget {
  const _UnavailableAppearanceSpecimen({required this.appearanceId});

  final String appearanceId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      key: Key('overlay-appearance-preview-unavailable-$appearanceId'),
      height: 210,
      child: ColoredBox(
        color: tokens.surfaces.ground.fill,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.statusIdentity,
                size: tokens.icons.medium,
                color: tokens.colors.textDisabled,
              ),
              SizedBox(height: tokens.space.sm),
              Text(
                _copy(
                  context,
                  'overlay.workspace.appearance.previewUnavailable',
                ),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({
    required this.released,
    required this.previewAvailable,
    required this.available,
    required this.current,
  });

  final bool released;
  final bool previewAvailable;
  final bool available;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = current
        ? tokens.colors.accent
        : !released
        ? tokens.colors.textSecondary
        : available
        ? tokens.colors.success
        : tokens.colors.warning;
    final text = current
        ? _copy(context, 'overlay.workspace.appearance.inUse')
        : !released
        ? _copy(
            context,
            previewAvailable
                ? 'overlay.workspace.appearance.previewOnly'
                : 'overlay.workspace.appearance.inDevelopment',
          )
        : available
        ? _copy(context, 'overlay.workspace.appearance.available')
        : _copy(context, 'overlay.workspace.appearance.requiresQualification');
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

class _AppearanceDetails extends StatelessWidget {
  const _AppearanceDetails({
    required this.appearance,
    required this.currentId,
    required this.busy,
    required this.onApply,
    required this.settings,
  });

  final OverlayWorkspaceAppearance? appearance;
  final String currentId;
  final bool busy;
  final ValueChanged<OverlayWorkspaceAppearance> onApply;
  final Widget settings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selected = appearance;
    if (selected == null) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context);
    final english = locale.languageCode == 'en';
    final name = english ? selected.displayNameEn : selected.displayNameZh;
    final traits = english ? selected.traitsEn : selected.traitsZh;
    final current = currentId == selected.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StarBridgeSurface(
          role: SurfaceRole.raised,
          padding: EdgeInsets.all(tokens.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: tokens.space.sm),
              Wrap(
                spacing: tokens.space.xs,
                runSpacing: tokens.space.xs,
                children: traits
                    .take(3)
                    .map((trait) => Chip(label: Text(trait)))
                    .toList(growable: false),
              ),
              SizedBox(height: tokens.space.md),
              _DetailLine(
                label: _copy(context, 'overlay.workspace.appearance.palette'),
                value: selected.locksTheme
                    ? _copy(
                        context,
                        'overlay.workspace.appearance.fixedPaletteShort',
                      )
                    : _copy(
                        context,
                        'overlay.workspace.appearance.flexiblePalette',
                      ),
              ),
              SizedBox(height: tokens.space.sm),
              _DetailLine(
                label: _copy(
                  context,
                  'overlay.workspace.appearance.transition',
                ),
                value: _copy(
                  context,
                  'overlay.workspace.option.${selected.startupTransition}',
                ),
              ),
              SizedBox(height: tokens.space.md),
              FilledButton(
                key: Key('overlay-appearance-apply-${selected.id}'),
                onPressed:
                    busy ||
                        current ||
                        !selected.isReleased ||
                        !selected.isAvailable
                    ? null
                    : () => onApply(selected),
                child: Text(
                  current
                      ? _copy(context, 'overlay.workspace.appearance.inUse')
                      : !selected.isReleased
                      ? _copy(
                          context,
                          'overlay.workspace.appearance.notReleased',
                        )
                      : selected.isAvailable
                      ? _copy(context, 'overlay.workspace.appearance.apply')
                      : _copy(
                          context,
                          'overlay.workspace.appearance.normalAccountLocked',
                        ),
                ),
              ),
            ],
          ),
        ),
        if (current) ...[SizedBox(height: tokens.space.md), settings],
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ),
        SizedBox(width: tokens.space.md),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    );
  }
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
