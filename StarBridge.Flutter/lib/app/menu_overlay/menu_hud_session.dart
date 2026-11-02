import 'dart:async';
import 'dart:convert';

import '../../features/overlay_settings/overlay_preset_name.dart';
import '../../features/overlay_settings/overlay_workspace_layout_item.dart';
import '../../features/overlay_settings/overlay_workspace_module.dart';
import '../../features/overlay_settings/overlay_scene_controller.dart';
import '../localization/app_strings.dart';
import 'menu_feature_session.dart';
import 'menu_hud_quick_projection.dart';

final class MenuHudSession extends MenuFeatureSession {
  MenuHudSession(
    this.workspace,
    this.scenes,
    void Function(Map<String, Object?>) publish,
  ) : super(publish, const Stream.empty());
  final OverlayWorkspaceModule workspace;
  final OverlaySceneController? scenes;
  String notice = '';
  bool _toggling = false;
  bool _working = false;
  int _intentEpoch = 0;
  Map<String, Object?>? _note;
  Timer? _noteTimer;
  ({String preset, String module, bool visible})? _undo;
  bool _placing = false;
  // Placement is an explicit session over the auto-saving workspace: Done
  // saves, Cancel restores. Scheduled commits are held while it is open.
  bool _holdingCommits = false;
  String _placeResult = '';

  AppStrings get _strings =>
      AppStrings.resolve(menuHudLocale(workspace.runtimeLanguage));

  String get _failureNotice {
    final language = workspace.runtimeLanguage.toLowerCase();
    if (!language.startsWith('zh')) {
      return 'Could not complete this action. Check the overlay settings in the client and try again.';
    }
    if (language.contains('tw') ||
        language.contains('hk') ||
        language.contains('hant')) {
      return '未完成，請檢查客戶端浮層設定後重試。';
    }
    return '未完成，请检查客户端浮层设置后重试。';
  }

  @override
  void show(bool value) {
    if (disposed || visible == value) return;
    visible = value;
    _intentEpoch++;
    if (value) {
      workspace.projection.addListener(_publish);
      scenes?.projection.addListener(_publish);
      _publish();
      unawaited(
        workspace
            .refreshRuntime(workspace.runtimeLanguage)
            .catchError((Object _) => false),
      );
      unawaited(scenes?.refresh());
    } else {
      workspace.projection.removeListener(_publish);
      scenes?.projection.removeListener(_publish);
      _clearNote();
      _endPlacement();
    }
  }

  /// Leaving the menu always ends placement. An unfinished placement never
  /// survives as a client draft; Done has already saved, Cancel discarded.
  void _endPlacement() {
    if (_placing) {
      final view = workspace.projection.value;
      if (_placeResult != 'saved' && view.dirty && !view.busy) {
        workspace.discardChanges();
      }
    }
    _releaseCommits();
    _placing = false;
    _placeResult = '';
  }

  void _releaseCommits() {
    if (!_holdingCommits) return;
    _holdingCommits = false;
    workspace.releaseCommits();
  }

  Map<String, Object?> _view() {
    final view = workspace.projection.value;
    return {
      'title': _strings.text('menu.tools.hud'),
      'notice': notice,
      'busy': _toggling || view.runtimeBusy,
      'hudEnabled': view.runtime.available ? view.runtime.enabled : null,
      'quick': menuHudQuickWire(
        workspace: view,
        scene: scenes?.projection.value,
        strings: _strings,
        working: _working || _toggling,
        note: _note,
        placing: _placing,
        placeResult: _placeResult,
        canUndo: workspace.canUndo,
        canRedo: workspace.canRedo,
      ),
    };
  }

  void _publish() {
    if (!visible || disposed) return;
    final view = workspace.projection.value;
    emit({
      'state': view.runtime.available ? 'ready' : 'unavailable',
      ..._view(),
    });
  }

