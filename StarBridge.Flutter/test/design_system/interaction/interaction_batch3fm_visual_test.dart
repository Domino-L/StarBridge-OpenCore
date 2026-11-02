import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_loading.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_directory.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_navigation.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_sidebar.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/communities/community_ship_banner.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../app/menu_overlay/menu_organizations_test.dart' show fixture;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3fl_menu_test.dart'
    show directoryData, MenuProbe, menuFocus;
import 'interaction_batch3i_test.dart' show scopedApp;

final _directory = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fm_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
Finder _key(String key) => find.byKey(Key(key));

/// Displays original menu snapshots only. This is not a session/transport
/// owner and never fabricates a service acknowledgement or account identity.
class _Probe {
  _Probe(this.suite, this.light, this.locale)
    : skeleton = MenuProbe(suite, 'sidebar');
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final MenuProbe skeleton;
  final frame = GlobalKey();
  final commands = <(String, String, InteractionSource)>[];
  String kind = 'directory', phase = 'ready';
  InteractionSource? readSource;
  bool reduce = false, pendingOnRefresh = false;
  int request = 0;
  late StateSetter update;

  Map<String, Object?> _snapshot() {
    final data = kind == 'directory'
        ? directoryData()
        : fixture(tab: kind == 'ships' ? 'ships' : 'members');
    final org = data['organization']! as Map<String, Object?>;
    if (phase == 'loading' || phase == 'empty-error') {
      data['rows'] = <Object?>[];
      org['rows'] = <Object?>[];
    }
    if (phase == 'loading') {
      org['bodyLoading'] = true;
    }
    if (phase == 'refreshing') {
      data['refreshing'] = true;
    }
    if (phase == 'processing') {
      data['busy'] = true;
    }
    if (phase == 'empty-error' || phase == 'retained-error') {
      org['bodyError'] = true;
      data['notice'] = '暂时无法读取；已有内容仍保留，请重试。';
    }
    if (kind == 'directory' && phase == 'refreshing') {
      data['busy'] = true;
    }
    if (kind == 'directory' && phase == 'retained-error') {
      data['notice'] = '刷新失败，仍显示上次读取的组织。';
    }
    if (phase == 'loading' || phase == 'refreshing' || phase == 'processing') {
      data['readFeedback'] = readSource == null
          ? {'request': request + 1, 'source': 'unknown'}
          : {
              'request': request + 1,
              'source': readSource == InteractionSource.pointer
                  ? 'pointer'
                  : 'keyboard',
            };
    }
    return data;
  }

  void action(String key, String value) {
    final source = currentStarBridgeActivationSource;
    commands.add((key, value, source));
    if (pendingOnRefresh && key == 'refresh') {
      update(() {
        request++;
        readSource = source;
        phase = phase == 'empty-error' ? 'loading' : 'refreshing';
      });
    }
  }

  Widget _component() {
    final view = MenuFeatureView.parse(_snapshot());
    assert(view.organization != null);
    return switch (kind) {
      'directory' => MenuOrganizationDirectory(view: view, onAction: action),
      'sidebar' => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280,
          child: MenuOrganizationSidebar(
            items: skeleton.items,
            busy: phase == 'refreshing',
            onSelect: (key) => action(key, ''),
          ),
        ),
      ),
      'navigation' => Align(
        alignment: Alignment.topLeft,
        child: MenuOrganizationNavigation(view: view, onAction: action),
      ),
      _ => MenuOrganizationsPanel(view: view, onAction: action),
    };
  }

  Widget app() => StatefulBuilder(
    builder: (_, setter) {
      update = setter;
      final base = scopedApp(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Menu component gallery · $kind · $phase'),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox.expand(
                  key: const Key('3fm-component-bounds'),
                  child: KeyedSubtree(key: ValueKey(kind), child: _component()),
                ),
              ),
            ),
          ],
        ),
        suite,
        light: light,
        reduce: reduce,
      ) as MaterialApp;
      return RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        ),
      );
    },
  );
}

Future<void> _frames(WidgetTester t, [int count = 4]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _show(
  WidgetTester t,
  _Probe p,
  String kind, [
  String phase = 'ready',
]) async {
  p.update(() {
    p.kind = kind;
    p.phase = phase;
    // Only an actual admitted callback supplies an active read origin.
    p.readSource = null;
  });
  await _frames(t);
}

Future<void> _mount(WidgetTester t, _Probe p, double width) async {
  size(t, Size(width, 1200));
  await t.pumpWidget(p.app());
  await _frames(t);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await _frames(t, 2);
  expect(t.takeException(), isNull);
}

void _layout(WidgetTester t, double width) {
  expect(t.takeException(), isNull);
  final rect = t.getRect(_key('3fm-component-bounds'));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(1200));
}

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height];

