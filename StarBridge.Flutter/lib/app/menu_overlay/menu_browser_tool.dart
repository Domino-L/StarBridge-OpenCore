import 'menu_overlay_locale.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../features/common/social_read_activity.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../platform/window/menu_browser_preferences.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../../features/overlay_settings/menu_browser_resume_controller.dart';
import '../localization/app_strings.dart';
import 'menu_bridge_style.dart';
import 'menu_browser_address.dart';
import 'menu_browser_state.dart';
import 'menu_browser_tabs.dart';
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
  final _draftRevisions = <String, int>{};
  final _tabKeys = <String, GlobalKey>{};
  Timer? statusTimer;
  MenuBrowserState? state;
  bool ready = false, busy = false, opening = false;
  InteractionSource _openingSource = InteractionSource.programmatic;
  InteractionSource _commandSource = InteractionSource.programmatic;
  int _epoch = 0;
  int? _statusRequest;
  String? error;
  String? _errorKind;
  Rect? lastBounds;
  bool? lastVisible;
  bool? lastNativeVisible;
  List<Rect> lastOcclusions = const [];
  Size? workspaceSize;
  bool routeActive = true;
  bool _elementActive = true;
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
      if (_errorKind == 'configuration') {
        setState(() {
          error = null;
          _errorKind = null;
        });
      }
      await _status(force: true);
    } on Object {
      if (mounted) {
        setState(() {
          _errorKind = 'configuration';
          error = AppStrings.of(context).text('menu.browser.applyFailed');
        });
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
      _openingSource = captureStarBridgeActivationSource()();
      opening = true;
      error = null;
      _errorKind = null;
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
            setState(
              () =>
                  error = menuText(context, 'menu.overlay.browser.homeFailed'),
            );
          }
        }
      }
      if (!mounted || epoch != _epoch) return;
      _changed();
      await _status(force: true);
    } on Object {
      if (mounted && epoch == _epoch) {
        setState(() {
          _errorKind = _applied != effectivePreferences
              ? 'configuration'
              : 'startup';
          error = _errorKind == 'configuration'
              ? AppStrings.of(context).text('menu.browser.applyFailed')
              : menuText(context, 'menu.overlay.browser.startFailed');
        });
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

  @override
  void deactivate() {
    _elementActive = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _elementActive = true;
    _changed();
  }

  void _sync() {
    // Child hints release their lease while unmounting. mounted is still true
    // after deactivation, but their viewport Element cannot be inspected then.
    if (!mounted || !_elementActive || !ready) return;
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
            if (mounted) {
              setState(
                () => error = menuText(
                  context,
                  'menu.overlay.browser.interrupted',
                ),
              );
            }
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
        if (_errorKind == 'status') {
          error = null;
          _errorKind = null;
        }
        _drafts.removeWhere((id, _) => !next.tabs.any((tab) => tab.id == id));
        _draftRevisions.removeWhere(
          (id, _) => !next.tabs.any((tab) => tab.id == id),
        );
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
        setState(() {
          _errorKind = 'status';
          error = menuText(context, 'menu.overlay.browser.statusFailed');
        });
      }
    } finally {
      if (_statusRequest == epoch) _statusRequest = null;
    }
  }

  Future<void> _action(String action, {String? tabId, String? url}) async {
    if (!ready || busy) return;
    final submittedDraftRevision = _draftRevisions[tabId] ?? 0;
    final submittedEditingValue = address.value;
    final epoch = ++_epoch; // Retire any state poll started before this action.
    setState(() {
      _commandSource = captureStarBridgeActivationSource()();
      busy = true;
      error = null;
      _errorKind = null;
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
        // Editing stays available during a native request. A late success only
        // acknowledges the submitted generation, never a later draft (even if
        // the user edits back to the same text with new selection/composition).
        final stillActive = state?.activeId == tabId;
        final sameEditingValue =
            !stillActive || address.value == submittedEditingValue;
        if ((_draftRevisions[tabId] ?? 0) == submittedDraftRevision &&
            sameEditingValue) {
          _drafts.remove(tabId);
          if (stillActive) addressFocus.unfocus();
        } else if (stillActive && tabId != null) {
          // Selection/composition changes do not fire TextField.onChanged.
          _drafts[tabId] = address.value;
        }
      }
    } on Object catch (failure) {
      if (mounted && epoch == _epoch) {
        setState(
          () => error =
              failure is PlatformException &&
                  failure.code == 'menu.browser_tab_limit'
              ? menuText(context, 'menu.overlay.browser.tabLimit')
              : failure is PlatformException &&
                    failure.code == 'menu.browser_tab_stale'
              ? menuText(context, 'menu.overlay.browser.staleTab')
              : menuText(context, 'menu.overlay.browser.actionFailed'),
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
      setState(
        () => error = menuText(context, 'menu.overlay.browser.invalidAddress'),
      );
      return;
    }
    unawaited(_action('browserNavigate', tabId: tab.id, url: uri.toString()));
  }

  Widget _waiting(String phase, InteractionSource source, String label) =>
      KeyedSubtree(
        key: ValueKey(('browser-wait', phase, _epoch, state?.activeId)),
        // Keep the existing caption as the single reader status. This track
        // is not numeric progress and does not own the native page's loading.
        child: ExcludeSemantics(
          child: SocialReadActivity(
            key: ValueKey('menu-browser-$phase-activity'),
            source: source,
            opening: false,
            label: label,
            height: 2,
          ),
        ),
      );
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
                    MenuBrowserTabs(
                      state: state,
                      ready: ready,
                      busy: busy,
                      routeActive: routeActive,
                      workspace: widget.workspace,
                      keyForTab: (id) =>
                          _tabKeys.putIfAbsent(id, GlobalKey.new),
                      onSelect: (id) => _action('browserSelectTab', tabId: id),
                      onClose: (id) => _action('browserCloseTab', tabId: id),
                      onNew: () => _action('browserNewTab'),
                    ),
                    if (state != null && state!.tabs.length >= state!.limit)
                      BridgeCaption(
                        menuText(context, 'menu.overlay.browser.tabCount', {
                          'count': state!.tabs.length,
                          'limit': state!.limit,
                        }),
                      ),
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final item in {
                          'browserBack': menuText(
                            context,
                            'menu.overlay.browser.back',
                          ),
                          'browserForward': menuText(
                            context,
                            'menu.overlay.browser.forward',
                          ),
                          'browserReload': menuText(context, 'friends.refresh'),
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
                            label: menuText(
                              context,
                              'menu.overlay.browser.stop',
                            ),
                            onPressed: busy
                                ? null
                                : () => _action('browserStop', tabId: tab!.id),
                            child: Text(
                              menuText(context, 'menu.overlay.browser.stop'),
                            ),
                          ),
                        if (error != null)
                          BridgeMenuAction(
                            label: menuText(context, 'friends.retry'),
                            onPressed: opening || busy
                                ? null
                                : ready
                                ? _refreshConfiguration
                                : _open,
                            child: Text(menuText(context, 'friends.retry')),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: StarBridgeFieldFrame(
                              focusNode: addressFocus,
                              builder: (context, focus) => TextField(
                                key: const ValueKey('browser-address'),
                                controller: address,
                                focusNode: focus,
                                maxLength: 2048,
                                onChanged: (_) {
                                  if (tab != null) {
                                    _drafts[tab.id] = address.value;
                                    _draftRevisions[tab.id] =
                                        (_draftRevisions[tab.id] ?? 0) + 1;
                                  }
                                },
                                onSubmitted: (_) =>
                                    runStarBridgeSynchronousActivation(
                                      InteractionSource.keyboard,
                                      _navigate,
                                    ),
                                decoration: InputDecoration(
                                  hintText: menuText(
                                    context,
                                    'menu.overlay.browser.address',
                                  ),
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                          BridgeMenuAction(
                            label: menuText(context, 'menu.overlay.browser.go'),
                            onPressed: ready && !busy && tab != null
                                ? _navigate
                                : null,
                            child: Text(
                              menuText(context, 'menu.overlay.browser.go'),
                            ),
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
                      BridgeCaption(
                        menuText(context, 'menu.overlay.browser.unavailable'),
                      )
                    else if (tab?.failed == true)
                      BridgeCaption(
                        menuText(context, 'menu.overlay.browser.pageFailed'),
                      ),
                    if (busy)
                      _waiting(
                        'command',
                        _commandSource,
                        menuText(context, 'menu.overlay.browser.busy'),
                      )
                    else if (tab?.loading == true)
                      _waiting(
                        'page',
                        InteractionSource.programmatic,
                        menuText(context, 'menu.overlay.browser.loading'),
                      )
                    else if (!ready && error == null)
                      _waiting(
                        'starting',
                        _openingSource,
                        menuText(context, 'menu.overlay.browser.starting'),
                      ),
                    if (busy && tab?.loading != true)
                      BridgeCaption(
                        menuText(context, 'menu.overlay.browser.busy'),
                      ),
                    if (tab?.loading == true)
                      BridgeCaption(
                        menuText(context, 'menu.overlay.browser.loading'),
                      ),
                    if (!ready && error == null)
                      BridgeCaption(
                        menuText(context, 'menu.overlay.browser.starting'),
                      ),
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
                            Text(
                              menuText(context, 'menu.overlay.browser.empty'),
                            ),
                            const SizedBox(height: 12),
                            BridgeMenuAction(
                              label: menuText(
                                context,
                                'menu.overlay.browser.address',
                              ),
                              onPressed: () {
                                addressFocus.requestFocus();
                                final inputContext = addressFocus.context;
                                if (inputContext != null) {
                                  unawaited(
                                    Scrollable.ensureVisible(inputContext),
                                  );
                                }
                              },
                              child: Text(
                                menuText(
                                  context,
                                  'menu.overlay.browser.address',
                                ),
                              ),
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