  @override
  void act(String key, String value) {
    if (disposed || !visible) return;
    if (key == 'toggle' && value.isEmpty) {
      if (!_toggling) unawaited(_toggle());
      return;
    }
    if (_working || _toggling) return;
    if (key.startsWith('place')) {
      _place(key, value);
      return;
    }
    if (_placing) return;
    switch (key) {
      case 'preset':
        unawaited(_quick(() => _activatePreset(value)));
      case 'source':
        unawaited(_quick(() => _selectSource(value)));
      case 'module' when menuHudQuickFields.containsKey(value):
        final visible =
            workspace.projection.value.settings?[menuHudQuickFields[value]!];
        if (visible is bool) {
          unawaited(_quick(() => _setModule(value, !visible, undo: false)));
        }
      case 'undo' when value.isEmpty:
        final undo = _undo;
        final active = workspace.projection.value.snapshot?.activePresetId;
        if (undo != null && undo.preset == active) {
          unawaited(
            _quick(() => _setModule(undo.module, undo.visible, undo: true)),
          );
        }
    }
  }

  void _place(String key, String value) {
    if (key == 'placeBegin') {
      final view = workspace.projection.value;
      if (_placing || !_editable || !view.runtime.enabled) return;
      if (view.dirty) {
        // Settings-page edits still in their quiet period are saved first, so
        // Cancel restores exactly what was on screen when placement began.
        unawaited(
          _quick(() async {
            if (await workspace.save() && !_placing && _editable) {
              _beginPlacement();
            } else if (!_placing) {
              _setNote('failed', ok: false);
            }
          }),
        );
        return;
      }
      _beginPlacement();
      return;
    }
    if (!_placing || _placeResult.isNotEmpty) return;
    final view = workspace.projection.value;
    switch (key) {
      case 'placeItem':
        try {
          final wire = jsonDecode(value) as Map<String, Object?>;
          final item = OverlayWorkspaceLayoutItem.fromMap(
            (wire['item']! as Map).cast<String, Object?>(),
          );
          if (!view.layout.any((current) => current.key == item.key)) return;
          // A gesture is one undo step: reset coalescing on its first frame.
          if (wire['first'] == true) workspace.beginEventNotificationGesture();
          workspace.updateLayoutItem(item);
        } on Object {
          return;
        }
      case 'placeEvents':
        try {
          final wire = jsonDecode(value) as Map<String, Object?>;
          final side = wire['side'], y = wire['y'];
          if (side is! String || y is! num || !y.isFinite) return;
          if (wire['first'] == true) workspace.beginEventNotificationGesture();
          workspace.updateEventNotificationPlacement(side, y.toDouble());
        } on Object {
          return;
        }
      case 'placeShow' || 'placeHide'
          when menuHudQuickFields.containsKey(value):
        workspace.updateSetting(menuHudQuickFields[value]!, key == 'placeShow');
      case 'placeUndo':
        workspace.undo();
      case 'placeRedo':
        workspace.redo();
      case 'placeCancel':
        if (view.dirty && !view.busy) workspace.discardChanges();
        _releaseCommits();
        _placeResult = 'cancelled';
        _publish();
      case 'placeDone':
        unawaited(
          _quick(() async {
            if (!workspace.projection.value.dirty) {
              _placeResult = 'saved';
              return;
            }
            _placeResult = await workspace.save() ? 'saved' : '';
            if (_placeResult.isEmpty) {
              _setNote('failed', ok: false);
            } else {
              _releaseCommits();
            }
          }),
        );
    }
  }

  void _beginPlacement() {
    _clearNote();
    workspace.holdCommits();
    _holdingCommits = true;
    _placing = true;
    _placeResult = '';
    _publish();
  }

  Future<void> _quick(Future<void> Function() task) async {
    final epoch = _intentEpoch;
    _working = true;
    _publish();
    try {
      await task();
    } on Object {
      if (epoch == _intentEpoch) _setNote('failed', ok: false);
    } finally {
      _working = false;
      _publish();
    }
  }

  // Edits save on their own, so a pending one is no obstacle (actions save it
  // first). Only an edit that failed to save blocks writes from here.
  bool get _editable {
    final view = workspace.projection.value;
    return view.available &&
        !view.busy &&
        !(view.dirty && view.failure != null);
  }

