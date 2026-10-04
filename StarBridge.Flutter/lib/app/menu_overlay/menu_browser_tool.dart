import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/icons/standard_icon.dart';

import 'menu_bridge_style.dart';
import 'menu_browser_address.dart';
import 'menu_browser_state.dart';
import 'menu_local_call.dart';
import 'menu_workspace_controller.dart';

/// Native WebViews own pages. The surface holds only display state/address
/// drafts, with no browser script or account bridge.
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
  final toolbarScroll = ScrollController();
  final viewport = GlobalKey();
  final _drafts = <String, TextEditingValue>{};
  final _tabKeys = <String, GlobalKey>{};
  Timer? statusTimer;
  MenuBrowserState? state;
  bool ready = false, busy = false, opening = false;
  int _epoch = 0;
  int? _statusRequest;
  String? error;
  Rect? lastBounds;
  bool? lastVisible;
  bool? lastNativeVisible;

  bool get blankPage =>
      state?.active.url == 'about:blank' &&
      state?.active.loading == false &&
      state?.active.failed == false;

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_changed);
    unawaited(_open());
  }

  Future<void> _open() async {
    if (opening) return;
    setState(() {
      opening = true;
      error = null;
    });
    final epoch = ++_epoch;
    try {
      await widget
          .call('browserOpen', const {})
          .timeout(const Duration(seconds: 20));
      if (!mounted || epoch != _epoch) return;
      setState(() {
        ready = true;
      });
      _changed();
      await _status(force: true);
    } on Object {
      if (mounted && epoch == _epoch) {
        setState(() => error = '浏览器无法启动。请确认已安装 WebView2，或稍后重试。');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => opening = false);
    }
  }

  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // Workspace activation may change without rebuilding this retained child.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sync() {
    if (!mounted || !ready) return;
    final render = viewport.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final origin = render.localToGlobal(Offset.zero);
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
    final nativeShown = shown && (!blankPage || busy);
    if (bounds == lastBounds &&
        shown == lastVisible &&
        nativeShown == lastNativeVisible) {
      return;
    }
    lastBounds = bounds;
    lastVisible = shown;
    lastNativeVisible = nativeShown;
    unawaited(
      widget
          .call('browserBounds', {
            'visible': nativeShown,
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

  Future<void> _status({bool force = false}) async {
    if (!mounted ||
        !ready ||
        (!force && (busy || lastVisible != true || _statusRequest == _epoch))) {
      return;
    }
    final epoch = _epoch;
    _statusRequest = epoch;
    try {
      final result = await widget
          .call('browserState', const {})
          .timeout(const Duration(seconds: 3));
      if (!mounted || epoch != _epoch || (!force && lastVisible != true)) {
        return;
      }
      final next = MenuBrowserState.parse(result);
      final changed = state?.activeId != next.activeId;
      setState(() {
        state = next;
        if (error == '暂时无法更新标签页，请点击刷新重试。') error = null;
        _drafts.removeWhere((id, _) => !next.tabs.any((tab) => tab.id == id));
        _tabKeys.removeWhere((id, _) => !next.tabs.any((tab) => tab.id == id));
        if (changed || !addressFocus.hasFocus) {
          address.value =
              _drafts[next.activeId] ??
              TextEditingValue(
                text: next.active.url == 'about:blank' ? '' : next.active.url,
              );
        }
      });
      if (changed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final context = _tabKeys[state?.activeId]?.currentContext;
          if (context != null) unawaited(Scrollable.ensureVisible(context));
        });
      }
    } on Object {
      if (mounted && epoch == _epoch && (force || lastVisible == true)) {
        setState(() => error = '暂时无法更新标签页，请点击刷新重试。');
      }
    } finally {
      if (_statusRequest == epoch) _statusRequest = null;
    }
  }

  Future<void> _action(String action, {String? tabId, String? url}) async {
    if (!ready || busy) return;
    final epoch = ++_epoch; // Retire any state poll started before this action.
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget
          .call(action, {'tabId': ?tabId, 'url': ?url})
          .timeout(const Duration(seconds: 20));
      if (!mounted || epoch != _epoch) return;
      if (action == 'browserNavigate') {
        _drafts.remove(tabId);
        addressFocus.unfocus();
      }
    } on Object catch (failure) {
      if (mounted && epoch == _epoch) {
        setState(
          () => error =
              failure is PlatformException &&
                  failure.code == 'menu.browser_tab_limit'
              ? '标签页已达上限，请先关闭不需要的页面。'
              : failure is PlatformException &&
                    failure.code == 'menu.browser_tab_stale'
              ? '标签页已变化，请在当前页面重新操作。'
              : '操作未完成，请检查当前标签页后重试。',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) {
        await _status(force: true);
        if (mounted && epoch == _epoch) setState(() => busy = false);
      }
    }
  }

  void _navigate() {
    final input = address.text.trim();
    final tab = state?.active;
    if (input.isEmpty || tab == null) return;
    final uri = menuBrowserAddress(input);
    if (uri == null) {
      setState(() => error = '请输入 HTTP/HTTPS 地址或搜索词。');
      return;
    }
    unawaited(_action('browserNavigate', tabId: tab.id, url: uri.toString()));
  }

  Widget _tabs() {
    final current = state;
    final ink = MenuBridgeColors.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in current?.tabs ?? <MenuBrowserTab>[])
                  Container(
                    key: _tabKeys.putIfAbsent(tab.id, GlobalKey.new),
                    constraints: const BoxConstraints(maxWidth: 216),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: tab.id == current?.activeId
                          ? ink.selected
                          : ink.panel,
                      border: Border(
                        bottom: BorderSide(
                          color: tab.id == current?.activeId
                              ? ink.blue
                              : ink.line,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Tooltip(
                            message: tab.url == 'about:blank'
                                ? '新标签页'
                                : tab.url,
                            child: BridgeMenuAction(
                              key: ValueKey('browser-tab-${tab.id}'),
                              label: tab.title.isEmpty ? '新标签页' : tab.title,
                              selected: tab.id == current?.activeId,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              onPressed: busy
                                  ? null
                                  : () => _action(
                                      'browserSelectTab',
                                      tabId: tab.id,
                                    ),
                              child: Text(
                                tab.title.isEmpty ? '新标签页' : tab.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: ValueKey('browser-close-${tab.id}'),
                          tooltip: '关闭标签页',
                          onPressed: busy
                              ? null
                              : () => _action('browserCloseTab', tabId: tab.id),
                          icon: const StandardIcon(
                            StandardIconSemantic.close,
                            size: 16,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: const EdgeInsets.all(8),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('browser-new-tab'),
          tooltip: current != null && current.tabs.length >= current.limit
              ? '最多 ${current.limit} 个标签页'
              : '新建标签页',
          onPressed:
              ready &&
                  !busy &&
                  current != null &&
                  current.tabs.length < current.limit
              ? () => _action('browserNewTab')
              : null,
          icon: const StandardIcon(StandardIconSemantic.add),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _epoch++;
    statusTimer?.cancel();
    addressFocus.dispose();
    toolbarScroll.dispose();
    address.dispose();
    widget.workspace.removeListener(_changed);
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
    final tab = state?.active;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .6),
            child: Scrollbar(
              controller: toolbarScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: toolbarScroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tabs(),
                    if (state != null && state!.tabs.length >= state!.limit)
                      BridgeCaption(
                        '已打开 ${state!.limit} 个标签页，请先关闭不需要的页面再打开新页面。',
                      ),
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final item in const {
                          'browserBack': '后退',
                          'browserForward': '前进',
                          'browserReload': '刷新',
                        }.entries)
                          BridgeMenuAction(
                            label: item.value,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            onPressed:
                                ready &&
                                    !busy &&
                                    tab != null &&
                                    (item.key != 'browserBack' || tab.back) &&
                                    (item.key != 'browserForward' ||
                                        tab.forward)
                                ? () => _action(item.key, tabId: tab.id)
                                : null,
                            child: Text(item.value),
                          ),
                        if (tab?.loading == true)
                          BridgeMenuAction(
                            label: '停止加载',
                            onPressed: busy
                                ? null
                                : () => _action('browserStop', tabId: tab!.id),
                            child: const Text('停止加载'),
                          ),
                        if (error != null)
                          BridgeMenuAction(
                            label: '重试',
                            onPressed: opening || busy
                                ? null
                                : ready
                                ? () => _status(force: true)
                                : _open,
                            child: const Text('重试'),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('browser-address'),
                              controller: address,
                              focusNode: addressFocus,
                              maxLength: 2048,
                              onChanged: (_) {
                                if (tab != null) {
                                  _drafts[tab.id] = address.value;
                                }
                              },
                              onSubmitted: (_) => _navigate(),
                              decoration: const InputDecoration(
                                hintText: '输入网址或搜索词',
                                counterText: '',
                              ),
                            ),
                          ),
                          BridgeMenuAction(
                            label: '访问',
                            onPressed: ready && !busy && tab != null
                                ? _navigate
                                : null,
                            child: const Text('访问'),
                          ),
                        ],
                      ),
                    ),
                    if (error != null) Text(error!),
                    if (tab?.unavailable == true)
                      const BridgeCaption(
                        '浏览器暂时不可用，请点击刷新重新启动此标签页。若仍无法启动，请检查 WebView2 是否已安装。',
                      )
                    else if (tab?.failed == true)
                      const BridgeCaption('网页未能打开，请检查地址或刷新重试。'),
                    if (tab?.loading == true) const BridgeCaption('正在加载网页…'),
                    if (!ready && error == null)
                      const BridgeCaption('正在启动浏览器…'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SizedBox.expand(
              key: viewport,
              child: blankPage
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('输入网址或搜索词，开始浏览'),
                            const SizedBox(height: 12),
                            BridgeMenuAction(
                              label: '输入网址或搜索词',
                              onPressed: () {
                                addressFocus.requestFocus();
                                final inputContext = addressFocus.context;
                                if (inputContext != null) {
                                  unawaited(
                                    Scrollable.ensureVisible(inputContext),
                                  );
                                }
                              },
                              child: const Text('输入网址或搜索词'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
