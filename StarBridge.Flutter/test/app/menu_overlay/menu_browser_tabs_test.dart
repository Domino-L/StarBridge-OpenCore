import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_state.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_tool.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_native_popup.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_panel_idle.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_preferences.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_resume_controller.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, capture, loadFonts;

Map<String, Object?> page(
  String id, {
  String? title,
  String? url,
  bool failed = false,
  bool loading = false,
}) => {
  'id': id,
  'title': title ?? '页面 $id',
  'url': url ?? 'https://example.test/$id',
  'back': id == 't1',
  'forward': false,
  'loading': loading,
  'failed': failed,
};

final class BrowserFake {
  final calls = <(String, Map<String, Object?>)>[];
  final tabs = <Map<String, Object?>>[page('t1'), page('t2')];
  String active = 't1';
  int serial = 2;
  Completer<Object?>? pendingState;
  Completer<Object?>? pendingAction;
  Object? failure;
  int limit = 8;
  Map<String, Object?>? configured;
  bool failConfiguration = false;
  bool interactionActive = false, opacitySupported = true;
  Completer<Object?>? pendingConfiguration;
  Map<String, Object?> snapshot() => {
    'tabs': tabs.map((tab) => {...tab}).toList(),
    'activeTabId': active,
    'tabLimit': limit,
    'interactionActive': interactionActive,
    'opacitySupported': opacitySupported,
  };
  Future<Object?> call(String action, Map<String, Object?> args) async {
    calls.add((action, {...args}));
    if (action == 'browserConfigure') {
      if (failConfiguration) throw StateError('synthetic config failure');
      if (pendingConfiguration case final pending?) await pending.future;
      configured = Map<String, Object?>.from(args['preferences'] as Map);
      limit = configured!['tabLimit'] as int;
      return null;
    }
    if (action == 'browserState') {
      final pending = pendingState;
      pendingState = null;
      return pending == null ? snapshot() : pending.future;
    }
    if (action == 'browserOpen' || action == 'browserBounds') return null;
    if (failure != null) {
      final error = failure!;
      failure = null;
      throw error;
    }
    if (pendingAction != null) return pendingAction!.future;
    if (action == 'browserNewTab') {
      active = 't${++serial}';
      tabs.add(
        page(active, title: '', url: args['url'] as String? ?? 'about:blank'),
      );
    } else if (action == 'browserSelectTab') {
      active = args['tabId']! as String;
    } else if (action == 'browserCloseTab') {
      tabs.removeWhere((tab) => tab['id'] == args['tabId']);
      if (tabs.isEmpty) {
        tabs.add(
          page(
            't${++serial}',
            title: '',
            url: args['url'] as String? ?? 'about:blank',
          ),
        );
      }
      if (active == args['tabId']) active = tabs.last['id']! as String;
    } else if (action == 'browserNavigate') {
      tabs.firstWhere((tab) => tab['id'] == args['tabId'])['url'] = args['url'];
    }
    return null;
  }
}

MenuWorkspaceController workspace() => MenuWorkspaceController(
  scope: Object(),
  panels: [
    MenuPanelSpec(
      id: 'browser',
      initialBounds: const Rect.fromLTWH(0, 0, 900, 650),
    ),
    MenuPanelSpec(
      id: 'image',
      initialBounds: const Rect.fromLTWH(0, 0, 400, 300),
    ),
  ],
)..open('browser');

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Future<void> mount(
  WidgetTester tester,
  BrowserFake native,
  MenuWorkspaceController work, {
  double width = 900,
  double height = 650,
  double scale = 1,
  double interfaceScale = 1,
  double pixelRatio = 1,
  bool safeMode = false,
  GlobalKey? boundary,
  MenuBrowserPreferences preferences = const MenuBrowserPreferences(),
  MenuBrowserResumeController? resume,
}) async {
  size(tester, Size(width, height));
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: app(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            devicePixelRatio: pixelRatio,
          ),
          child: Transform.scale(
            scale: interfaceScale,
            alignment: Alignment.topLeft,
            child: MenuBrowserTool(
              safeMode: safeMode,
              call: native.call,
              workspace: work,
              preferences: preferences,
              resume: resume,
            ),
          ),
        ),
      ),
    ),
  );
  await flush(tester);
}

