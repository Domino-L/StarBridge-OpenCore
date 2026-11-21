import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_slider.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_visor_layout.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_geometry_fields.dart';

class OverlayWorkspaceLayoutInspector extends StatelessWidget {
  const OverlayWorkspaceLayoutInspector({
    required this.item,
    required this.nudgePixels,
    required this.onChanged,
    this.embedded = false,
    this.positionOnly = false,
    this.layoutLocked = false,
    this.presetId = 'preset1',
    this.surfaceSize = OverlayWorkspaceLayoutGeometry.referenceSize,
    this.settings,
    super.key,
  });

  final OverlayWorkspaceLayoutItem item;
  final double nudgePixels;
  final bool embedded;

  /// Position only: the lock and the opacities are in the block's look
  /// controls below it (the full-screen tools, laid out as the settings page,
  /// 11-13 user 请你定 3).
  final bool positionOnly;
  final bool layoutLocked;
  final String presetId;
  final Size surfaceSize;
  final void Function(OverlayWorkspaceLayoutItem item, bool coalesce) onChanged;

  /// The preset's settings: with the visor appearance its blocks keep the
  /// S/M/L size (no size controls) and the overview has no block of its own.
  final OverlayWorkspaceSettings? settings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final settings = this.settings;
    if (settings != null &&
        OverlayVisorLayout.mergedIntoMembers(settings, item.key)) {
      final note = Text(
        _copy(context, 'overlay.workspace.layout.visorOverview'),
        key: Key('overlay-layout-visor-overview-${item.key}'),
        style: Theme.of(context).textTheme.bodySmall,
      );
      return embedded
          ? note
          : StarBridgeSurface(
              role: SurfaceRole.panel,
              padding: EdgeInsets.all(tokens.space.md),
              child: note,
            );
    }
    final sized =
        settings == null || !OverlayVisorLayout.fixedSize(settings, item.key);
    final isNotice = item.key == 'Notice';
    // 11-11 user ("主程序编辑器去掉没用的控件"): on the visor the rally is
    // always centred (top or bottom only), and a moved block is anchored to
    // the screen half it is in when saved, so those controls do nothing there
    final visor = settings != null && OverlayVisorLayout.active(settings);
    final visorRally = visor && isNotice;
    final noticeDock =
        isNotice &&
            OverlayWorkspaceLayoutGeometry.resolve(
                  item,
                  surfaceSize: surfaceSize,
                ).center.dy >=
                surfaceSize.height / 2
        ? 'Bottom'
        : 'Top';
    final state = _copy(
      context,
      (item.isLocked || layoutLocked)
          ? 'overlay.workspace.layout.locked'
          : sized
          ? 'overlay.workspace.layout.adjustable'
          : 'overlay.workspace.layout.visorPositionOnly',
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // the lock switch is with the block's look below; what can be moved
        // here is still said
        if (positionOnly)
          Text(state, style: Theme.of(context).textTheme.bodySmall)
        else
          Material(
            type: MaterialType.transparency,
            child: StarBridgeSwitch.tile(
              preserveNativeTile: true,
              controlKey: Key('overlay-layout-lock-${item.key}'),
              label: embedded
                  ? _copy(context, 'overlay.workspace.layout.lockPositionSize')
                  : _moduleName(context, item.key),
              titleWidget: Text(
                embedded
                    ? _copy(
                        context,
                        'overlay.workspace.layout.lockPositionSize',
                      )
                    : _moduleName(context, item.key),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: state,
              value: item.isLocked,
              onChanged: (value) =>
                  onChanged(item.copyWith(isLocked: value), false),
            ),
          ),
        if (!visor || isNotice)
          Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.sm,
            children: [
              if (!visor)
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
        _nudgeControls(context, sized, horizontal: !visorRally),
        SizedBox(height: tokens.space.md),
        if (!visorRally)
          OverlayWorkspaceGeometryFields(
            item: item,
            surfaceSize: surfaceSize,
            showSize: sized,
            enabled: !item.isLocked && !layoutLocked,
            onChanged: (value) => onChanged(value, false),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: Key('overlay-layout-reset-${item.key}'),
            onActivate: item.isLocked || layoutLocked
                ? null
                : (_) => onChanged(
                    OverlayVisorLayout.resetPosition(item, presetId, settings),
                    false,
                  ),
            child: Text(_copy(context, 'overlay.editor.resetPosition')),
          ),
        ),
        if (!visorRally)
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
        if (sized) ...[
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
        ],
        if (!positionOnly) ...[
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
      ],
    );
    if (embedded) return content;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: content,
    );
  }

  Widget _nudgeControls(
    BuildContext context,
    bool sized, {
    bool horizontal = true,
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (horizontal) ...[
        _nudgeButton(context, 'left', 'x', -nudgePixels),
        _nudgeButton(context, 'right', 'x', nudgePixels),
      ],
      if (item.key != 'Notice') ...[
        _nudgeButton(context, 'up', 'y', -nudgePixels),
        _nudgeButton(context, 'down', 'y', nudgePixels),
      ],
      if (sized) ...[
        _nudgeButton(context, 'narrower', 'width', -nudgePixels),
        _nudgeButton(context, 'wider', 'width', nudgePixels),
        _nudgeButton(context, 'shorter', 'height', -nudgePixels),
        _nudgeButton(context, 'taller', 'height', nudgePixels),
      ],
    ],
  );

  Widget _nudgeButton(
    BuildContext context,
    String action,
    String property,
    double delta,
  ) => StarBridgeActionButton(
    controlKey: Key('overlay-layout-nudge-$action-${item.key}'),
    onActivate: (item.isLocked || layoutLocked)
        ? null
        : (_) => onChanged(
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
    child: StarBridgeSelectFormField<String>(
      key: Key(key),
      identity: key,
      controlKey: ValueKey('$key-command'),
      semanticLabel: _copy(context, labelKey),
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
        child: StarBridgeSlider(
          semanticLabel: label,
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
