import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_toolbar_settings_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_toolbar_editor.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_toolbar_preferences.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/platform/window/menu_attention.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Store implements MenuWindowPreferencesPort {
  MenuWindowPreferences value = const MenuWindowPreferences(
    3,
    {'version': 1, 'panels': [], 'open': []},
    {'showClock': true, 'showContext': true, 'dimming': .5},
  );
  bool fail = false;
  int writes = 0;
  @override
  Future<MenuWindowPreferences> read() async => value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    writes++;
    if (fail) throw StateError('fixture write failed');
    expect(next.revision, value.revision);
    return value = MenuWindowPreferences(
      next.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'shared toolbar badge switch changes presentation without clearing unread',
    (tester) async {
      size(tester, const Size(1040, 900));
      var preferences = const MenuToolbarPreferences(
        labels: 'iconsOnly',
        density: 'compact',
      );
      final counters = const MenuAttention(
        friends: 2,
        comms: 123,
        rooms: 1,
        organizations: 9,
      );
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: Column(
                children: [
                  BridgePreviewDock(
                    selected: null,
                    onToggle: (_) {},
                    featuresEnabled: true,
                    attention: counters,
                    preferences: preferences,
                  ),
                  MenuToolbarEditor(
                    value: preferences,
                    onChanged: (value) => setState(() => preferences = value),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('通讯 · 123 项未读或待处理'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-toolbar-unread')));
      await tester.pump();
      expect(find.text('99+'), findsNothing);
      expect(
        tester
            .widget<AttentionIconBadge>(
              find.byKey(const ValueKey('menu-attention-comms')),
            )
            .count,
        0,
      );
      expect(counters.comms, 123);
      await tester.tap(find.byKey(const ValueKey('menu-toolbar-unread')));
      await tester.pump();
      expect(find.text('99+'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  test(
    'toolbar document rejects unknown, duplicates and hidden mandatory tool',
    () {
      final base = const MenuToolbarPreferences().toMap();
      for (final value in [
        {
          ...base,
          'hidden': ['hud'],
        },
        {
          ...base,
          'hidden': ['browser', 'browser'],
        },
        {
          ...base,
          'order': ['browser'],
        },
        {...base, 'density': 'unknown'},
        {...base, 'labels': 'unknown'},
        {...base, 'account': 'forbidden'},
      ]) {
        expect(MenuToolbarPreferences.parse(value), isNull);
      }
      expect(
        MenuToolbarPreferences.parse(null)!.order,
        MenuToolbarPreferences.ids,
      );
      expect(
        MenuWindowPreferences.parse({
          ...MenuWindowPreferences.defaults.toMap(),
          'settings': {
            ...MenuWindowPreferences.defaults.settings,
            'toolbar': null,
          },
        }),
        isNull,
      );
    },
  );
  for (final width in [320.0, 760.0, 1040.0]) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ]) {
      testWidgets('badge dock fits enlarged text width=$width locale=$locale', (
        tester,
      ) async {
        size(tester, Size(width, 400));
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: locale,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.8)),
                  child: RepaintBoundary(
                    key: key,
                    child: BridgePreviewDock(
                      selected: null,
                      onToggle: (_) {},
                      featuresEnabled: true,
                      preferences: const MenuToolbarPreferences(
                        density: 'compact',
                      ),
                      attention: const MenuAttention(
                        friends: 1,
                        comms: 100,
                        rooms: 3,
                        organizations: 88,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'menu-badges-${width.toInt()}-${locale.languageCode}-${locale.countryCode ?? "default"}',
        );
      });
    }
  }
  testWidgets(
    'toolbar edits save explicitly, failed save keeps draft, reload preserves geometry',
    (tester) async {
      final store = _Store()..fail = true;
      await tester.pumpWidget(
        app(SingleChildScrollView(child: MenuToolbarSettingsCard(port: store))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('menu-toolbar-visible-friends')),
      );
      await tester.pump();
      expect(store.writes, 0);
      expect(
        find.byKey(const ValueKey('menu-toolbar-visible-hud')),
        findsNothing,
      );
      expect(find.text('始终显示'), findsOneWidget);
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderItem!(7, 0);
      await tester.pump();
      final save = find.byKey(const Key('menu-toolbar-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-toolbar-error')), findsOneWidget);
      expect(
        tester
            .widget<MenuToolbarEditor>(find.byType(MenuToolbarEditor))
            .value
            .order
            .first,
        'browser',
      );
      store.value = MenuWindowPreferences(9, const {
        'version': 1,
        'panels': [
          {
            'id': 'browser',
            'bounds': [1, 2, 500, 400],
          },
        ],
        'open': [],
      }, store.value.settings);
      await tester.tap(find.byKey(const Key('menu-toolbar-reload')));
      await tester.pumpAndSettle();
      store.fail = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        MenuToolbarPreferences.parse(store.value.settings['toolbar'])!.hidden,
        ['friends'],
      );
      expect(store.value.layout['panels'], isNotEmpty);
    },
  );
  testWidgets(
    'dock renders persisted order, hiding and icons without disabling open windows',
    (tester) async {
      const preferences = MenuToolbarPreferences(
        order: [
          'browser',
          'hud',
          'organizations',
          'friends',
          'comms',
          'rooms',
          'screenshot',
          'image',
        ],
        hidden: ['friends'],
        density: 'compact',
        labels: 'iconsOnly',
      );
      await tester.pumpWidget(
        app(
          BridgePreviewDock(
            selected: BridgePreviewPanel.browser,
            onToggle: (_) {},
            featuresEnabled: true,
            localToolsEnabled: true,
            preferences: preferences,
            openPanels: const {
              BridgePreviewPanel.browser,
              BridgePreviewPanel.friends,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-tool-friends')), findsNothing);
      expect(find.text('浏览器'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('menu-tool-browser'))).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('menu-tool-overlay'))).dx,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('menu-tool-browser'))).width,
        66,
      );
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('menu-open-browser')))
            .color,
        BridgeInk.blue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 760.0, 1040.0]) {
    testWidgets('toolbar editor fits width $width', (tester) async {
      size(tester, Size(width, 900));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: SingleChildScrollView(
              child: MenuToolbarSettingsCard(port: _Store()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'menu-toolbar-${width.toInt()}');
    });
  }
  testWidgets('restored hidden tool window remains available on the desktop', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    await tester.pumpWidget(
      app(
        MenuBridgePreview(
          visible: true,
          onDismiss: () {},
          localCall: (_, _) async => null,
          initialSettings: {
            ...MenuWindowPreferences.defaults.settings,
            'restoreDesktop': true,
            'toolbar': const MenuToolbarPreferences(hidden: ['friends'])
                .toMap(),
          },
          initialLayout: const {
            'version': 1,
            'panels': [],
            'open': ['friends'],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-tool-friends')), findsNothing);
    expect(find.byKey(const ValueKey('menu-panel-friends')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
