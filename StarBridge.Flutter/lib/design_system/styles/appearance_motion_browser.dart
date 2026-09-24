import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/window/overlay_editor_window_port.dart';

import 'native_appearance_player.dart';

Future<void> showAppearanceMotionBrowser(
  BuildContext context,
  String skin, {
  OverlayEditorWindowPort editorWindow = const UnavailableOverlayEditorWindow(),
  Set<String> previewableIds = const {'Default', 'NightShadow'},
}) => showDialog<void>(
  context: context,
  builder: (_) => _AppearanceMotionBrowser(
    initialSkin: skin,
    editorWindow: editorWindow,
    previewableIds: previewableIds,
  ),
);

class _AppearanceMotionBrowser extends StatefulWidget {
  const _AppearanceMotionBrowser({
    required this.initialSkin,
    required this.editorWindow,
    required this.previewableIds,
  });
  final String initialSkin;
  final OverlayEditorWindowPort editorWindow;
  final Set<String> previewableIds;
  @override
  State<_AppearanceMotionBrowser> createState() =>
      _AppearanceMotionBrowserState();
}

class _AppearanceMotionBrowserState extends State<_AppearanceMotionBrowser> {
  late String _skin = widget.previewableIds.contains(widget.initialSkin)
      ? widget.initialSkin
      : 'Default';
  String _mode = 'notice-in';
  bool _opening = false;
  bool _failed = false;

  Future<void> _fullscreen() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    final navigator = Navigator.of(context, rootNavigator: true);
    final window = widget.editorWindow;
    final skin = _skin;
    var entered = false;
    try {
      await window.enter();
      entered = true;
      if (!navigator.mounted) return;
      await navigator.push<void>(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              _FullscreenTransition(skin: skin, window: window),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (entered) {
        try {
          await window.exit();
        } catch (_) {
          if (mounted) setState(() => _failed = true);
        }
      }
      if (mounted) setState(() => _opening = false);
    }
  }

  static const _modes = {
    'flow': ('流光', 'Light flow'),
    'notice-in': ('公告弹出', 'Announcement in'),
    'notice-out': ('公告收起', 'Announcement out'),
    'event-in': ('事件弹出', 'Event in'),
    'event-out': ('事件收起', 'Event out'),
    'event-cycle': ('事件交替', 'Event sequence'),
    'transition': ('启动转场', 'Startup transition'),
  };

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      zh ? '外观动画预览' : 'Appearance motion preview',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(zh ? '关闭' : 'Close'),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      key: const Key('appearance-motion-skin'),
                      value: _skin,
                      isExpanded: true,
                      items:
                          [
                                DropdownMenuItem(
                                  value: 'Default',
                                  child: Text(zh ? '舰队标准' : 'Fleet Standard'),
                                ),
                                DropdownMenuItem(
                                  value: 'NightShadow',
                                  child: Text(zh ? '夜影' : 'Night Shadow'),
                                ),
                                DropdownMenuItem(
                                  value: 'Verdict',
                                  child: Text(zh ? '裁决' : 'Verdict'),
                                ),
                              ]
                              .where(
                                (item) =>
                                    widget.previewableIds.contains(item.value),
                              )
                              .toList(),
                      onChanged: (value) => setState(() {
                        _skin = value!;
                        if (_skin == 'Default' && _mode == 'flow') {
                          _mode = 'transition';
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButton<String>(
                      key: const Key('appearance-motion-mode'),
                      value: _mode,
                      isExpanded: true,
                      items: _modes.entries
                          .where(
                            (entry) =>
                                _skin != 'Default' || entry.key != 'flow',
                          )
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(zh ? entry.value.$1 : entry.value.$2),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _mode = value!),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ColoredBox(
                  color: const Color(0xFF080F14),
                  child: _mode == 'transition'
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                zh ? '2560 × 1440 · 原尺寸 · 模块联动' : '2560 × 1440 · Native pixels · Linked modules',
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                key: const Key(
                                  'appearance-transition-fullscreen',
                                ),
                                onPressed: _opening ? null : _fullscreen,
                                child: Text(
                                  zh ? '全屏播放转场' : 'Play transition fullscreen',
                                ),
                              ),
                              if (_failed)
                                Text(
                                  zh
                                      ? '未能切换窗口，请重试。'
                                      : 'Could not switch window. Try again.',
                                ),
                            ],
                          ),
                        )
                      : NativeAppearancePlayer(
                          asset:
                              'assets/overlay-appearances/$_skin-$_mode.webp',
                          repeat: _mode == 'event-cycle',
                        ),
                ),
              ),
              Text(
                zh
                    ? '仅播放预览，不改变浮层或发送消息。'
                    : 'Preview only. No overlay changes or messages are sent.',
              ),
              if (MediaQuery.disableAnimationsOf(context))
                Text(
                  zh
                      ? '已减少动态效果，可拖动进度查看画面。'
                      : 'Reduced motion is on. Scrub to inspect frames.',
                ),
              if (_skin == 'Default' && _mode == 'notice-out')
                Text(
                  zh
                      ? '舰队标准的公告直接收起，没有独立收起动画。'
                      : 'Fleet Standard announcements close instantly.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenTransition extends StatefulWidget {
  const _FullscreenTransition({required this.skin, required this.window});
  final String skin;
  final OverlayEditorWindowPort window;
  @override
  State<_FullscreenTransition> createState() => _FullscreenTransitionState();
}

class _FullscreenTransitionState extends State<_FullscreenTransition> {
  bool _leaving = false;
  bool _canPop = false;
  bool _failed = false;
  bool _covered = false;

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await widget.window.exit();
      if (!mounted) return;
      setState(() => _canPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _leaving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _leave();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.f11)) {
            _leave();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF080F14),
          body: Stack(
            fit: StackFit.expand,
            children: [
              NativeAppearancePlayer(
                asset:
                    'assets/overlay-appearances/${widget.skin}-transition.webp',
                nativePixels: true,
                coveredInterval: widget.skin == 'Verdict'
                    ? (
                        const Duration(milliseconds: 820),
                        const Duration(milliseconds: 1040),
                      )
                    : null,
                onCoveredChanged: (covered) {
                  if (mounted && covered != _covered) {
                    setState(() => _covered = covered);
                  }
                },
              ),
              if (!_covered)
                Positioned(
                  right: 20,
                  top: 12,
                  child: TextButton(
                    key: const Key('appearance-transition-exit'),
                    onPressed: _leaving ? null : _leave,
                    child: Text(
                      _failed
                          ? (zh ? '重试退出' : 'Retry exit')
                          : (zh ? '退出全屏 · Esc' : 'Exit fullscreen · Esc'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
