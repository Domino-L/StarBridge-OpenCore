import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';
import 'menu_workspace_controller.dart';

typedef MenuLocalCall = Future<Object?> Function(String, Map<String, Object?>);

/// Presentation state only. File selection, capture and WebView ownership stay
/// native; no file paths or browser scripts can be supplied by the surface.
class MenuLocalToolsController extends ChangeNotifier {
  MenuLocalToolsController(this.call);
  final MenuLocalCall call;
  Uint8List? reference, screenshot;
  String notice = '';
  bool busy = false, closed = false;
  bool showClock = true, showContext = true;
  bool restoreDesktop = false, snapWindows = false;
  double dimming = 133 / 255;
  Future<void> image({bool capture = false}) async {
    if (busy || closed) return;
    busy = true;
    notice = '';
    notifyListeners();
    try {
      final bytes = await call(capture ? 'capture' : 'image', const {});
      if (closed) return;
      if (bytes is Uint8List &&
          bytes.isNotEmpty &&
          bytes.length <= 32 * 1024 * 1024) {
        if (capture) {
          screenshot = bytes;
        } else {
          reference = bytes;
        }
      } else if (bytes != null) {
        notice = '图片无法读取，请选择 PNG、JPEG 或 BMP 图片（不超过 32 MB）。';
      }
    } on Object {
      if (!closed) notice = capture ? '截图未完成，请重试。' : '图片未打开，请重试。';
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> save() async {
    if (busy || closed || screenshot == null) return;
    busy = true;
    notice = '';
    notifyListeners();
    try {
      final saved = await call('save', const {});
      if (!closed) notice = saved == true ? '截图已保存。' : '未保存截图。';
    } on Object {
      if (!closed) notice = '保存未完成，请重试。';
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
    bool? snap,
  }) {
    showClock = clock ?? showClock;
    showContext = context ?? showContext;
    dimming = (dim ?? dimming).clamp(.3, .9);
    restoreDesktop = restore ?? restoreDesktop;
    snapWindows = snap ?? snapWindows;
    notifyListeners();
  }

  @override
  void dispose() {
    closed = true;
    reference = screenshot = null;
    super.dispose();
  }
}

class MenuImageTool extends StatefulWidget {
  const MenuImageTool({super.key, required this.tools, this.capture = false});
  final MenuLocalToolsController tools;
  final bool capture;
  @override
  State<MenuImageTool> createState() => _MenuImageToolState();
}

class _MenuImageToolState extends State<MenuImageTool> {
  final transform = TransformationController();
  double opacity = 1;
  int turns = 0;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.tools,
    builder: (context, _) {
      final tools = widget.tools,
          bytes = widget.capture
              ? widget.tools.screenshot
              : widget.tools.reference;
      return Column(
        children: [
          Flexible(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      BridgeMenuAction(
                        label: widget.capture ? '截取当前屏幕' : '选择图片',
                        onPressed: tools.busy
                            ? null
                            : () => tools.image(capture: widget.capture),
                        child: Text(widget.capture ? '截取当前屏幕' : '选择图片'),
                      ),
                      if (widget.capture)
                        BridgeMenuAction(
                          label: '保存截图',
                          onPressed: tools.busy || bytes == null
                              ? null
                              : tools.save,
                          child: const Text('保存截图'),
                        ),
                      BridgeMenuAction(
                        label: '适合窗口',
                        onPressed: () => transform.value = Matrix4.identity(),
                        child: const Text('适合窗口'),
                      ),
                      BridgeMenuAction(
                        label: '旋转',
                        onPressed: () =>
                            setState(() => turns = (turns + 1) % 4),
                        child: const Text('旋转'),
                      ),
                    ],
                  ),
                  if (tools.busy) const BridgeCaption('正在处理…'),
                  if (tools.notice.isNotEmpty) BridgeCaption(tools.notice),
                  if (!widget.capture)
                    Row(
                      children: [
                        const Text('透明度'),
                        Expanded(
                          child: Slider(
                            value: opacity,
                            min: .15,
                            onChanged: (value) =>
                                setState(() => opacity = value),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ClipRect(
              child: bytes == null
                  ? Center(
                      child: Text(
                        widget.capture
                            ? '点击截取当前屏幕。菜单不会出现在截图中。'
                            : '选择本机图片，可滚轮缩放、拖动查看。',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : InteractiveViewer(
                      transformationController: transform,
                      minScale: .2,
                      maxScale: 8,
                      child: SizedBox.expand(
                        child: Opacity(
                          opacity: opacity,
                          child: RotatedBox(
                            quarterTurns: turns,
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const Center(child: Text('无法显示这张图片。')),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      );
    },
  );
}

class MenuLocalSettings extends StatelessWidget {
  const MenuLocalSettings({
    super.key,
    required this.tools,
    required this.workspace,
  });
  final MenuLocalToolsController tools;
  final MenuWorkspaceController workspace;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tools,
    builder: (context, _) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('窗口与恢复'),
            BridgeMenuAction(
              label: '保留离开时的桌面',
              onPressed: () => tools.settings(restore: !tools.restoreDesktop),
              child: Text('${tools.restoreDesktop ? "✓" : "—"} 保留离开时的桌面'),
            ),
            const BridgeCaption('下次打开菜单时，恢复未关闭的窗口、位置、大小和前后顺序；重启应用后也保留。'),
            const BridgeCaption('只保存桌面布局，不保存私信正文、草稿、截图或参考图。应用重启后浏览器为空白页。'),
            BridgeMenuAction(
              label: '窗口边缘吸附',
              onPressed: () => tools.settings(snap: !tools.snapWindows),
              child: Text('${tools.snapWindows ? "✓" : "—"} 窗口边缘吸附'),
            ),
            BridgeMenuAction(
              label: '重置窗口位置',
              onPressed: workspace.resetPlacements,
              child: const Text('重置窗口位置'),
            ),
            const SizedBox(height: 12),
            BridgeMenuAction(
              label: '显示时间',
              onPressed: () => tools.settings(clock: !tools.showClock),
              child: Text('${tools.showClock ? "✓" : "—"} 显示时间'),
            ),
            BridgeMenuAction(
              label: '显示状态栏',
              onPressed: () => tools.settings(context: !tools.showContext),
              child: Text('${tools.showContext ? "✓" : "—"} 显示状态栏'),
            ),
            const SizedBox(height: 12),
            const Text('背景压暗'),
            Slider(
              value: tools.dimming,
              min: .3,
              max: .9,
              onChanged: (value) => tools.settings(dim: value),
            ),
            const BridgeCaption('只调整菜单，不改变信息浮层或游戏画面。'),
          ],
        ),
      ),
    ),
  );
}

class MenuBrowserTool extends StatefulWidget {
  const MenuBrowserTool({
    super.key,
    required this.call,
    required this.workspace,
  });
  final MenuLocalCall call;
  final MenuWorkspaceController workspace;
  @override
  State<MenuBrowserTool> createState() => _MenuBrowserToolState();
}

class _MenuBrowserToolState extends State<MenuBrowserTool> {
  final address = TextEditingController();
  final addressFocus = FocusNode();
  final viewport = GlobalKey();
  Timer? statusTimer;
  bool statusBusy = false, canBack = false, canForward = false, loading = false;
  String currentUrl = '';
  String? error;
  bool ready = false, busy = false;
  Rect? lastBounds;
  bool? lastVisible;
  @override
  void initState() {
    super.initState();
    addressFocus.addListener(_addressFocusChanged);
    widget.workspace.addListener(_changed);
    unawaited(_open());
  }

  void _addressFocusChanged() {
    if (!addressFocus.hasFocus && currentUrl.isNotEmpty) {
      address.text = currentUrl == 'about:blank' ? '' : currentUrl;
    }
  }

  Future<void> _open() async {
    try {
      await widget
          .call('browserOpen', const {})
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          ready = true;
          error = null;
        });
        _changed();
      }
    } on Object {
      if (mounted) setState(() => error = '浏览器无法启动。请确认已安装 WebView2，或稍后重试。');
    }
  }

  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted || !ready) return;
    final render = viewport.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final ratio = MediaQuery.devicePixelRatioOf(context),
        origin = render.localToGlobal(Offset.zero);
    final bounds = Rect.fromLTWH(
      origin.dx * ratio,
      origin.dy * ratio,
      render.size.width * ratio,
      render.size.height * ratio,
    );
    final shown =
        widget.workspace.visible &&
        widget.workspace.isOpen('browser') &&
        widget.workspace.activeId == 'browser';
    if (shown) {
      statusTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _status(),
      );
    } else {
      statusTimer?.cancel();
      statusTimer = null;
    }
    if (bounds == lastBounds && shown == lastVisible) return;
    lastBounds = bounds;
    lastVisible = shown;
    unawaited(
      widget
          .call('browserBounds', {
            'visible': shown,
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          })
          .catchError((Object _) {
            if (mounted) setState(() => error = '浏览器显示中断，请重新打开窗口。');
            return null;
          }),
    );
  }

  Future<void> _status() async {
    if (!mounted || statusBusy || !ready || lastVisible != true) return;
    statusBusy = true;
    try {
      final state = await widget
          .call('browserState', const {})
          .timeout(const Duration(seconds: 3));
      if (!mounted ||
          lastVisible != true ||
          state is! Map ||
          state['url'] is! String) {
        return;
      }
      final url = state['url'] as String;
      if (url.length > 16384) return;
      setState(() {
        canBack = state['back'] == true;
        canForward = state['forward'] == true;
        loading = state['loading'] == true;
        if (url != currentUrl && !addressFocus.hasFocus) {
          address.text = url == 'about:blank' ? '' : url;
        }
        currentUrl = url;
        if (state['failed'] == true) error = '网页未能打开，请检查地址或刷新重试。';
      });
    } on Object {
      if (mounted && lastVisible == true) {
        setState(() => error = '浏览器状态读取失败，请重新打开窗口。');
      }
    } finally {
      statusBusy = false;
    }
  }

  Future<void> _action(String action, [String? url]) async {
    if (!ready || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget
          .call(action, {'url': ?url})
          .timeout(const Duration(seconds: 10));
    } on Object {
      if (mounted) setState(() => error = '操作未完成，请检查地址或重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _navigate() {
    final input = address.text.trim();
    if (input.isEmpty) return;
    var uri = Uri.tryParse(input);
    if (uri == null || (!uri.hasScheme && !input.contains('.'))) {
      uri = Uri.https('www.bing.com', '/search', {'q': input});
    } else if (!uri.hasScheme) {
      uri = Uri.tryParse('https://$input');
    }
    if (uri == null ||
        !const ['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      setState(() => error = '请输入 HTTP/HTTPS 地址或搜索词。');
      return;
    }
    unawaited(_action('browserNavigate', uri.toString()));
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    addressFocus.removeListener(_addressFocusChanged);
    addressFocus.dispose();
    widget.workspace.removeListener(_changed);
    address.dispose();
    unawaited(
      widget
          .call('browserBounds', const {'visible': false})
          .catchError((Object _) => null),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _changed();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          flex: 2,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const {
                      'browserBack': '后退',
                      'browserForward': '前进',
                      'browserReload': '刷新',
                    }.entries)
                      BridgeMenuAction(
                        label: item.value,
                        onPressed:
                            ready &&
                                !busy &&
                                (item.key != 'browserBack' || canBack) &&
                                (item.key != 'browserForward' || canForward)
                            ? () => _action(item.key)
                            : null,
                        child: Text(item.value),
                      ),
                    if (error != null && !ready)
                      BridgeMenuAction(
                        label: '重试',
                        onPressed: _open,
                        child: const Text('重试'),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: address,
                          focusNode: addressFocus,
                          maxLength: 2048,
                          onSubmitted: (_) => _navigate(),
                          decoration: const InputDecoration(
                            hintText: '输入网址或搜索词',
                            counterText: '',
                          ),
                        ),
                      ),
                      BridgeMenuAction(
                        label: '访问',
                        onPressed: ready && !busy ? _navigate : null,
                        child: const Text('访问'),
                      ),
                    ],
                  ),
                ),
                if (error != null) Text(error!),
                if (loading) const BridgeCaption('正在加载网页…'),
                if (!ready && error == null) const BridgeCaption('正在启动浏览器…'),
              ],
            ),
          ),
        ),
        Expanded(flex: 3, child: SizedBox.expand(key: viewport)),
      ],
    );
  }
}
