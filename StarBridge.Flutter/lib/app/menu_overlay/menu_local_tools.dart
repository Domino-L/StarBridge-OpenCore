import 'menu_overlay_locale.dart';
import '../localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';

import '../../design_system/interaction/starbridge_slider.dart';

import 'menu_bridge_style.dart';
import 'menu_workspace_controller.dart';

import 'menu_local_call.dart';
import 'menu_image_edit.dart';
import '../../platform/window/menu_shortcut_settings.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import '../../features/overlay_settings/menu_screenshot_directory_card.dart';
import '../../features/overlay_settings/menu_shortcut_settings_card.dart';
import '../../features/overlay_settings/menu_toolbar_editor.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_social_preferences.dart';
import '../../features/overlay_settings/menu_social_settings_card.dart';
import '../../features/overlay_settings/menu_display_editor.dart';
import '../../features/overlay_settings/menu_restore_editor.dart';
import '../../platform/window/menu_restore_preferences.dart';
import '../../platform/window/menu_browser_preferences.dart';
import '../../platform/window/menu_image_preferences.dart';
import '../../platform/window/menu_screenshot_preferences.dart';
import '../../features/overlay_settings/menu_screenshot_editor.dart';
import '../../features/overlay_settings/menu_image_editor.dart';
import '../../features/overlay_settings/menu_browser_editor.dart';
import '../../features/overlay_settings/menu_browser_resume_card.dart';
import '../../features/overlay_settings/menu_browser_resume_controller.dart';
export 'menu_local_call.dart';
export 'menu_browser_tool.dart';
export 'menu_image_editor.dart';

class _ReferenceAdjustment {
  _ReferenceAdjustment(MenuLocalToolsController tools)
    : opacity = tools.referenceOpacity,
      imageOnly = tools.referenceImageOnly,
      pinned = tools.pinned,
      edit = tools.referenceEdit,
      undo = List<MenuImageEdit>.of(tools._referenceUndo),
      scaleMode = tools.referenceScaleMode,
      transform = Matrix4.copy(tools.referenceTransform.value);
  final double opacity;
  final bool imageOnly, pinned;
  final String? scaleMode;
  final Matrix4 transform;
  final MenuImageEdit edit;
  final List<MenuImageEdit> undo;
}

/// Presentation state only. File selection, capture and WebView ownership stay
/// native; no file paths or browser scripts can be supplied by the surface.
class MenuLocalToolsController extends ChangeNotifier {
  MenuLocalToolsController(this.call, {this.locale});
  final Locale Function()? locale;
  String _text(String key, [Map<String, Object?> args = const {}]) =>
      menuOverlayFormat(
        AppStrings.resolve(locale?.call() ?? const Locale('zh', 'CN')),
        key,
        args,
      );
  final MenuLocalCall call;
  Uint8List? reference, screenshot;
  Uint8List? referencePreview;
  MenuImageEdit referenceEdit = const MenuImageEdit();
  int referencePreviewTurns = 0;
  final List<MenuImageEdit> _referenceUndo = [];
  bool get canUndoReference => _referenceUndo.isNotEmpty;
  int get referenceDisplayTurns => (referenceTurns - referencePreviewTurns) % 4;
  Uint8List? screenshotPreview;
  MenuImageEdit screenshotEdit = const MenuImageEdit();
  final List<MenuImageEdit> _undo = [];
  final referenceTransform = TransformationController();
  int referenceTurns = 0;
  double referenceOpacity = 1;
  bool referenceImageOnly = false;
  final referenceChromeHidden = ValueNotifier<bool>(false);
  bool referenceAutoPinOnClose = true;
  String? referenceScaleMode = 'fit';
  bool referenceAutoPinPending = false;
  String referenceNoticeKey = '';
  String? _referenceId;
  final _referenceAdjustments = <String, _ReferenceAdjustment>{};
  static final _imageId = RegExp(
    r'^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$',
  );