Future<List<int>> _pixels(WidgetTester t, _Probe p, Rect globalRect) async {
  final boundary =
      p.frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = globalRect.shift(-boundary.localToGlobal(Offset.zero));
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final left = rect.left.floor().clamp(0, image.width).toInt();
      final right = rect.right.ceil().clamp(0, image.width).toInt();
      final top = rect.top.floor().clamp(0, image.height).toInt();
      final bottom = rect.bottom.ceil().clamp(0, image.height).toInt();
      return <int>[
        for (var y = top; y < bottom; y++)
          ...bytes.sublist(
            (y * image.width + left) * 4,
            (y * image.width + right) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

int _diff(List<int> a, List<int> b) {
  expect(b.length, a.length);
  var changed = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      changed++;
    }
  }
  return changed;
}

Future<void> _capture(WidgetTester t, _Probe p, String name) async {
  final boundary =
      p.frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_directory).create(recursive: true);
      await File('$_directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Finder _target(WidgetTester t, Finder owner) =>
    t.widget(owner) is SuitePressable
    ? owner
    : find.descendant(of: owner, matching: find.byType(SuitePressable)).first;

Future<Map<String, Object?>> _touchCancel(
  WidgetTester t,
  _Probe p,
  Finder owner,
) async {
  final target = _target(t, owner);
  await t.ensureVisible(target);
  await _frames(t);
  final rect = t.getRect(target);
  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 180));
  expect(
    _diff(before, await _pixels(t, p, rect)),
    0,
    reason:
        'Idle pixels, not a running indicator, provide the control baseline',
  );
  final commands = p.commands.length;
  final gesture = await t.startGesture(
    rect.center,
    kind: ui.PointerDeviceKind.touch,
  );
  var changed = 0;
  try {
    await t.pump(const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 30));
    expect(t.getRect(target), rect);
    changed = _diff(before, await _pixels(t, p, rect));
    expect(
      changed,
      greaterThan(0),
      reason: 'The actual button/row press changes local pixels',
    );
    expect(p.commands.length, commands);
  } finally {
    await gesture.cancel();
    await _frames(t);
  }
  expect(
    p.commands.length,
    commands,
    reason: 'Cancellation issues no menu/session command',
  );
  return {
    'rect': _rect(rect),
    'idlePixels': 0,
    'pressPixels': changed,
    'cancelCommands': 0,
  };
}