void main() {
  testWidgets('native status protects idle browser and hides stop polling', (
    tester,
  ) async {
    final native = BrowserFake(), work = workspace();
    size(tester, const Size(1000, 800));
    await tester.pumpWidget(
      app(
        MenuOverlayWorkspace(
          controller: work,
          closeLabel: '关闭',
          moveLabel: '移动',
          resizeLabel: '缩放',
          panels: [
            MenuPanelContent(
              id: 'browser',
              title: '浏览器',
              icon: StarBridgeIconSemantic.friends,
              builder: (_, _) =>
                  MenuBrowserTool(call: native.call, workspace: work),
            ),
          ],
        ),
      ),
    );
    await flush(tester);
    Map<String, Object?> bounds() =>
        native.calls.lastWhere((call) => call.$1 == 'browserBounds').$2;
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(bounds()['opacity'], 1);
    await tester.pump(const Duration(milliseconds: 110));
    await flush(tester);
    expect(bounds()['opacity'], allOf(greaterThan(.7), lessThan(1)));
    await tester.pump(const Duration(milliseconds: 110));
    await flush(tester);
    expect(bounds()['opacity'], .7);
    native.interactionActive = true;
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(bounds()['opacity'], 1);
    await tester.pump(const Duration(seconds: 6));
    await flush(tester);
    expect(bounds()['opacity'], 1);
    native.interactionActive = false;
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 220));
    await flush(tester);
    expect(bounds()['opacity'], .7);
    native.opacitySupported = false;
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(bounds()['opacity'], 1);
    work.togglePanelsVisibility();
    await flush(tester);
    final stateCalls = native.calls
        .where((call) => call.$1 == 'browserState')
        .length;
    await tester.pump(const Duration(seconds: 10));
    await flush(tester);
    expect(
      native.calls.where((call) => call.$1 == 'browserState').length,
      stateCalls,
    );
    expect(bounds()['visible'], false);
    expect(find.byType(MenuPanelIdle, skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    work.dispose();
  });
  testWidgets(
    'popup routes keep native browser hidden through exit animation',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      final popups = MenuNativePopupObserver();
      size(tester, const Size(900, 650));
      late BuildContext routeContext;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [popups],
          home: Builder(
            builder: (context) {
              routeContext = context;
              return app(MenuBrowserTool(call: native.call, workspace: work));
            },
          ),
        ),
      );
      await flush(tester);
      unawaited(
        showDialog<void>(
          context: routeContext,
          builder: (_) => const AlertDialog(content: Text('确认')),
        ),
      );
      await tester.pumpAndSettle();
      expect(nativeViewportMenus.value, 1);
      expect(
        native.calls
            .lastWhere((call) => call.$1 == 'browserBounds')
            .$2['visible'],
        false,
      );
      Navigator.of(routeContext).pop();
      await tester.pump(const Duration(milliseconds: 20));
      expect(nativeViewportMenus.value, 1);
      expect(
        native.calls
            .lastWhere((call) => call.$1 == 'browserBounds')
            .$2['visible'],
        false,
      );
      await tester.pumpAndSettle();
      expect(nativeViewportMenus.value, 0);
      expect(
        native.calls
            .lastWhere((call) => call.$1 == 'browserBounds')
            .$2['visible'],
        true,
      );
      await tester.pumpWidget(const SizedBox());
      popups.dispose();
      work.dispose();
    },
  );
  testWidgets('actual workspace clips only higher panels at scaled DPI', (
    tester,
  ) async {
    final native = BrowserFake(), work = workspace();
    size(tester, const Size(1200, 800));
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            devicePixelRatio: 1.5,
          ),
          child: Transform.scale(
            scale: .85,
            alignment: Alignment.topLeft,
            child: MenuOverlayWorkspace(
              controller: work,
              closeLabel: '关闭',
              moveLabel: '移动',
              resizeLabel: '缩放',
              panels: [
                MenuPanelContent(
                  id: 'browser',
                  title: '浏览器',
                  icon: StarBridgeIconSemantic.friends,
                  builder: (_, _) =>
                      MenuBrowserTool(call: native.call, workspace: work),
                ),
                MenuPanelContent(
                  id: 'image',
                  title: '图片',
                  icon: StarBridgeIconSemantic.friends,
                  builder: (_, _) => MenuNativePopup(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: () {},
                        child: const Text('测试菜单'),
                      ),
                    ],
                    builder: (_, controller, _) => TextButton(
                      onPressed: controller.open,
                      child: const Text('打开弹出菜单'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await flush(tester);
    work.open('image');
    await flush(tester);
    Map<String, Object?> bounds() =>
        native.calls.lastWhere((call) => call.$1 == 'browserBounds').$2;
    void expectClip() {
      final panel = tester.getRect(
        find.byKey(const ValueKey('menu-panel-image')),
      );
      final clip = (bounds()['occlusions'] as List).single as Map;
      expect(bounds()['visible'], true);
      expect(clip['x'], closeTo(panel.left * 1.5, .01));
      expect(clip['y'], closeTo(panel.top * 1.5, .01));
      expect(clip['width'], closeTo(panel.width * 1.5, .01));
      expect(clip['height'], closeTo(panel.height * 1.5, .01));
    }

    expectClip();
    final lease = work.openPanels.last;
    // Pure images report only their existing painted viewport. Transparent
    // title/tool slots must not punch large holes through the native page.
    const imageViewport = Rect.fromLTWH(0, 120, 320, 160);
    work.setPaintBounds(lease, imageViewport);
    await flush(tester);
    final imageBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('menu-panel-image')),
    );
    final expectedClip = MatrixUtils.transformRect(
      imageBox.getTransformTo(null),
      imageViewport,
    );
    final pureClip = (bounds()['occlusions'] as List).single as Map;
    expect(pureClip['x'], closeTo(expectedClip.left * 1.5, .01));
    expect(pureClip['y'], closeTo(expectedClip.top * 1.5, .01));
    expect(pureClip['width'], closeTo(expectedClip.width * 1.5, .01));
    expect(pureClip['height'], closeTo(expectedClip.height * 1.5, .01));
    work.setPaintBounds(lease, null);
    await flush(tester);
    expectClip();
    work.moveTo(lease, const Offset(80, 170), const Size(1200, 800));
    work.resizeTo(lease, const Size(520, 360), const Size(1200, 800));
    await flush(tester);
    expectClip();
    await tester.tap(find.text('打开弹出菜单'));
    await flush(tester);
    expect(bounds()['visible'], false);
    await tester.tap(find.text('测试菜单'));
    await flush(tester);
    expect(bounds()['visible'], true);
    work.activate('browser');
    await flush(tester);
    expect(bounds()['occlusions'], isEmpty);
    work.setVisible(false);
    await flush(tester);
    expect(bounds()['visible'], false);
    await tester.pumpWidget(const SizedBox());
    work.dispose();
  });
  testWidgets('background browser keeps its uncovered viewport visible', (
    tester,
  ) async {
    final native = BrowserFake(), work = workspace();
    await mount(tester, native, work);
    work.open('image');
    await flush(tester);
    expect(
      native.calls
          .lastWhere((call) => call.$1 == 'browserBounds')
          .$2['visible'],
      isTrue,
    );
    work.togglePanelsVisibility();
    await flush(tester);
    expect(
      native.calls
          .lastWhere((call) => call.$1 == 'browserBounds')
          .$2['visible'],
      false,
    );
    expect(work.visible, true);
    work.togglePanelsVisibility();
    await flush(tester);
    expect(
      native.calls
          .lastWhere((call) => call.$1 == 'browserBounds')
          .$2['visible'],
      true,
    );
    await tester.pumpWidget(const SizedBox());
    work.dispose();
  });
  testWidgets(
    'safe startup forces hidden pause without rewriting saved browser choices',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      const saved = MenuBrowserPreferences(pauseWhenHidden: false);
      await mount(tester, native, work, preferences: saved, safeMode: true);
      expect(native.configured!['pauseWhenHidden'], true);
      expect(saved.pauseWhenHidden, false);
      final count = native.calls
          .where((call) => call.$1 == 'browserConfigure')
          .length;
      await mount(tester, native, work, preferences: saved, safeMode: true);
      expect(
        native.calls.where((call) => call.$1 == 'browserConfigure').length,
        count,
      );
      await mount(tester, native, work, preferences: saved);
      expect(native.configured!['pauseWhenHidden'], false);
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );
  testWidgets('native viewport follows painted interface scale and DPI', (
    tester,
  ) async {
    final native = BrowserFake(), work = workspace();
    for (final scale in [.85, 1.0, 1.25]) {
      await mount(tester, native, work, interfaceScale: scale, pixelRatio: 1.5);
      final box = tester.renderObject<RenderBox>(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.key is GlobalKey,
        ),
      );
      final origin = box.localToGlobal(Offset.zero) * 1.5;
      final end = box.localToGlobal(box.size.bottomRight(Offset.zero)) * 1.5;
      final sent = native.calls
          .lastWhere((entry) => entry.$1 == 'browserBounds')
          .$2;
      expect(sent['x'], closeTo(origin.dx, .001));
      expect(sent['y'], closeTo(origin.dy, .001));
      expect(sent['width'], closeTo(end.dx - origin.dx, .001));
      expect(sent['height'], closeTo(end.dy - origin.dy, .001));
    }
    await tester.pumpWidget(const SizedBox());
    work.dispose();
  });
  testWidgets(
    'blank tab offers input guidance while native blank stays hidden',
    (tester) async {
      final native = BrowserFake(), work = workspace(), boundary = GlobalKey();
      native.tabs[0] = page('t1', title: '', url: 'about:blank');
      await mount(tester, native, work, boundary: boundary);
      await capture(tester, boundary, 'menu-browser-blank');
      expect(find.text('输入网址或搜索词，开始浏览'), findsOneWidget);
      expect(
        native.calls.lastWhere((e) => e.$1 == 'browserBounds').$2['visible'],
        isFalse,
      );
      await tester.tap(find.text('输入网址或搜索词').last);
      await flush(tester);
      final input = find.byKey(const ValueKey('browser-address'));
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      await tester.enterText(input, 'example.test');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await flush(tester);
      expect(find.text('输入网址或搜索词，开始浏览'), findsNothing);
      expect(
        native.calls.lastWhere((e) => e.$1 == 'browserBounds').$2['visible'],
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );
  testWidgets(
    'visible browser sends a nonempty physical viewport below toolbar',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      final bounds = native.calls
          .lastWhere((call) => call.$1 == 'browserBounds')
          .$2;
      expect(bounds['visible'], isTrue);
      expect(bounds['width'] as double, greaterThan(0));
      expect(bounds['height'] as double, greaterThan(0));
      expect(bounds['y'] as double, greaterThan(0));
      expect(
        (bounds['y'] as double) + (bounds['height'] as double),
        closeTo(650, 0.01),
      );
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );
  testWidgets('browser startup failure is not a webpage address failure', (
    tester,
  ) async {
    final native = BrowserFake(), work = workspace();
    native.tabs[0]['failed'] = true;
    native.tabs[0]['unavailable'] = true;
    await mount(tester, native, work);
    expect(find.textContaining('浏览器暂时不可用'), findsOneWidget);
    expect(find.text('网页未能打开，请检查地址或刷新重试。'), findsNothing);
    await tester.tap(find.text('刷新'));
    await flush(tester);
    expect(
      native.calls.any(
        (call) => call.$1 == 'browserReload' && call.$2['tabId'] == 't1',
      ),
      isTrue,
    );
    native.tabs[0]['failed'] = false;
    native.tabs[0]['unavailable'] = false;
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(find.textContaining('浏览器暂时不可用'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    work.dispose();
  });
  setUpAll(() async {
    if (Platform.environment['STARBRIDGE_CAPTURE_SOCIAL'] == '1') {
      await loadFonts();
    }
  });
  test(
    'browser snapshot rejects missing/duplicate IDs and malformed fields',
    () {
      final native = BrowserFake();
      expect(MenuBrowserState.parse(native.snapshot()).active.id, 't1');
      for (final value in [
        {...native.snapshot(), 'activeTabId': 'missing'},
        {
          ...native.snapshot(),
          'tabs': [page('t1'), page('t1')],
        },
        {...native.snapshot(), 'tabLimit': 100},
        {
          ...native.snapshot(),
          'tabs': [
            {...page('t1'), 'back': 'yes'},
          ],
        },
        {
          ...native.snapshot(),
          'tabs': [page('file://private')],
        },
        {...native.snapshot(), 'tabs': []},
      ]) {
        expect(() => MenuBrowserState.parse(value), throwsFormatException);
      }
    },
  );

  testWidgets(
    'switch/new/close use native IDs and keep per-tab address drafts',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      final input = find.byKey(const ValueKey('browser-address'));
      await tester.enterText(input, 'an unfinished search');
      await tester.tap(find.byKey(const ValueKey('browser-tab-t2')));
      await flush(tester);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'https://example.test/t2',
      );
      await tester.tap(find.byKey(const ValueKey('browser-tab-t1')));
      await flush(tester);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'an unfinished search',
      );
      await tester.tap(find.byKey(const ValueKey('browser-new-tab')));
      await flush(tester);
      expect(find.byKey(const ValueKey('browser-tab-t3')), findsOneWidget);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'https://www.bing.com/',
      );
      await tester.tap(find.byKey(const ValueKey('browser-close-t2')));
      await flush(tester);
      expect(native.active, 't3');
      expect(find.byKey(const ValueKey('browser-tab-t2')), findsNothing);
      expect(native.calls.where((e) => e.$1 == 'browserCloseTab').single.$2, {
        'tabId': 't2',
        'url': 'https://www.bing.com/',
      });
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );

  testWidgets(
    'a poll started before tab selection cannot restore the old tab',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      final late = native.pendingState = Completer<Object?>();
      final old = native.snapshot();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('browser-tab-t2')));
      await flush(tester);
      late.complete(old);
      await flush(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('browser-address')))
            .controller!
            .text,
        'https://example.test/t2',
      );
      await tester.tap(find.text('刷新'));
      await flush(tester);
      expect(native.calls.lastWhere((e) => e.$1 == 'browserReload').$2, {
        'tabId': 't2',
      });
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );

  testWidgets(
    'background state updates do not overwrite typed URL and hide stops polling',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      final input = find.byKey(const ValueKey('browser-address'));
      await tester.enterText(input, 'example.test/new');
      native.tabs[0]['url'] = 'https://example.test/redirect';
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'example.test/new',
      );
      work.open('image');
      await flush(tester);
      final backgroundCount = native.calls
          .where((e) => e.$1 == 'browserState')
          .length;
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(
        native.calls.where((e) => e.$1 == 'browserState').length,
        greaterThan(backgroundCount),
      );
      work.setVisible(false);
      await flush(tester);
      final count = native.calls.where((e) => e.$1 == 'browserState').length;
      await tester.pump(const Duration(seconds: 5));
      await flush(tester);
      expect(native.calls.where((e) => e.$1 == 'browserState').length, count);
      expect(
        native.calls.lastWhere((e) => e.$1 == 'browserBounds').$2['visible'],
        false,
      );
      work.activate('browser');
      work.setVisible(true);
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(
        native.calls.where((e) => e.$1 == 'browserState').length,
        greaterThan(count),
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        'example.test/new',
      );
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );

  testWidgets(
    'navigation is explicit, scoped, rejects protocols and recovers failed pages',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      final input = find.byKey(const ValueKey('browser-address'));
      await tester.enterText(input, 'file:///C:/private');
      await tester.tap(find.text('访问'));
      await flush(tester);
      expect(native.calls.where((e) => e.$1 == 'browserNavigate'), isEmpty);
      await tester.enterText(input, 'example.test/path');
      await tester.tap(find.text('访问'));
      await flush(tester);
      expect(native.calls.lastWhere((e) => e.$1 == 'browserNavigate').$2, {
        'tabId': 't1',
        'url': 'https://example.test/path',
      });
      native.tabs[0]['failed'] = true;
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(find.text('网页未能打开，请检查地址或刷新重试。'), findsOneWidget);
      native.tabs[0]['failed'] = false;
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(find.text('网页未能打开，请检查地址或刷新重试。'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );

  testWidgets(
    'new tabs stop at native limit and pending action cannot duplicate',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      native.pendingAction = Completer<Object?>();
      await tester.tap(find.byKey(const ValueKey('browser-new-tab')));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('browser-new-tab')));
      await flush(tester);
      expect(native.calls.where((e) => e.$1 == 'browserNewTab').length, 1);
      native.tabs.addAll([for (var i = 3; i <= 8; i++) page('t$i')]);
      native.pendingAction!.complete();
      await flush(tester);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('browser-new-tab')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );

  testWidgets(
    'late replies after disposal do not rebuild or show native view',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      final late = native.pendingState = Completer<Object?>();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      late.complete(native.snapshot());
      await flush(tester);
      expect(tester.takeException(), isNull);
      expect(native.calls.lastWhere((e) => e.$1 == 'browserBounds').$2, {
        'visible': false,
      });
      work.dispose();
    },
  );

  testWidgets(
    'stale native tab error is actionable and never retries navigation automatically',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      native.failure = PlatformException(code: 'menu.browser_tab_stale');
      await tester.tap(find.text('刷新'));
      await flush(tester);
      expect(find.text('标签页已变化，请在当前页面重新操作。'), findsOneWidget);
      expect(native.calls.where((e) => e.$1 == 'browserReload').length, 1);
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );

  for (final width in [1280.0, 700.0, 320.0]) {
    testWidgets('tab toolbar fits $width with long titles', (tester) async {
      final native = BrowserFake(), work = workspace(), boundary = GlobalKey();
      native.tabs[0]['title'] = '很长的网页标题，需要截断而不是撑破整个浏览器窗口';
      await mount(
        tester,
        native,
        work,
        width: width,
        height: width == 320 ? 200 : 900,
        scale: width == 320 ? 2 : 1,
        boundary: boundary,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'menu-browser-tabs-${width.toInt()}');
      if (width == 320) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('browser-address')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('browser-address')),
          'example.test',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await flush(tester);
        expect(
          native.calls.lastWhere((e) => e.$1 == 'browserNavigate').$2['tabId'],
          't1',
        );
        await capture(tester, boundary, 'menu-browser-tabs-320-address');
      }
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    });
  }
}
