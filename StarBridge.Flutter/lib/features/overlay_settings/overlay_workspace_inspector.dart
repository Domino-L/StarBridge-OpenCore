import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_geometry_fields.dart';

class OverlayWorkspaceLayoutInspector extends StatelessWidget {
  const OverlayWorkspaceLayoutInspector({
    required this.item,
    required this.nudgePixels,
    required this.onChanged,
    this.embedded = false,
    this.layoutLocked = false,
    this.presetId = 'preset1',
    this.surfaceSize = OverlayWorkspaceLayoutGeometry.referenceSize,
    super.key,
  });

  final OverlayWorkspaceLayoutItem item;
  final double nudgePixels;
  final bool embedded;
  final bool layoutLocked;
  final String presetId;
  final Size surfaceSize;
  final void Function(OverlayWorkspaceLayoutItem item, bool coalesce) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isNotice = item.key == 'Notice';
    final noticeDock =
        isNotice &&
            OverlayWorkspaceLayoutGeometry.resolve(
                  item,
                  surfaceSize: surfaceSize,
                ).center.dy >=
                surfaceSize.height / 2
        ? 'Bottom'
        : 'Top';
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              embedded
                  ? _copy(context, 'overlay.workspace.layout.lockPositionSize')
                  : _moduleName(context, item.key),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Text(
              _copy(
                context,
                (item.isLocked || layoutLocked)
                    ? 'overlay.workspace.layout.locked'
                    : 'overlay.workspace.layout.adjustable',
              ),
            ),
            value: item.isLocked,
            onChanged: (value) =>
                onChanged(item.copyWith(isLocked: value), false),
          ),
        ),
        Wrap(
          spacing: tokens.space.sm,
          runSpacing: tokens.space.sm,
          children: [
            _anchorField(
              context,
              key: 'overlay-layout-horizontal-anchor-${item.key}',
              labelKey: 'overlay.workspace.layout.horizontalAnchor',
              value: item.horizontalAnchor,
              values: const ['Left', 'Center', 'Right'],
              onChanged: (item.isLocked || layoutLocked)
                  ? null
                  : (value) => onChanged(
                      item.copyWith(horizontalAnchor: value),
                      false,
                    ),
            ),
            _anchorField(
              context,
              key: 'overlay-layout-vertical-anchor-${item.key}',
              labelKey: 'overlay.workspace.layout.verticalAnchor',
              value: isNotice ? noticeDock : item.verticalAnchor,
              values: isNotice
                  ? const ['Top', 'Bottom']
                  : const ['Top', 'Middle', 'Bottom'],
              onChanged: (item.isLocked || layoutLocked)
                  ? null
                  : (value) => onChanged(
                      isNotice
                          ? OverlayWorkspaceLayoutGeometry.dockNotice(
                              item,
                              value,
                              surfaceSize: surfaceSize,
                            )
                          : item.copyWith(verticalAnchor: value),
                      false,
                    ),
            ),
          ],
        ),
        if (isNotice) ...[
          SizedBox(height: tokens.space.xs),
          Text(
            _copy(context, 'overlay.workspace.layout.noticeDockHelp'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        SizedBox(height: tokens.space.sm),
        _nudgeControls(context),
        SizedBox(height: tokens.space.md),
        OverlayWorkspaceGeometryFields(
          item: item,
          surfaceSize: surfaceSize,
          enabled: !item.isLocked && !layoutLocked,
          onChanged: (value) => onChanged(value, false),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: Key('overlay-layout-reset-${item.key}'),
            onPressed: item.isLocked || layoutLocked
                ? null
                : () => onChanged(
                    OverlayWorkspaceLayoutGeometry.resetPosition(
                      item,
                      presetId,
                    ),
                    false,
                  ),
            child: Text(_copy(context, 'overlay.editor.resetPosition')),
          ),
        ),
        _layoutSlider(
          _copy(context, 'overlay.workspace.layout.x'),
          item.x,
          (item.isLocked || layoutLocked)
              ? null
              : (value) => onChanged(item.copyWith(x: value), true),
        ),
        if (!isNotice)
          _layoutSlider(
            _copy(context, 'overlay.workspace.layout.y'),
            item.y,
            (item.isLocked || layoutLocked)
                ? null
                : (value) => onChanged(item.copyWith(y: value), true),
          ),
        _layoutSlider(
          _copy(context, 'overlay.workspace.layout.width'),
          item.width,
          (item.isLocked || layoutLocked)
              ? null
              : (value) => onChanged(item.copyWith(width: value), true),
          minimum: 0.05,
        ),
        _layoutSlider(
          _copy(context, 'overlay.workspace.layout.height'),
          item.height,
          (item.isLocked || layoutLocked)
              ? null
              : (value) => onChanged(item.copyWith(height: value), true),
          minimum: 0.05,
        ),
        _layoutSlider(
          _copy(context, 'overlay.workspace.layout.textOpacity'),
          item.textOpacity,
          (value) => onChanged(item.copyWith(textOpacity: value), true),
          key: Key('overlay-layout-text-opacity-${item.key}'),
          minimum: 0.15,
        ),
        _layoutSlider(
          _copy(context, 'overlay.workspace.layout.backgroundOpacity'),
          item.backgroundOpacity,
          (value) => onChanged(item.copyWith(backgroundOpacity: value), true),
          key: Key('overlay-layout-background-opacity-${item.key}'),
        ),
        _layoutSlider(
          _copy(context, 'overlay.workspace.layout.decorationOpacity'),
          item.decorationOpacity,
          (value) => onChanged(item.copyWith(decorationOpacity: value), true),
          key: Key('overlay-layout-decoration-opacity-${item.key}'),
        ),
      ],
    );
    if (embedded) return content;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: content,
    );
  }

  Widget _nudgeControls(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _nudgeButton(context, 'left', 'x', -nudgePixels),
      _nudgeButton(context, 'right', 'x', nudgePixels),
      if (item.key != 'Notice') ...[
        _nudgeButton(context, 'up', 'y', -nudgePixels),
        _nudgeButton(context, 'down', 'y', nudgePixels),
      ],
      _nudgeButton(context, 'narrower', 'width', -nudgePixels),
      _nudgeButton(context, 'wider', 'width', nudgePixels),
      _nudgeButton(context, 'shorter', 'height', -nudgePixels),
      _nudgeButton(context, 'taller', 'height', nudgePixels),
    ],
  );

  Widget _nudgeButton(
    BuildContext context,
    String action,
    String property,
    double delta,
  ) => OutlinedButton(
    key: Key('overlay-layout-nudge-$action-${item.key}'),
    onPressed: (item.isLocked || layoutLocked)
        ? null
        : () => onChanged(
            OverlayWorkspaceLayoutGeometry.nudge(
              item,
              property,
              delta,
              surfaceSize: surfaceSize,
            ),
            false,
          ),
    child: Text(_copy(context, 'overlay.workspace.layout.$action')),
  );

  static Widget _anchorField(
    BuildContext context, {
    required String key,
    required String labelKey,
    required String value,
    required List<String> values,
    required ValueChanged<String>? onChanged,
  }) => SizedBox(
    width: 240,
    child: DropdownButtonFormField<String>(
      key: Key(key),
      initialValue: value,
      decoration: InputDecoration(labelText: _copy(context, labelKey)),
      items: values
          .map(
            (entry) => DropdownMenuItem(
              value: entry,
              child: Text(_anchorName(context, entry)),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged == null
          ? null
          : (entry) {
              if (entry != null) onChanged(entry);
            },
    ),
  );

  static Widget _layoutSlider(
    String label,
    double value,
    ValueChanged<double>? onChanged, {
    Key? key,
    double minimum = 0,
  }) => Row(
    key: key,
    children: [
      SizedBox(width: 140, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(minimum, 1),
          min: minimum,
          max: 1,
          divisions: 100,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
String _moduleName(BuildContext context, String key) =>
    _copy(context, 'overlay.workspace.module.$key');
String _anchorName(BuildContext context, String value) =>
    _copy(context, 'overlay.workspace.anchor.$value');