Future<void> _keyboard(WidgetTester t, Finder owner) async {
  final target = _target(t, owner);
  await t.ensureVisible(target);
  final node = menuFocus(t, target);
  for (var i = 0; i < 100 && !node.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(node.hasPrimaryFocus, isTrue);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

Finder _shipRetry(Locale locale) => find.widgetWithText(
  StarBridgeActionButton,
  AppStrings.resolve(locale).text('menu.overlay.organizations.retryRead'),
);

Future<Map<String, Object?>> _waiting(
  WidgetTester t,
  _Probe p,
  String kind, {
  required bool animated,
}) async {
  final marker = find.byType(MenuLoading);
  expect(marker, findsOneWidget);
  await t.ensureVisible(marker);
  await t.pump();
  final rect = t.getRect(marker);
  await t.pump(const Duration(milliseconds: 80));
  final before = await _pixels(t, p, rect);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(t.getRect(marker), rect);
  final changed = _diff(before, await _pixels(t, p, rect));
  expect(changed, animated ? greaterThan(0) : equals(0));
  return {
    'kind': kind,
    'rect': _rect(rect),
    'elapsedMs': 600,
    'animated': animated,
    'changedPixels': changed,
  };
}

void _retainedMembers() {
  expect(
    find.byType(OrganizationMemberRow),
    findsNWidgets(4),
    reason: 'Refresh/failed projections retain the actual four member rows',
  );
}

void main() {
  setUpAll(loadFonts);
  final evidence = <Map<String, Object?>>[];
  tearDownAll(() async {
    await Directory(_directory).create(recursive: true);
    await File('$_directory/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Separate actual Directory, Sidebar, Navigation, Ships Panel and Members Panel. Original display snapshots only; callback spy does not implement session authority, persistence, transport or a full shell. Owned menu copy follows the locale under test; fixture content stays as given.',
        'checks': evidence,
      }),
    );
  });
  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [540.0, 1100.0]) {
          testWidgets(
            '3fm menu component states $suite $palette $locale $width 1.5x',
            (t) async {
              final p = _Probe(suite, light, locale);
              await _mount(t, p, width);
              _layout(t, width);
              expect(find.text('远航者组织'), findsOneWidget);
              if (locale.countryCode == 'CN' && width == 540) {
                await _capture(t, p, '${suite.name}-$palette-directory');
              }
              await _show(t, p, 'directory', 'refreshing');
              _layout(t, width);
              expect(find.text('远航者组织'), findsOneWidget);
              await _show(t, p, 'directory', 'retained-error');
              _layout(t, width);
              expect(find.text('刷新失败，仍显示上次读取的组织。'), findsOneWidget);
              await _show(t, p, 'sidebar');
              _layout(t, width);
              expect(_key('menu-organization-sidebar-a20'), findsOneWidget);
              await _show(t, p, 'navigation');
              _layout(t, width);
              expect(_key('menu-organization-tab-refresh'), findsOneWidget);

              await _show(t, p, 'ships', 'loading');
              _layout(t, width);
              expect(find.byType(MenuLoading), findsOneWidget);
              await _show(t, p, 'ships', 'empty-error');
              _layout(t, width);
              expect(_shipRetry(locale), findsOneWidget);
              if (locale.countryCode == 'CN' && width == 540) {
                await _capture(t, p, '${suite.name}-$palette-ships-failed');
              }
              p.pendingOnRefresh = true;
              final count = p.commands.length;
              await t.tap(_shipRetry(locale));
              await _frames(t, 2);
              expect(p.commands.length, count + 1);
              expect(p.commands.last.$1, 'refresh');
              expect(find.byType(MenuLoading), findsOneWidget);
              await _show(t, p, 'ships');
              _layout(t, width);
              expect(find.byType(CommunityShipBanner), findsNWidgets(4));
              final shipScroll = _key('menu-org-body-ships');
              await t.drag(shipScroll, const Offset(0, -320));
              await _frames(t, 2);
              _layout(t, width);
              await _show(t, p, 'ships', 'refreshing');
              _layout(t, width);
              expect(find.byType(CommunityShipBanner), findsNWidgets(4));
              expect(find.byType(MenuLoading), findsOneWidget);

              await _show(t, p, 'members');
              _retainedMembers();
              await _show(t, p, 'members', 'refreshing');
              _layout(t, width);
              _retainedMembers();
              expect(find.byType(MenuLoading), findsOneWidget);
              if (locale.countryCode == 'CN' && width == 1100) {
                await _capture(t, p, '${suite.name}-$palette-members-retained');
              }
              await _show(t, p, 'members', 'retained-error');
              _layout(t, width);
              _retainedMembers();
              expect(_key('menu-org-retry'), findsOneWidget);
              final beforeRetry = p.commands.length;
              await t.ensureVisible(_key('menu-org-retry'));
              await t.tap(_key('menu-org-retry'));
              await _frames(t, 2);
              expect(p.commands.length, beforeRetry + 1);
              _retainedMembers();
              _layout(t, width);
              evidence.add({
                'kind': 'layout',
                'suite': suite.name,
                'palette': palette,
                'locale': locale.toLanguageTag(),
                'width': width,
                'components': [
                  'directory',
                  'sidebar',
                  'navigation',
                  'ships',
                  'members',
                ],
                'states': ['ready', 'pending', 'failed', 'retry', 'retained'],
              });
              await _unmount(t);
            },
          );
        }
      }
      testWidgets('3fm menu real inputs pixels $suite $palette', (t) async {
        final p = _Probe(suite, light, const Locale('zh', 'CN'));
        await _mount(t, p, 1100);
        final checks = <Map<String, Object?>>[];
        checks.add({
          'control': 'directory-refresh',
          ...await _touchCancel(t, p, _key('menu-organization-refresh')),
        });
        await _show(t, p, 'sidebar');
        checks.add({
          'control': 'sidebar-row',
          ...await _touchCancel(t, p, _key('menu-organization-sidebar-a20')),
        });
        await _show(t, p, 'members');
        checks.add({
          'control': 'panel-refresh',
          ...await _touchCancel(t, p, _key('menu-organization-tab-refresh')),
        });
        expect(p.commands, isEmpty);
        p.pendingOnRefresh = true;
        await t.tap(_key('menu-organization-tab-refresh'));
        await t.pump();
        await t.pump();
        expect(p.commands, [('refresh', '', InteractionSource.pointer)]);
        _retainedMembers();
        checks.add(await _waiting(t, p, 'pointer-refresh', animated: true));
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        checks.add(await _waiting(t, p, 'live-reduced', animated: false));
        _retainedMembers();
        p.update(() {
          p.reduce = false;
          p.phase = 'ready';
        });
        await _frames(t);
        await _keyboard(t, _key('menu-organization-tab-refresh'));
        expect(p.commands.last, ('refresh', '', InteractionSource.keyboard));
        _retainedMembers();
        checks.add(await _waiting(t, p, 'keyboard-refresh', animated: false));
        p.update(() {
          p.readSource = null;
          p.request++;
        });
        await t.pump();
        await t.pump();
        checks.add(await _waiting(t, p, 'unknown-origin', animated: false));
        _retainedMembers();
        p.update(() {
          p.phase = 'processing';
          p.readSource = InteractionSource.pointer;
        });
        await t.pump();
        await t.pump();
        expect(t.widget<MenuLoading>(find.byType(MenuLoading)).label, '正在处理');
        checks.add(
          await _waiting(
            t,
            p,
            'busy-only-does-not-borrow-old-pointer',
            animated: false,
          ),
        );
        _retainedMembers();
        _layout(t, 1100);
        expect(
          p.commands.length,
          2,
          reason: 'Waiting/visual frames never duplicate a command',
        );
        evidence.add({
          'kind': 'input',
          'suite': suite.name,
          'palette': palette,
          'checks': checks,
        });
        await _unmount(t);
      });
    }
  }
}
