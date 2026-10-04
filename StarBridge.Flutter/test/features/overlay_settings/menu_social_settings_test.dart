import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_social_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_social_settings_card.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Store implements MenuWindowPreferencesPort {
  MenuWindowPreferences value = MenuWindowPreferences.defaults;
  bool fail = false;
  @override
  Future<MenuWindowPreferences> read() async => value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    if (fail) throw StateError('fixture');
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
  test('legacy defaults remain read only and social fields are exact', () {
    final legacy = MenuWindowPreferences.defaults;
    expect(
      MenuSocialPreferences.fromSettings(legacy.settings)!.friendSort,
      'onlineFirst',
    );
    expect(legacy.settings.containsKey('social'), false);
    for (final bad in [
      null,
      {},
      {'friendSort': null},
      {'friendSort': true},
      {'friendSort': 'invalid'},
      {'friendSort': 'alphabetical', 'extra': true},
      {'friendSort': 'alphabetical', 'notifications': 1},
      {'friendSort': 'alphabetical', 'sound': 'true'},
      {'friendSort': 'alphabetical', 'showAvatars': 1},
      {'friendSort': 'alphabetical', 'preview': 'invalid'},
    ]) {
      expect(
        MenuWindowPreferences.parse({
          ...legacy.toMap(),
          'settings': {...legacy.settings, 'social': bad},
        }),
        isNull,
      );
    }
  });
  testWidgets('menu sorting updates immediately without mutating projection', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final tools = MenuLocalToolsController((_, _) async => null);
    addTearDown(tools.dispose);
    const friends = MenuFriendsView(
      'ready',
      rows: [
        (name: 'Alpha', presence: 'online', key: 'a', avatar: null),
        (name: 'Zulu', presence: 'inGame', key: 'z', avatar: null),
        (name: 'Beta', presence: 'offline', key: 'b', avatar: null),
      ],
    );
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      app(
        MenuBridgePreview(
          visible: true,
          onDismiss: () {},
          friends: friends,
          localToolsController: tools,
          onSettingsChanged: (v) => saved = v,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<MenuOverlayWorkspace>(find.byType(MenuOverlayWorkspace))
        .controller
        .open('friends');
    await tester.pumpAndSettle();
    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('Zulu'), lessThan(y('Alpha')));
    tools.settings(
      social: const MenuSocialPreferences(friendSort: 'alphabetical'),
    );
    await tester.pumpAndSettle();
    expect(y('Alpha'), lessThan(y('Zulu')));
    expect(y('Zulu'), lessThan(y('Beta')));
    expect((saved!['social'] as Map)['friendSort'], 'alphabetical');
    expect(friends.rows.first.name, 'Alpha');
    await tester.pumpWidget(const SizedBox());
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'localized social editor saves and preserves failed draft $locale',
      (tester) async {
        size(tester, const Size(320, 900));
        final store = _Store()..fail = true;
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
                    child: SingleChildScrollView(
                      child: MenuSocialSettingsCard(port: store),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final avatars = find.byKey(const ValueKey('menu-social-avatars'));
        await tester.ensureVisible(avatars);
        await tester.tap(avatars);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MenuSocialEditor>(find.byType(MenuSocialEditor))
              .value
              .showAvatars,
          false,
        );
        tester
            .widget<MenuSocialEditor>(find.byType(MenuSocialEditor))
            .onChanged(
              const MenuSocialPreferences(
                friendSort: 'alphabetical',
                notifications: false,
                showAvatars: false,
                preview: 'hiddenDetails',
              ),
            );
        await tester.pumpAndSettle();
        final save = find.byKey(const Key('menu-social-save'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('menu-social-error')), findsOneWidget);
        expect(
          tester
              .widget<MenuSocialEditor>(find.byType(MenuSocialEditor))
              .value
              .friendSort,
          'alphabetical',
        );
        store.fail = false;
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          (store.value.settings['social'] as Map)['friendSort'],
          'alphabetical',
        );
        expect(store.value.layout, MenuWindowPreferences.defaults.layout);
        final prefs = MenuSocialPreferences.fromSettings(store.value.settings)!;
        expect(prefs.notifications, false);
        expect(prefs.showAvatars, false);
        expect(prefs.preview, 'hiddenDetails');
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'menu-social-$locale');
      },
    );
  }
}
