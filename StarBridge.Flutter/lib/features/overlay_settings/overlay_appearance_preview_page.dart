import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_color_picker.dart';

import 'overlay_workspace_controls.dart';
import 'overlay_workspace_models.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';

import 'overlay_workspace_rules.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

import 'overlay_appearance_live_session.dart';
import 'overlay_appearance_preview_status.dart';
import 'overlay_appearance_preview_playback_controls.dart';
import 'overlay_appearance_preview_guide_card.dart';
import 'overlay_appearance_try_on_selector.dart';
import 'overlay_appearance_preview_copy.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';

export 'overlay_appearance_preview_route.dart';

/// An inspector over an actual Native surface. There is deliberately no canvas
/// or scaled module renderer in this Widget. Save remains the workspace flow.
class OverlayAppearancePreviewPage extends StatefulWidget {
  const OverlayAppearancePreviewPage({
    required this.module,
    required this.port,
    required this.appearanceId,
    this.readOnly = false,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayAppearanceLivePort port;
  final String appearanceId;

  /// First-use inspection reuses the same Native session, protection and close
  /// path, without exposing configuration or persistence controls.
  final bool readOnly;
  @override
  State<OverlayAppearancePreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<OverlayAppearancePreviewPage>
    with WidgetsBindingObserver {
  late final OverlayAppearanceLiveSession _session;
  late String _skin;
  String? _lastFrame;
  bool _started = false, _left = false, _collapsed = false;
  bool _moving = false, _leaving = false, _canPop = false;
  bool _reducePreviewMotion = false;
  bool _guideVisible = false, _guideBusy = false;
  StarBridgeDialogRoute<String>? _colorRoute;
  OverlayWorkspaceSnapshot? _colorSnapshot;
  String? _playbackStatus;
  Object? _presentationFailure;
  Size _size = Size.zero;
  bool get _liveSession =>
      _session.hasSession &&
      (_session.phase == OverlayAppearanceLivePhase.live ||
          _session.phase == OverlayAppearanceLivePhase.updating);
  bool get _editable =>
      _liveSession &&
      !_leaving &&
      !_moving &&
      !_guideBusy &&
      !_session.playbackBusy &&
      !widget.module.projection.value.busy;
  String _copy(String cn, String tw, String en) =>
      overlayAppearancePreviewText(context, cn, tw, en);

  String _fieldName(String field) =>
      overlayAppearancePreviewFieldName(context, field);

  double get _top =>
      56 * math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
  double get _bottom =>
      40 * math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
  double get _panelWidth => math.min(360, math.max(240, _size.width - 16));
  double get _barWidth => math.max(1.0, math.min(600, _size.width - 24));
  double get _guideBottom => 20 + _bottom + _top;
  double get _guideHeight => math.max(
    0,
    math.min(
      240 * math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14),
      _size.height - _guideBottom - 8,
    ),
  );
  double get _guideWidth => math.min(480, _barWidth);
  List<OverlayPreviewControlArea> _areas({
    bool? left,
    bool? collapsed,
    bool? guide,
  }) {
    if (_size.isEmpty) return [const OverlayPreviewControlArea(0, 0, 1, 1)];
    final barHeight = math.min(_top + _bottom + 52, _size.height);
    final width = math.min(_panelWidth / _size.width, 1.0);
    return [
      // Leave top-center notices visible. Extra upper clearance protects
      // keyboard/hover tooltips around the compact bottom-center controls.
      OverlayPreviewControlArea(
        (_size.width - _barWidth) / 2 / _size.width,
        1 - barHeight / _size.height,
        _barWidth / _size.width,
        barHeight / _size.height,
      ),
      if (!(collapsed ?? _collapsed))
        OverlayPreviewControlArea((left ?? _left) ? 0 : 1 - width, 0, width, 1),
      if ((guide ?? _guideVisible) && _guideHeight > 0)
        OverlayPreviewControlArea(
          (_size.width - _guideWidth) / 2 / _size.width,
          (_size.height - _guideBottom - _guideHeight) / _size.height,
          _guideWidth / _size.width,
          _guideHeight / _size.height,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _skin = widget.appearanceId;
    _collapsed = widget.readOnly;
    _session = OverlayAppearanceLiveSession(widget.port)..addListener(_changed);
    widget.module.projection.addListener(_draftChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_start());
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _draftChanged();
      });
    }
  }

  OverlayAppearanceLiveFrame _frame() {
    final p = widget.module.projection.value;
    if (!p.available) throw StateError('Workspace unavailable.');
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode != 'zh'
        ? 'en'
        : locale.scriptCode == 'Hant' ||
              const {'TW', 'HK'}.contains(locale.countryCode)
        ? 'zh-Hant'
        : 'zh-CN';
    return OverlayAppearanceLiveFrame(
      appearanceId: _skin,
      settings: p.settings!,
      layout: p.layout,
      options: p.appearanceOptions,
      language: language,
      reduceMotion:
          _reducePreviewMotion ||
          resolveStarBridgeInteraction(context).reduceMotion ||
          p.settings!['animationFrameRate'] == 'Off',
    );
  }

  Future<void> _start() async {
    try {
      final frame = _frame();
      _lastFrame = jsonEncode(frame.toMap());
      await _session.open(frame);
      if (!mounted || !_session.hasSession) return;
      await _session.protectControls(_areas());
      if (!widget.readOnly) unawaited(_firstGuide());
    } on Object catch (error) {
      if (mounted) setState(() => _presentationFailure = error);
    }
  }

  void _changed() {
    if (_colorRoute != null && !_liveSession) _retireColor();
    if (mounted) setState(() {});
  }

  Future<void> _firstGuide() async {
    final preferences = widget.module.previewGuidePort;
    if (preferences == null) return;
    try {
      final seen = await preferences.readPreviewGuideSeen();
      if (!seen && mounted && !_leaving && _liveSession) {
        await _showGuide();
        // Persist only after a protected card was actually laid out. A failed
        // read/write never changes the workspace or claims acknowledgement.
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && _guideVisible && !_leaving && _liveSession) {
          await preferences.markPreviewGuideSeen();
        }
      }
    } on Object {
      // Help remains manually available; no blocking error over the preview.
    }
  }

