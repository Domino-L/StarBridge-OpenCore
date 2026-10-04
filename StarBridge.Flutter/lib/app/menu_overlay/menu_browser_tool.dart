import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../platform/window/menu_browser_preferences.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../../features/overlay_settings/menu_browser_resume_controller.dart';
import '../localization/app_strings.dart';

import 'menu_bridge_style.dart';
import 'menu_browser_address.dart';
import 'menu_browser_state.dart';
import 'menu_local_call.dart';
import 'menu_workspace_controller.dart';
import 'menu_workspace_viewport.dart';
import 'menu_panel_idle.dart';

/// Native WebViews own pages. The surface holds only display state/address
/// drafts, with no browser script or account bridge.
class MenuBrowserTool extends StatefulWidget {
  const MenuBrowserTool({
    super.key,
    required this.call,
    required this.workspace,
    this.preferences = const MenuBrowserPreferences(),
    this.resume,
    this.safeMode = false,
  });
  final MenuLocalCall call;
  final MenuWorkspaceController workspace;
  final MenuBrowserPreferences preferences;
  final MenuBrowserResumeController? resume;
  final bool safeMode;
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
  List<Rect> lastOcclusions = const [];
  Size? workspaceSize;
  bool routeActive = true;
  MenuPanelIdleScope? idleScope;
  double? lastOpacity;
  MenuBrowserPreferences? _applied;
  Future<void>? _configuration;
  bool _restoreAttempted = false;
  bool _resumeRestoreFailed = false;
  MenuBrowserPreferences get effectivePreferences =>
      widget.preferences.effective(safeMode: widget.safeMode);
  void _resumeChanged() {
    if (mounted) setState(() {});
  }

  // Serialize configuration through the same native owner before any action.
  // A newer edit arriving during a reply is applied before the action proceeds.
  Future<void> _configure() async {
    if (_configuration case final pending?) return pending;
    final work = _applyConfiguration();
    _configuration = work;
    try {
      await work;
    } finally {
      _configuration = null;
    }
  }

  Future<void> _applyConfiguration() async {
    while (mounted && _applied != effectivePreferences) {
      final options = effectivePreferences;
      await widget
          .call('browserConfigure', {'preferences': options.toMap()})
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      _applied = options;
    }
  }

  @override
  void didUpdateWidget(covariant MenuBrowserTool old) {
    super.didUpdateWidget(old);
    if (old.resume != widget.resume) {
      old.resume?.removeListener(_resumeChanged);
      widget.resume?.addListener(_resumeChanged);
    }
    if (ready &&
        (widget.preferences != old.preferences ||
            widget.safeMode != old.safeMode)) {
      unawaited(_refreshConfiguration());
    }
  }

  Future<void> _refreshConfiguration() async {
    try {
      await _configure();
      if (!mounted) return;
      final failure = AppStrings.of(context).text('menu.browser.applyFailed');
      if (error == failure) setState(() => error = null);
      await _status(force: true);
    } on Object {
      if (mounted) {
        setState(
          () => error = AppStrings.of(context).text('menu.browser.applyFailed'),
        );
      }
    }
  }