  void _rememberReference() {
    if (!imagePreferences.rememberAdjustments ||
        reference == null ||
        _referenceId == null) {
      return;
    }
    _referenceAdjustments.remove(_referenceId);
    _referenceAdjustments[_referenceId!] = _ReferenceAdjustment(this);
    if (_referenceAdjustments.length > 32) {
      _referenceAdjustments.remove(_referenceAdjustments.keys.first);
    }
  }

  bool pinned = false, pinDirty = false;
  Rect? pinnedBounds;
  int referenceEditSerial = 0;
  int revision = 0;
  bool get canUndo => _undo.isNotEmpty;
  String notice = '';
  bool busy = false, closed = false;
  InteractionSource imageFeedbackSource = InteractionSource.programmatic;
  void _beginImageFeedback([InteractionSource? source]) =>
      imageFeedbackSource = source ?? captureStarBridgeActivationSource()();
  MenuDisplayPreferences display = const MenuDisplayPreferences();
  MenuSocialPreferences social = const MenuSocialPreferences();
  bool get showClock => display.showClock;
  bool get showContext => display.showContext;
  MenuRestorePreferences restore = const MenuRestorePreferences();
  bool get restoreDesktop => restore.inSession;
  set restoreDesktop(bool value) => restore = restore.change(inSession: value);
  bool snapWindows = false;
  double dimming = 133 / 255;
  MenuToolbarPreferences toolbar = const MenuToolbarPreferences();
  MenuBrowserPreferences browser = const MenuBrowserPreferences();
  MenuImagePreferences imagePreferences = const MenuImagePreferences();
  MenuScreenshotPreferences screenshotPreferences =
      const MenuScreenshotPreferences();
  String screenshotNoticeKey = '';
  Future<void> image({bool capture = false}) async {
    if (busy || closed) return;
    final hideMenu = screenshotPreferences.hideMenu;
    _beginImageFeedback();
    busy = true;
    if (capture) screenshotNoticeKey = '';
    notice = '';
    notifyListeners();
    try {
      final selected = await call(
        capture ? 'capture' : 'image',
        capture ? {'hideMenu': hideMenu} : const {},
      );
      if (closed) return;
      Uint8List? bytes;
      String? imageId;
      if (selected is Uint8List) {
        bytes = selected; // Older native adapter: display, but do not invent an identity.
      } else if (!capture &&
          selected is Map &&
          selected.length == 2 &&
          selected.containsKey('bytes') &&
          selected.containsKey('imageId') &&
          selected['bytes'] is Uint8List &&
          (selected['imageId'] == null ||
              (selected['imageId'] is String &&
                  _imageId.hasMatch(selected['imageId'])))) {
        bytes = selected['bytes'];
        imageId = selected['imageId'];
      }
      if (bytes is Uint8List &&
          bytes.isNotEmpty &&
          bytes.length <= 32 * 1024 * 1024) {
        if (capture) {
          screenshot = bytes;
          screenshotPreview = bytes;
          screenshotEdit = const MenuImageEdit();
          _undo.clear();
        } else {
          _rememberReference();
          final saved = imagePreferences.rememberAdjustments && imageId != null
              ? _referenceAdjustments.remove(imageId)
              : null;
          Uint8List? restoredPreview;
          var editRestored = true;
          if (saved != null &&
              (saved.edit.turns != 0 ||
                  saved.edit.crop != const Rect.fromLTWH(0, 0, 1, 1))) {
            try {
              final result = await call('imageEdit', saved.edit.toMap());
              if (closed) return;
              if (result is! Uint8List ||
                  result.length > 32 * 1024 * 1024 ||
                  menuPngSize(result) == null) {
                throw StateError('Invalid reference edit');
              }
              restoredPreview = result;
            } on Object {
              if (closed) return;
              editRestored = false;
            }
          }
          _referenceId = imageId;
          reference = bytes;
          referencePreview = restoredPreview;
          referenceEdit = editRestored
              ? saved?.edit ?? const MenuImageEdit()
              : const MenuImageEdit();
          referencePreviewTurns = restoredPreview == null
              ? 0
              : referenceEdit.turns;
          _referenceUndo.clear();
          if (editRestored && saved != null) _referenceUndo.addAll(saved.undo);
          pinned = pinDirty = false;
          pinnedBounds = null;
          referenceEditSerial++;
          referenceTurns = referenceEdit.turns;
          referenceOpacity =
              saved?.opacity ?? imagePreferences.opacityPercent / 100;
          referenceImageOnly =
              saved?.imageOnly ?? imagePreferences.openMode == 'imageOnly';
          referenceChromeHidden.value = referenceImageOnly;
          referenceAutoPinOnClose = true;
          referenceTransform.value = saved == null || !editRestored
              ? Matrix4.identity()
              : Matrix4.copy(saved.transform);
          referenceScaleMode = saved == null || !editRestored
              ? imagePreferences.scaleMode
              : saved.scaleMode;
          referenceAutoPinPending =
              editRestored && (saved?.pinned ?? imagePreferences.defaultPinned);
          referenceNoticeKey = !editRestored
              ? 'restoreEditFailed'
              : saved != null
              ? 'restored'
              : imageId == null && imagePreferences.rememberAdjustments
              ? 'identityUnavailable'
              : '';
        }
        revision++;
      } else if (selected != null) {
        notice = _text('menu.overlay.image.invalid');
      }
    } on Object {
      if (!closed) {
        notice = capture
            ? _text('menu.overlay.image.captureFailed')
            : _text('menu.overlay.image.openFailed');
      }
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  bool screenshotDirectoryAvailable = false;
  Future<void> save({bool copy = false, bool toDirectory = false}) => _save(
    copy: copy,
    toDirectory: toDirectory,
    preferences: screenshotPreferences,
  );
  Future<void> _save({
    required bool copy,
    required bool toDirectory,
    required MenuScreenshotPreferences preferences,
    InteractionSource? source,
  }) async {
    if (busy || closed || screenshot == null) return;
    _beginImageFeedback(source);
    busy = true;
    notice = '';
    screenshotNoticeKey = '';
    final edit = screenshotEdit.toMap();
    notifyListeners();
    try {
      if (toDirectory && !copy) {
        if (!screenshotDirectoryAvailable ||
            await call('screenshotDestination', const {}) != true) {
          throw PlatformException(
            code: 'menu.screenshot_directory_unavailable',
          );
        }
        if (closed) return;
      }
      final saved = await call(
        copy
            ? 'screenshotCopy'
            : toDirectory
            ? 'saveToDirectory'
            : 'save',
        copy ? edit : {...edit, 'export': preferences.toExportOptions()},
      );
      if (closed) return;
      if (saved == false && !copy && !toDirectory) {
        screenshotNoticeKey = 'cancelled';
      } else if (saved != true) {
        screenshotNoticeKey = copy ? 'copyFailed' : 'saveFailed';
      } else if (!copy && preferences.copyAfterSave) {
        try {
          final copied = await call('screenshotCopy', edit);
          if (!closed) {
            screenshotNoticeKey = copied != true
                ? 'savedCopyFailed'
                : preferences.showConfirmation
                ? 'savedCopied'
                : '';
          }
        } on Object {
          if (!closed) screenshotNoticeKey = 'savedCopyFailed';
        }
      } else if (preferences.showConfirmation) {
        screenshotNoticeKey = copy ? 'copied' : 'exported';
      }
    } on PlatformException catch (error) {
      if (!closed) {
        screenshotNoticeKey =
            error.code == 'menu.screenshot_directory_unavailable'
            ? 'directoryUnavailable'
            : error.code == 'menu.screenshot_extension_mismatch'
            ? 'extensionMismatch'
            : copy
            ? 'copyFailed'
            : 'saveFailed';
      }
    } on Object {
      if (!closed) screenshotNoticeKey = copy ? 'copyFailed' : 'saveFailed';
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> captureAndSave({bool toDirectory = false}) async {
    if (busy || closed) return;
    final source = captureStarBridgeActivationSource()();
    final before = revision;
    final preferences = screenshotPreferences;
    screenshotNoticeKey = '';
    await image(capture: true);
    if (!closed && revision != before && screenshot != null) {
      await _save(
        copy: false,
        toDirectory: toDirectory,
        preferences: preferences,
        source: source,
      );
    }
  }

  Future<void> editScreenshot(MenuImageEdit edit, {bool undo = false}) async {
    if (busy || closed || screenshot == null) return;
    _beginImageFeedback();
    busy = true;
    screenshotNoticeKey = '';
    notice = '';
    notifyListeners();
    try {
      final result = await call('screenshotEdit', edit.toMap());
      if (closed) return;
      if (result is! Uint8List ||
          result.isEmpty ||
          result.length > 32 * 1024 * 1024) {
        throw StateError('invalid image');
      }
      if (undo) {
        _undo.removeLast();
      } else {
        _undo.add(screenshotEdit);
        if (_undo.length > 20) _undo.removeAt(0);
      }
      screenshotEdit = edit;
      screenshotPreview = result;
      revision++;
    } on Object {
      if (!closed) notice = _text('menu.overlay.image.adjustFailed');
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> undoScreenshot() async {
    if (_undo.isNotEmpty) await editScreenshot(_undo.last, undo: true);
  }

  Future<void> editReference(MenuImageEdit edit, {bool undo = false}) async {
    if (busy || closed || reference == null) return;
    _beginImageFeedback();
    busy = true;
    notice = '';
    notifyListeners();
    try {
      final result = await call('imageEdit', edit.toMap());
      if (closed) return;
      if (result is! Uint8List ||
          result.length > 32 * 1024 * 1024 ||
          menuPngSize(result) == null) {
        throw StateError('Invalid reference edit');
      }
      if (undo) {
        _referenceUndo.removeLast();
      } else {
        _recordReferenceEdit();
      }
      referenceEdit = edit;
      referenceTurns = referencePreviewTurns = edit.turns;
      referencePreview = result;
      referenceTransform.value = Matrix4.identity();
      referenceScaleMode = 'fit';
      referenceAutoPinPending = false;
      referenceEditSerial++;
      pinDirty = pinned;
      revision++;
      referenceNoticeKey = pinDirty ? '' : 'editApplied';
    } on Object {
      if (!closed) referenceNoticeKey = 'editFailed';
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _recordReferenceEdit() {
    _referenceUndo.add(referenceEdit);
    if (_referenceUndo.length > 20) _referenceUndo.removeAt(0);
  }

  Future<void> undoReference() async {
    if (_referenceUndo.isNotEmpty) {
      await editReference(_referenceUndo.last, undo: true);
    }
  }

  void referenceChanged({int? turns, double? opacity, bool fit = false}) {
    if (closed || busy) return;
    if (turns != null && turns % 4 != referenceTurns) {
      _recordReferenceEdit();
      while (referenceEdit.turns != turns % 4) {
        referenceEdit = referenceEdit.rotate();
      }
      referenceTurns = referenceEdit.turns;
    }
    referenceOpacity = (opacity ?? referenceOpacity).clamp(.15, 1);
    if (fit) {
      referenceTransform.value = Matrix4.identity();
      referenceScaleMode = 'fit';
    }
    pinDirty = pinned;
    referenceEditSerial++;
    notice = '';
    referenceNoticeKey = '';
    notifyListeners();
  }

  void referenceView({String? mode, bool? imageOnly}) {
    if (closed || busy) return;
    if (mode != null) referenceScaleMode = mode;
    referenceImageOnly = imageOnly ?? referenceImageOnly;
    referenceChromeHidden.value = reference != null && referenceImageOnly;
    // Chrome visibility does not edit the image or invalidate its fixed frame.
    if (mode != null) {
      markPinDirty();
      notice = '';
      referenceNoticeKey = '';
    }
    notifyListeners();
  }

  void markPinDirty() {
    if (closed) return;
    referenceEditSerial++;
    if (!pinned || pinDirty) return;
    pinDirty = true;
    notice = '';
    notifyListeners();
  }

  Future<bool> pin(Map<String, Object?> frame, {int? editSerial}) async {
    if (closed || reference == null) return false;
    if (busy) {
      notice = _text('menu.overlay.image.pinBusy');
      notifyListeners();
      return false;
    }
    final serial = editSerial ?? referenceEditSerial;
    _beginImageFeedback();
    busy = true;
    notice = '';
    notifyListeners();
    try {
      await call('imagePin', frame);
      if (!closed) {
        pinned = true;
        pinDirty = referenceEditSerial != serial;
        final x = frame['x'],
            y = frame['y'],
            w = frame['width'],
            h = frame['height'];
        if (x is num && y is num && w is num && h is num) {
          pinnedBounds = Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            w.toDouble(),
            h.toDouble(),
          );
        }
        notice = pinDirty
            ? _text('menu.overlay.image.pinDirty')
            : _text('menu.overlay.image.pinned');
      }
      return !closed;
    } on Object {
      if (!closed) notice = _text('menu.overlay.image.pinFailed');
      return false;
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> clear({bool capture = false, bool unpinOnly = false}) async {
    if (busy || closed) return;
    _beginImageFeedback();
    busy = true;
    notifyListeners();
    try {
      await call(
        unpinOnly
            ? 'imageUnpin'
            : capture
            ? 'screenshotClear'
            : 'imageClear',
        const {},
      );
      if (closed) return;
      if (capture) {
        screenshotNoticeKey = '';
        screenshot = screenshotPreview = null;
        screenshotEdit = const MenuImageEdit();
        _undo.clear();
      } else {
        pinned = pinDirty = false;
        referenceAutoPinOnClose = false;
        referenceAutoPinPending = false;
        _rememberReference();
        pinnedBounds = null;
        if (!unpinOnly) {
          reference = referencePreview = null;
          referenceChromeHidden.value = false;
          referenceEdit = const MenuImageEdit();
          referencePreviewTurns = referenceTurns = 0;
          _referenceUndo.clear();
          _referenceId = null;
        }
      }
      revision++;
      notice = unpinOnly
          ? _text('menu.overlay.image.unpinned')
          : capture
          ? _text('menu.overlay.image.clearedScreenshot')
          : _text('menu.overlay.image.clearedReference');
    } on Object {
      if (!closed) notice = _text('menu.overlay.errors.actionRetry');
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void settings({
    bool? clock,
    bool? context,
    double? dim,
    bool? restore,
    MenuRestorePreferences? restoration,
    bool? snap,
    MenuToolbarPreferences? toolbar,
    MenuDisplayPreferences? display,
    MenuSocialPreferences? social,
    MenuBrowserPreferences? browser,
    MenuImagePreferences? image,
    MenuScreenshotPreferences? screenshot,
  }) {
    this.display = display ?? this.display;
    this.social = social ?? this.social;
    if (clock != null) this.display = this.display.change('showClock', clock);
    if (context != null) {
      this.display = this.display.change('showContext', context);
    }
    dimming = (dim ?? dimming).clamp(.3, .9);
    restoreDesktop = restore ?? restoreDesktop;
    this.restore = restoration ?? this.restore;
    snapWindows = snap ?? snapWindows;
    this.toolbar = toolbar ?? this.toolbar;
    this.browser = browser ?? this.browser;
    if (image?.rememberAdjustments == false) _referenceAdjustments.clear();
    imagePreferences = image ?? imagePreferences;
    screenshotPreferences = screenshot ?? screenshotPreferences;
    notifyListeners();
  }

  @override
  void dispose() {
    closed = true;
    imageFeedbackSource = InteractionSource.programmatic;
    notice = referenceNoticeKey = screenshotNoticeKey = '';
    reference = referencePreview = screenshot = screenshotPreview = null;
    _referenceUndo.clear();
    _referenceId = null;
    _referenceAdjustments.clear();
    referenceAutoPinPending = false;
    referenceTransform.dispose();
    referenceChromeHidden.dispose();
    super.dispose();
  }
}

class MenuLocalSettings extends StatelessWidget {
  const MenuLocalSettings({
    super.key,
    required this.tools,
    required this.workspace,
    this.shortcutSettings,
    this.browserResume,
    this.screenshotDirectory,
  });
  final MenuLocalToolsController tools;
  final MenuWorkspaceController workspace;
  final MenuShortcutSettingsPort? shortcutSettings;
  final MenuBrowserResumeController? browserResume;
  final MenuScreenshotDirectoryPort? screenshotDirectory;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tools,
    builder: (context, _) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shortcutSettings != null) ...[
              MenuShortcutSettingsCard(port: shortcutSettings!),
              const SizedBox(height: 16),
            ],
            MenuRestoreEditor(
              value: tools.restore,
              onChanged: (value) => tools.settings(restoration: value),
            ),
            BridgeMenuAction(
              key: const Key('menu-local-snap'),
              label: menuText(context, 'menu.overlay.window.snap'),
              selected: tools.snapWindows,
              onPressed: () => tools.settings(snap: !tools.snapWindows),
              child: Text(
                '${tools.snapWindows ? "✓" : "—"} ${menuText(context, 'menu.overlay.window.snap')}',
              ),
            ),
            BridgeMenuAction(
              key: const Key('menu-local-reset-layout'),
              label: menuText(context, 'menu.overlay.window.resetLayout'),
              onPressed: workspace.resetPlacements,
              child: Text(menuText(context, 'menu.overlay.window.resetLayout')),
            ),
            const SizedBox(height: 12),
            MenuDisplayEditor(
              value: tools.display,
              onChanged: (value) => tools.settings(display: value),
            ),
            const SizedBox(height: 16),
            MenuSocialEditor(
              value: tools.social,
              onChanged: (value) => tools.settings(social: value),
            ),
            const SizedBox(height: 12),
            Text(menuText(context, 'menu.overlay.window.dimming')),
            StarBridgeSlider(
              controlKey: const Key('menu-local-dimming'),
              semanticLabel: menuText(context, 'menu.overlay.window.dimming'),
              valueLabel: (value) => '${(value * 100).round()}%',
              value: tools.dimming,
              min: .3,
              max: .9,
              onChanged: (value) => tools.settings(dim: value),
            ),
            BridgeCaption(menuText(context, 'menu.overlay.window.menuOnly')),
            const SizedBox(height: 16),
            MenuToolbarEditor(
              value: tools.toolbar,
              onChanged: (value) => tools.settings(toolbar: value),
            ),
            const SizedBox(height: 16),
            MenuBrowserEditor(
              value: tools.browser,
              onChanged: (value) => tools.settings(browser: value),
            ),
            const SizedBox(height: 16),
            MenuImageEditor(
              value: tools.imagePreferences,
              onChanged: (value) => tools.settings(image: value),
            ),
            const SizedBox(height: 16),
            MenuScreenshotEditor(
              value: tools.screenshotPreferences,
              onChanged: (value) => tools.settings(screenshot: value),
            ),
            if (browserResume != null) ...[
              const SizedBox(height: 16),
              MenuBrowserResumeCard(
                port: browserResume!.port,
                controller: browserResume,
              ),
            ],
            if (screenshotDirectory != null) ...[
              const SizedBox(height: 16),
              MenuScreenshotDirectoryCard(port: screenshotDirectory!),
            ],
          ],
        ),
      ),
    ),
  );
}