  Future<void> _showGuide() async {
    if (_guideBusy || _guideVisible || !_editable || _guideHeight < 80) return;
    setState(() => _guideBusy = true);
    try {
      await _session.protectControls(_areas(guide: true));
      if (mounted && !_leaving && _liveSession) {
        setState(() => _guideVisible = true);
      }
    } on Object {
      // Do not expose controls over an unprotected native region.
    } finally {
      if (mounted) setState(() => _guideBusy = false);
    }
  }

  Future<void> _hideGuide() async {
    if (!_guideVisible || _guideBusy) return;
    setState(() {
      _guideVisible = false;
      _guideBusy = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && !_leaving) await _restoreProtection();
    if (mounted) setState(() => _guideBusy = false);
  }

  Widget _guide() => OverlayAppearancePreviewGuideCard(onDismiss: _hideGuide);

  void _draftChanged() {
    if (_colorRoute != null &&
        !identical(_colorSnapshot, widget.module.projection.value.snapshot)) {
      _retireColor();
    }
    if (!mounted ||
        (!_session.hasSession &&
            _session.phase != OverlayAppearanceLivePhase.opening) ||
        _leaving ||
        _session.phase == OverlayAppearanceLivePhase.closing ||
        _session.phase == OverlayAppearanceLivePhase.closed) {
      return;
    }
    try {
      final frame = _frame();
      final key = jsonEncode(frame.toMap());
      if (key == _lastFrame) return;
      _lastFrame = key;
      _session.update(frame);
    } on Object catch (error) {
      setState(() => _presentationFailure = error);
    }
  }

  @override
  void didChangeMetrics() {
    if (!_session.hasSession || _leaving) return;
    unawaited(
      _session
          .protectControls([const OverlayPreviewControlArea(0, 0, 1, 1)])
          .then((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_restoreProtection());
            });
          })
          .catchError((Object error) {
            if (mounted) setState(() => _presentationFailure = error);
          }),
    );
  }

  Future<void> _restoreProtection() async {
    try {
      await _session.protectControls(_areas());
    } on Object catch (error) {
      if (mounted) setState(() => _presentationFailure = error);
    }
  }

  Future<void> _move({bool? left, bool? collapsed}) async {
    if (_moving || _leaving || !_session.hasSession) return;
    setState(() => _moving = true);
    try {
      // Protect destination while the accepted old footprint stays protected.
      await _session.protectControls([
        ..._areas(),
        ..._areas(left: left, collapsed: collapsed),
      ]);
      if (!mounted) return;
      setState(() {
        _left = left ?? _left;
        _collapsed = collapsed ?? _collapsed;
      });
      await WidgetsBinding.instance.endOfFrame;
      await _session.protectControls(_areas());
      if (mounted) setState(() => _presentationFailure = null);
    } on Object catch (error) {
      if (mounted) setState(() => _presentationFailure = error);
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  void _retireColor() {
    final route = _colorRoute;
    _colorRoute = null;
    _colorSnapshot = null;
    retireStarBridgeDialog(route);
  }

  Future<void> _pickColor(String field, InteractionSource source) async {
    if (!_editable) return;
    setState(() => _moving = true);
    final originalSnapshot = widget.module.projection.value.snapshot;
    final original = widget.module.projection.value.settings![field] as String;
    try {
      await _session.protectControls([
        const OverlayPreviewControlArea(0, 0, 1, 1),
      ]);
      if (!mounted ||
          !_liveSession ||
          _leaving ||
          !identical(
            widget.module.projection.value.snapshot,
            originalSnapshot,
          )) {
        return;
      }
      _colorSnapshot = originalSnapshot;
      final result = await showStarBridgeDialog<String>(
        context,
        source: source,
        onRouteCreated: (route) => _colorRoute = route,
        builder: (_) => OverlayColorPickerDialog(
          label: _fieldName(field),
          initialValue: original,
        ),
      );
      if (mounted &&
          _liveSession &&
          !_leaving &&
          identical(
            widget.module.projection.value.snapshot,
            originalSnapshot,
          ) &&
          widget.module.projection.value.settings?[field] == original &&
          result != null) {
        widget.module.updateSetting(field, result);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _presentationFailure = error);
    } finally {
      _colorRoute = null;
      _colorSnapshot = null;
      if (mounted && !_leaving && _session.hasSession) {
        await _restoreProtection();
      }
      if (mounted) setState(() => _moving = false);
    }
  }

  Future<void> _save() async {
    if (widget.readOnly) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_editable) await widget.module.save();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    _retireColor();
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await _session.close();
      if (!mounted) return;
      setState(() => _canPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _leaving = false;
          _presentationFailure = error;
        });
      }
    }
  }

  @override
  void dispose() {
    _retireColor();
    WidgetsBinding.instance.removeObserver(this);
    widget.module.projection.removeListener(_draftChanged);
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  Widget _inspector(OverlayWorkspaceProjection p) {
    final snapshot = p.snapshot!;
    // Trial selection is not a value in the normal saved settings schema.
    final settings = p.settings!;
    final appearances = snapshot.appearances
        .where((a) => a.isPreviewAvailable)
        .toList();
    final selected = appearances.where((a) => a.id == _skin).firstOrNull;
    final profile = OverlayWorkspaceAppearanceRule(
      theme: settings['theme']! as String,
      startupTransition: settings['startupTransitionStyle']! as String,
      locksTheme: selected?.locksTheme ?? false,
      supportsBloom: selected?.supportsBloom ?? false,
    );
    final fields = overlayWorkspaceFieldSpecs
        .where(
          (f) =>
              (f.group == 'appearance' || f.group == 'crosshair') &&
              f.field != 'skin' &&
              (!(selected?.locksTheme ?? false) ||
                  !const {'theme', 'autoThemeByShip'}.contains(f.field)) &&
              (f.field != 'nightShadowBloom' ||
                  selected?.supportsBloom == true) &&
              f.userVisible,
        )
        .toList();
    List<Widget> colors(String group) => [
      for (final field in fields.where(
        (f) =>
            f.group == group &&
            f.kind == OverlayWorkspaceFieldKind.color &&
            overlayWorkspaceFieldVisible(
              f.field,
              settings,
              appearanceRule: profile,
            ),
      ))
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: StarBridgeActionButton(
            key: Key('appearance-preview-color-${field.field}'),
            onActivate:
                _editable &&
                    overlayWorkspaceFieldEnabled(
                      field.field,
                      settings,
                      appearanceRule: profile,
                    )
                ? (source) => _pickColor(field.field, source)
                : null,
            child: Text('${_fieldName(field.field)}  ${settings[field.field]}'),
          ),
        ),
    ];
    return Material(
      color: context.tokens.surfaces.panel.fill,
      child: SingleChildScrollView(
        key: const Key('appearance-preview-inspector'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OverlayAppearanceTryOnSelector(
              appearances: appearances,
              skin: _skin,
              onSelected: _editable
                  ? (value) {
                      setState(() => _skin = value);
                      _draftChanged();
                    }
                  : null,
            ),
            if (_session.supportsPlayback) _playbackControls(p),
            AbsorbPointer(
              absorbing: !_editable,
              child: OverlayWorkspaceSettingsGroup(
                group: 'appearance',
                settings: settings,
                appearanceRule: profile,
                fields: fields
                    .where(
                      (f) =>
                          f.group == 'appearance' &&
                          f.kind != OverlayWorkspaceFieldKind.color,
                    )
                    .toList(),
                appearances: snapshot.appearances,
                onChanged: widget.module.updateSetting,
              ),
            ),
            const SizedBox(height: 12),
            StarBridgeExpansionTile(
              key: const Key('appearance-preview-crosshair'),
              title: overlayWorkspaceGroupName(context, 'crosshair'),
              children: [
                ...colors('crosshair'),
                AbsorbPointer(
                  absorbing: !_editable,
                  child: OverlayWorkspaceSettingsGroup(
                    group: 'crosshair',
                    settings: settings,
                    appearanceRule: profile,
                    fields: fields
                        .where(
                          (f) =>
                              f.group == 'crosshair' &&
                              f.kind != OverlayWorkspaceFieldKind.color,
                        )
                        .toList(),
                    appearances: snapshot.appearances,
                    onChanged: widget.module.updateSetting,
                  ),
                ),
              ],
            ),
            ...colors('appearance'),
            for (final config in snapshot.appearanceConfigurations.where(
              (c) => c.appearanceId == _skin,
            ))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OverlayAppearanceConfigurationPanel(
                  configuration: config,
                  options: p.appearanceOptions,
                  placementStates: _session.placementStates,
                  enabled: _editable && snapshot.appearanceOptionsEnabled,
                  collectionTryOn: snapshot.appearanceProgressIds.contains(
                    _skin,
                  ),
                  onChanged: widget.module.updateAppearanceOptions,
                ),
              ),
            SizedBox(height: _top + _bottom + 28),
          ],
        ),
      ),
    );
  }

  Future<void> _play(OverlayAppearancePreviewPlayback action) async {
    if (!_editable) return;
    try {
      final accepted = await _session.play(action);
      if (mounted && !_leaving) {
        setState(
          () => _playbackStatus = accepted
              ? _copy(
                  '示例已发送，使用此外观的真实效果。',
                  '示例已傳送，使用此外觀的真實效果。',
                  'Example sent using this appearance’s native effect.',
                )
              : _copy(
                  '当前设置不支持此示例，请检查模块显示与事件容量。',
                  '目前設定不支援此示例，請檢查模組顯示與事件容量。',
                  'Current settings do not support this example. Check module visibility and event capacity.',
                ),
        );
      }
    } on Object {
      if (mounted && !_leaving) {
        setState(
          () => _playbackStatus = _copy(
            '示例未发送，可以重试；不会积压播放。',
            '示例未傳送，可以重試；不會積壓播放。',
            'Example not sent. Retry when ready; no playback was queued.',
          ),
        );
      }
    }
  }

  Widget _playbackControls(OverlayWorkspaceProjection p) {
    return OverlayAppearancePreviewPlaybackControls(
      settings: p.settings!,
      editable: _editable,
      reduced: _frame().reduceMotion,
      status: _playbackStatus,
      onPlay: _play,
      onReducedMotion: (value) {
        setState(() => _reducePreviewMotion = value);
        _draftChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_guideVisible) {
            unawaited(_hideGuide());
          } else {
            unawaited(_leave());
          }
          return KeyEventResult.handled;
        }
        if (HardwareKeyboard.instance.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyS) {
          unawaited(_save());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: const Key('appearance-preview-page'),
        backgroundColor: context.tokens.surfaces.ground.fill,
        body: ValueListenableBuilder(
          valueListenable: widget.module.projection,
          builder: (context, p, _) => LayoutBuilder(
            builder: (context, constraints) {
              _size = constraints.biggest;
              final failed =
                  _presentationFailure != null ||
                  _session.failure != null ||
                  !p.available;
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Empty space is occupied by the real, unscaled D2D HUD above this
                  // main window. Do not put screenshots or fake layout tiles here.
                  if (!widget.readOnly && p.available && !_collapsed)
                    Positioned(
                      left: _left ? 0 : null,
                      right: _left ? null : 0,
                      top: 0,
                      bottom: 0,
                      width: _panelWidth,
                      child: _inspector(p),
                    ),
                  if (_guideVisible && _guideHeight > 0)
                    Positioned(
                      left: (_size.width - _guideWidth) / 2,
                      width: _guideWidth,
                      height: _guideHeight,
                      bottom: _guideBottom,
                      child: _guide(),
                    ),
                  Positioned(
                    left: (_size.width - _barWidth) / 2,
                    width: _barWidth,
                    bottom: 12 + _bottom,
                    height: _top,
                    child: Material(
                      color: context.tokens.surfaces.floating.fill,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _copy('外观预览', '外觀預覽', 'Appearance preview'),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            StarBridgeIconAction(
                              controlKey: const Key('appearance-preview-help'),
                              label: _copy('查看预览提示', '查看預覽提示', 'Preview tips'),
                              onActivate: _editable && !_guideBusy
                                  ? (_) => _showGuide()
                                  : null,
                              icon: const StandardIcon(
                                StandardIconSemantic.info,
                              ),
                            ),
                            if (!widget.readOnly)
                              StarBridgeIconAction(
                                controlKey: const Key(
                                  'appearance-preview-switch-side',
                                ),
                                label: _copy('面板换边', '面板換邊', 'Move inspector'),
                                onActivate: _editable
                                    ? (_) => _move(left: !_left)
                                    : null,
                                icon: const StandardIcon(
                                  StandardIconSemantic.swapHoriz,
                                ),
                              ),
                            if (!widget.readOnly)
                              StarBridgeIconAction(
                                controlKey: const Key(
                                  'appearance-preview-collapse',
                                ),
                                label: _copy(
                                  _collapsed ? '展开设置' : '收起设置',
                                  _collapsed ? '展開設定' : '收起設定',
                                  _collapsed
                                      ? 'Show settings'
                                      : 'Hide settings',
                                ),
                                onActivate: _editable
                                    ? (_) => _move(collapsed: !_collapsed)
                                    : null,
                                icon: StandardIcon(
                                  _collapsed
                                      ? StandardIconSemantic.layers
                                      : StandardIconSemantic.visibility,
                                ),
                              ),
                            if (!widget.readOnly)
                              StarBridgeIconAction(
                                controlKey: const Key(
                                  'appearance-preview-save',
                                ),
                                label: _copy('保存更改', '儲存變更', 'Save changes'),
                                onActivate: _editable && p.dirty
                                    ? (_) => _save()
                                    : null,
                                icon: const StarBridgeIcon(
                                  StarBridgeIconSemantic.save,
                                ),
                              ),
                            StarBridgeIconAction(
                              controlKey: const Key('appearance-preview-exit'),
                              label: _copy('退出预览', '退出預覽', 'Exit preview'),
                              onActivate: _leaving ? null : (_) => _leave(),
                              icon: const StandardIcon(
                                StandardIconSemantic.close,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (_size.width - _barWidth) / 2,
                    width: _barWidth,
                    bottom: 12,
                    height: _bottom,
                    child: Material(
                      color: context.tokens.surfaces.floating.fill,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            overlayAppearancePreviewStatus(
                              Localizations.localeOf(context),
                              closed:
                                  _session.phase ==
                                  OverlayAppearanceLivePhase.closed,
                              failed: failed,
                              hasSession: _session.hasSession,
                              readOnly: widget.readOnly,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