  Future<void> _activatePreset(String id) async {
    final presets = workspace.projection.value.snapshot?.presets ?? const [];
    final target = presets.where((p) => p.id == id).firstOrNull;
    if (!_editable || target == null || target.isActive) return;
    if (!await workspace.activatePreset(id)) {
      _setNote('failed', ok: false);
      return;
    }
    _undo = null;
    final wire = menuHudQuickWire(
      workspace: workspace.projection.value,
      scene: scenes?.projection.value,
      strings: _strings,
      working: false,
    );
    final bound = (wire['presets'] as List)
        .cast<Map<String, Object?>>()
        .where((p) => p['id'] == id)
        .firstOrNull?['bound'];
    _setNote(
      bound is String && bound.isNotEmpty ? 'presetBound' : 'preset',
      args: {'name': target.name, if (bound is String) 'source': bound},
    );
  }

  Future<void> _selectSource(String id) async {
    final controller = scenes;
    if (controller == null || id.isEmpty) return;
    if (controller.projection.value.preferredId == id) return;
    if (!await controller.select(id)) {
      _setNote('failed', ok: false);
      return;
    }
    final source =
        menuHudQuickWire(
              workspace: workspace.projection.value,
              scene: controller.projection.value,
              strings: _strings,
              working: false,
            )['source']
            as Map<String, Object?>?;
    _setNote('source', args: {'source': '${source?['label'] ?? ''}'});
  }

  /// Quick toggles save straight to the active preset. They only run on a
  /// clean workspace, so the saved draft contains nothing but this change.
  Future<void> _setModule(
    String module,
    bool show, {
    required bool undo,
  }) async {
    final field = menuHudQuickFields[module]!;
    final before = workspace.projection.value;
    final preset = before.snapshot?.presets
        .where((p) => p.isActive)
        .firstOrNull;
    if (!_editable || preset == null) return;
    workspace.updateSetting(field, show);
    final changed = workspace.projection.value;
    if (identical(changed, before) || changed.settings?[field] != show) {
      _setNote('failed', ok: false);
      return;
    }
    if (!await workspace.save()) {
      final after = workspace.projection.value;
      if (after.dirty && !after.busy) workspace.discardChanges();
      _setNote('failed', ok: false);
      return;
    }
    _undo = undo ? null : (preset: preset.id, module: module, visible: !show);
    if (undo) {
      _setNote('undone');
    } else {
      _setNote(
        show ? 'shown' : 'hidden',
        args: {'module': module, 'preset': preset.shownName(_strings)},
        undo: true,
      );
    }
  }

  void _setNote(
    String kind, {
    Map<String, String> args = const {},
    bool ok = true,
    bool undo = false,
  }) {
    _noteTimer?.cancel();
    _note = {'kind': kind, 'args': args, 'ok': ok, 'undo': undo};
    _noteTimer = Timer(const Duration(seconds: 6), () {
      _clearNote();
      _publish();
    });
  }

  void _clearNote() {
    _noteTimer?.cancel();
    _noteTimer = null;
    _note = null;
    _undo = null;
  }

  Future<void> _toggle() async {
    final epoch = _intentEpoch;
    _toggling = true;
    _publish();
    try {
      // The same primary workspace owns current state and open/close commands.
      // This direct button does not mount a HUD settings window or start a poller.
      final read = await workspace.refreshRuntime(workspace.runtimeLanguage);
      if (disposed || epoch != _intentEpoch) return;
      if (!read) {
        notice = _failureNotice;
        return;
      }
      if (workspace.projection.value.runtimeBusy) return;
      final opening = !workspace.projection.value.runtime.enabled;
      final result = opening
          ? await workspace.openRuntime(workspace.runtimeLanguage)
          : await workspace.closeRuntime(workspace.runtimeLanguage);
      if (disposed || epoch != _intentEpoch) return;
      notice = result ? '' : _failureNotice;
      if (result) _setNote(opening ? 'hudOn' : 'hudOff');
    } on Object {
      if (!disposed && epoch == _intentEpoch) notice = _failureNotice;
    } finally {
      _toggling = false;
      _publish();
    }
  }

  @override
  void reset() {
    notice = '';
  }

  @override
  Future<void> closePort() async {
    workspace.projection.removeListener(_publish);
    scenes?.projection.removeListener(_publish);
    _clearNote();
  }

  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation;
    await workspace.refreshRuntime(workspace.runtimeLanguage);
    if (!current(epoch)) throw StateError('retired');
    return _view();
  }
}