  bool get blankPage =>
      state?.active.url == 'about:blank' &&
      state?.active.loading == false &&
      state?.active.failed == false;

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_changed);
    nativeViewportMenus.addListener(_sync);
    widget.resume?.addListener(_resumeChanged);
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
      await _configure();
      if (!mounted || epoch != _epoch) return;
      if (!_restoreAttempted && widget.resume != null) {
        await widget.resume!.load();
        if (!mounted || epoch != _epoch || widget.resume!.closed) return;
      }
      final saved = widget.resume?.saved;
      await widget
          .call('browserOpen', {
            'url': saved?.enabled == true && saved!.url != null
                ? saved.url
                : menuBrowserHome(provider: effectivePreferences.provider)
                      .toString(),
          })
          .timeout(const Duration(seconds: 20));
      if (!mounted || epoch != _epoch) return;
      if (!_restoreAttempted && widget.resume != null) {
        _restoreAttempted = true;
        final resume = widget.resume!;
        if (!mounted || epoch != _epoch || resume.closed) return;
        try {
          final saved = resume.saved;
          if (saved?.enabled == true && saved!.url != null) {
            final current = MenuBrowserState.parse(
              await widget
                  .call('browserState', const {})
                  .timeout(const Duration(seconds: 3)),
            );
            if (!mounted || epoch != _epoch || resume.closed) return;
            // Never overwrite a retained page, another tab or a loading/failed
            // view. This runs only when the user opens the browser, not startup.
            if (current.tabs.length == 1 &&
                current.active.url == 'about:blank' &&
                !current.active.loading &&
                !current.active.failed &&
                !current.active.unavailable &&
                identical(resume.saved, saved)) {
              await widget
                  .call('browserNavigate', {
                    'tabId': current.activeId,
                    'url': saved.url,
                  })
                  .timeout(const Duration(seconds: 20));
              if (!mounted || epoch != _epoch || resume.closed) return;
            }
          }
        } on Object {
          // Optional resume failure must not disguise a working browser as a
          // missing WebView runtime or prevent manual browsing.
          if (mounted && epoch == _epoch) _resumeRestoreFailed = true;
        }
      }
      setState(() {
        ready = true;
      });
      if (!_resumeRestoreFailed) {
        try {
          await _openHomeIfBlank(epoch, singleTab: true);
        } on Object {
          if (mounted && epoch == _epoch) {
            setState(() => error = '搜索引擎首页未能打开，请输入网址或搜索词重试。');
          }
        }
      }
      if (!mounted || epoch != _epoch) return;
      _changed();
      await _status(force: true);
    } on Object {
      if (mounted && epoch == _epoch) {
        setState(
          () => error = _applied != effectivePreferences
              ? AppStrings.of(context).text('menu.browser.applyFailed')
              : '浏览器无法启动。请确认已安装 WebView2，或稍后重试。',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => opening = false);
    }
  }

  Future<void> _openHomeIfBlank(int epoch, {bool singleTab = false}) async {
    final current = MenuBrowserState.parse(
      await widget
          .call('browserState', const {})
          .timeout(const Duration(seconds: 3)),
    );
    if (!mounted ||
        epoch != _epoch ||
        (singleTab && current.tabs.length != 1)) {
      return;
    }
    final tab = current.active;
    if (tab.url != 'about:blank' ||
        tab.loading ||
        tab.failed ||
        tab.unavailable) {
      return;
    }
    await widget
        .call('browserNavigate', {
          'tabId': tab.id,
          'url': menuBrowserHome(provider: effectivePreferences.provider)
              .toString(),
        })
        .timeout(const Duration(seconds: 20));
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
    final painted = MatrixUtils.transformRect(
      render.getTransformTo(null),
      Offset.zero & render.size,
    );
    final bounds = Rect.fromLTWH(
      painted.left * ratio,
      painted.top * ratio,
      painted.width * ratio,
      painted.height * ratio,
    );
    final shown =
        widget.workspace.panelsVisible &&
        widget.workspace.isOpen('browser') &&
        routeActive &&
        nativeViewportMenus.value == 0;
    final panels = widget.workspace.openPanels;
    final browserIndex = panels.indexWhere((panel) => panel.id == 'browser');
    final occlusions = workspaceSize == null || browserIndex < 0
        ? const <Rect>[]
        : MenuWorkspaceViewport.physicalRects(context, [
            for (final panel in panels.skip(browserIndex + 1))
              widget.workspace.paintBoundsFor(panel.id, workspaceSize!),
          ]).where((rect) => rect.overlaps(bounds)).toList();
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
        nativeShown == lastNativeVisible &&
        listEquals(occlusions, lastOcclusions) &&
        lastOpacity == (idleScope?.opacity ?? 1)) {
      return;
    }
    lastBounds = bounds;
    lastVisible = shown;
    lastNativeVisible = nativeShown;
    lastOcclusions = occlusions;
    lastOpacity = idleScope?.opacity ?? 1;
    unawaited(
      widget
          .call('browserBounds', {
            'visible': nativeShown,
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
            'opacity': lastOpacity,
            'occlusions': [
              for (final rect in occlusions)
                {
                  'x': rect.left,
                  'y': rect.top,
                  'width': rect.width,
                  'height': rect.height,
                },
            ],
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
      idleScope?.nativeInteraction(
        result is Map &&
            (result['interactionActive'] == true ||
                result['opacitySupported'] == false),
      );
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
      if (!next.active.loading &&
          !next.active.failed &&
          !next.active.unavailable) {
        unawaited(widget.resume?.confirmed(next.active.url));
      }
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
      await _configure();
      if (!mounted || epoch != _epoch) return;
      await widget
          .call(action, {
            'tabId': ?tabId,
            'url': ?(action == 'browserNewTab' || action == 'browserCloseTab'
                ? menuBrowserHome(provider: effectivePreferences.provider)
                      .toString()
                : url),
          })
          .timeout(const Duration(seconds: 20));
      if (!mounted || epoch != _epoch) return;
      if (action == 'browserNavigate') {
        _resumeRestoreFailed = false;
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
    final uri = menuBrowserAddress(
      input,
      provider: widget.preferences.provider,
    );
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
    nativeViewportMenus.removeListener(_sync);
    widget.resume?.removeListener(_resumeChanged);
    unawaited(
      widget
          .call('browserBounds', const {'visible': false})
          .catchError((Object _) => null),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    idleScope = MenuPanelIdleScope.of(context);
    workspaceSize = MenuWorkspaceViewport.sizeOf(context);
    routeActive =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        NativeViewportScope.isActive(context);
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
                        '已打开 ${state!.tabs.length} 个标签页，上限为 ${state!.limit} 个。请先关闭不需要的页面再打开新页面。',
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
                                ? _refreshConfiguration
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
                    if (widget.resume?.failed == true || _resumeRestoreFailed)
                      BridgeCaption(
                        AppStrings.of(context)
                            .text('menu.browser.resume.runtimeFailed'),
                      ),
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
