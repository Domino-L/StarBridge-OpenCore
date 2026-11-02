import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../platform/window/overlay_editor_window_port.dart';

import 'appearance_motion_browser.dart';
import 'native_appearance_player.dart';

/// Content-free catalog photographs rendered by the shipping native overlay.
/// Regenerate with tools/StarBridge.AppearanceCapture when its chrome changes.
class OverlayAppearancePreview extends StatefulWidget {
  const OverlayAppearancePreview({
    required this.appearanceId,
    this.previewableIds = const {'Default', 'NightShadow'},
    this.editorWindow = const UnavailableOverlayEditorWindow(),
    this.nativePoster,
    super.key,
  });

  final String appearanceId;
  final Set<String> previewableIds;
  final OverlayEditorWindowPort editorWindow;
  final Uint8List? nativePoster;

  @override
  State<OverlayAppearancePreview> createState() =>
      _OverlayAppearancePreviewState();
}

class _OverlayAppearancePreviewState extends State<OverlayAppearancePreview>
    with WidgetsBindingObserver {
  bool _paused = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _active = state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static const _assets = <String, String>{
    'Default': 'assets/overlay-appearances/Default.png',
    'NightShadow': 'assets/overlay-appearances/NightShadow.png',
    'Verdict': 'assets/overlay-appearances/Verdict.png',
  };

  @override
  Widget build(BuildContext context) {
    final appearanceId = widget.appearanceId;
    final motionAllowed = !MediaQuery.disableAnimationsOf(context);
    final asset = widget.previewableIds.contains(appearanceId)
        ? _assets[appearanceId]
        : null;
    final hasMotion = asset != null && motionAllowed;
    final poster = widget.previewableIds.contains(appearanceId)
        ? widget.nativePoster
        : null;
    final playing =
        hasMotion &&
        !_paused &&
        _active &&
        TickerMode.valuesOf(context).enabled;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return SizedBox(
      height: 210,
      child: ColoredBox(
        color: const Color(0xFF080F14),
        child: asset == null && poster == null
            ? const SizedBox.shrink()
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (playing)
                    NativeAppearancePlayer(
                      asset:
                          'assets/overlay-appearances/$appearanceId-event-cycle.webp',
                      controls: false,
                      repeat: true,
                    )
                  else if (poster != null)
                    Image.memory(
                      poster,
                      key: Key('overlay-native-preview-$appearanceId'),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stack) =>
                          const SizedBox.shrink(),
                    )
                  else
                    Image.asset(
                      asset!,
                      key: Key('overlay-native-preview-$appearanceId'),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                      // Optional appearance packs are not part of source builds.
                      // Keep this skin's empty preview, never substitute another.
                      errorBuilder: (context, error, stack) =>
                          const SizedBox.shrink(),
                    ),
                  if (hasMotion)
                    Positioned(
                      right: 4,
                      bottom: 0,
                      child: TextButton(
                        key: const Key('overlay-preview-motion-toggle'),
                        onPressed: () => setState(() => _paused = !_paused),
                        child: Text(
                          _paused
                              ? (chinese ? '播放预览' : 'Play preview')
                              : (chinese ? '暂停预览' : 'Pause preview'),
                        ),
                      ),
                    ),
                  if (asset != null)
                    Positioned(
                      left: 4,
                      bottom: 0,
                      child: TextButton(
                        key: Key('overlay-preview-browse-$appearanceId'),
                        onPressed: () => showAppearanceMotionBrowser(
                          context,
                          appearanceId,
                          editorWindow: widget.editorWindow,
                          previewableIds: widget.previewableIds,
                        ),
                        child: Text(chinese ? '动画预览' : 'Browse motion'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
