import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/standard_interaction.dart';

import 'package:starbridge_flutter/shared/ships/ship_art_ratio.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/legal/cig_fankit_notice.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_avatar.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_wallpaper_catalog.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final requiresReload in [true, false]) {
    testWidgets('failed editor preserves draft; reload gate: $requiresReload', (
      tester,
    ) async {
      final port = _FailedEditPort(requiresReload);
      await _pumpSignedInShell(tester, personalProfilePort: port);
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-edit')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('profile-call-sign-field'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Retained draft');
      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Retained draft'), findsOneWidget);
      expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(save).onPressed == null,
        requiresReload,
      );
      await Scrollable.ensureVisible(tester.element(save), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(port.saves, requiresReload ? 1 : 2);
      if (requiresReload) {
        await tester.tap(find.byKey(const Key('profile-edit-cancel')));
        await tester.pumpAndSettle();
        final refresh = find.byKey(const Key('profile-refresh'));
        await Scrollable.ensureVisible(tester.element(refresh), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(port.reads, 2);
        await tester.tap(find.byKey(const Key('profile-edit')));
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        expect(find.text('Retained draft'), findsNothing);
        expect(port.saves, 1); // A fresh read is not an automatic replay.
      }
      expect(tester.takeException(), isNull);
    });
  }
  test('background image labels are numeric while saved IDs stay stable', () {
    final images = PersonalProfileWallpaperCatalog.presets
        .where((preset) => preset.hasImage)
        .toList();
    expect(
      images.map((preset) => preset.displayNumber).toSet().length,
      images.length,
    );
    expect(
      images.every((preset) => RegExp(r'^\d+$').hasMatch(preset.displayNumber)),
      isTrue,
    );
    expect(
      PersonalProfileWallpaperCatalog.resolve('formation-flight').displayNumber,
      '01',
    );
    expect(
      PersonalProfileWallpaperCatalog.resolve('formation-flight').assetPath,
      'assets/profile-wallpapers/formation-flight.jpg',
    );
  });
  testWidgets('personal avatar has no added background, gradient or frame', (
    tester,
  ) async {
    await _pumpSignedInShell(tester);
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    final avatar = find.byType(PersonalProfileAvatar).first;
    final container = tester.widget<Container>(
      find.descendant(of: avatar, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
    expect(decoration.color, isNull);
    expect(decoration.gradient, isNull);
  });

  testWidgets('profile and account menu share separate app and game states', (
    tester,
  ) async {
    final source = InMemoryShellChrome(
      initial: InMemoryShellChrome.connectedProjection,
    );
    await _pumpSignedInShell(tester, shellChrome: source);
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-game-presence')), findsOneWidget);
    expect(find.text('游戏状态未知'), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    final header = find.byKey(const Key('profile-identity-header'));
    final colors = tester.element(header).tokens.colors;
    Color? headerColor(String label) => tester
        .widget<Text>(find.descendant(of: header, matching: find.text(label)))
        .style
        ?.color;
    expect(headerColor('应用在线'), colors.info);
    expect(headerColor('游戏状态未知'), colors.warning);
    expect(
      find.descendant(of: header, matching: find.text('应用在线')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.text('游戏状态未知')),
      findsOneWidget,
    );
    final activity = tester
        .widget<StarBridgeApp>(find.byType(StarBridgeApp))
        .composition
        .appActivity;
    activity.value = true;
    await tester.pumpAndSettle();
    expect(headerColor('暂离'), colors.warning);
    expect(
      tester.widget<Text>(find.byKey(const Key('account-presence'))).data,
      '暂离',
    );
    source.replace(
      InMemoryShellChrome.connectedProjection.copyWith(
        gamePresence: GamePresenceState.running,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: header, matching: find.text('应用在线')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.text('游戏中')),
      findsOneWidget,
    );
    expect(headerColor('游戏中'), colors.success);
    expect(headerColor('应用在线'), colors.info);
    source.replace(
      InMemoryShellChrome.connectedProjection.copyWith(
        gamePresence: GamePresenceState.notRunning,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: header, matching: find.text('未运行游戏')),
      findsOneWidget,
    );
    expect(headerColor('未运行游戏'), colors.offline);
    expect(headerColor('暂离'), colors.warning);
    activity.recordInteraction();
    await tester.pumpAndSettle();
    expect(headerColor('应用在线'), colors.info);
    expect(tester.takeException(), isNull);
  });

  test('curated profile wallpaper catalog excludes retired ids', () async {
    expect(
      PersonalProfileWallpaperCatalog.presets.where(
        (preset) => preset.hasImage,
      ),
      hasLength(43),
    );
    for (final retiredId in const [
      'levski-yard',
      'asteroid-belt',
      'lorville-corridor',
    ]) {
      expect(PersonalProfileWallpaperCatalog.contains(retiredId), isFalse);
      expect(
        PersonalProfileWallpaperCatalog.resolve(retiredId).id,
        PersonalProfileWallpaperCatalog.noneId,
      );
    }
  });

  test(
    'optional wallpaper delivery contains every catalog image',
    () async {
      for (final preset in PersonalProfileWallpaperCatalog.presets.where(
        (preset) => preset.hasImage,
      )) {
        expect(await rootBundle.load(preset.assetPath!), isNotNull);
      }
    },
    skip:
        !PersonalProfileWallpaperCatalog.presets.any(
          (preset) => preset.hasImage && File(preset.assetPath!).existsSync(),
        )
        ? 'Optional wallpaper media is not included in source builds.'
        : false,
  );

  testWidgets('avatar opens the personal menu without duplicating hangar', (
    tester,
  ) async {
    await _pumpSignedInShell(tester);

    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('account-menu-personal-profile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('account-menu-account-and-identity')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('account-menu-hangar')), findsNothing);
  });

  testWidgets('profile visibility offers all approved audience scopes', (
    tester,
  ) async {
    await _pumpSignedInShell(tester, size: const Size(1280, 1000));
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-edit')));
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-visibility-selector')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-visibility-public')), findsWidgets);
    expect(
      find.byKey(const Key('profile-visibility-friends-and-main-fleet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-visibility-friends-only')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-visibility-private')), findsOneWidget);

    await tester.tap(find.text('好友与主舰队成员可见').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(find.text('好友与主舰队成员可见'), findsOneWidget);
  });

  testWidgets('background picker previews and saves a curated background', (
    tester,
  ) async {
    await _pumpSignedInShell(tester, size: const Size(1280, 1000));
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-edit')));
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('profile-background-picker-grid')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('profile-background-picker-open')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('profile-wallpaper-choice-formation-flight')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('profile-wallpaper-formation-flight')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-wallpaper-image')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('profile-wallpaper-formation-flight')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-cig-fankit-notice')), findsOneWidget);
  });

  testWidgets('personal profile edits only public presentation fields', (
    tester,
  ) async {
    await _pumpSignedInShell(tester);
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Aster Lin'), findsWidgets);
    expect(find.text('@Aster-Lin'), findsOneWidget);
    // Steam-style page (2026-11-02): one column, a side rail, flat bands.
    expect(find.byKey(const Key('profile-steam-column')), findsOneWidget);
    expect(find.byKey(const Key('profile-side-rail')), findsOneWidget);
    expect(find.byKey(const Key('profile-showcase-week-bars')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-showcase-hours'))).data,
      '559',
    );
    expect(find.text('最爱舰船'), findsOneWidget);
    expect(find.text('舰船概览'), findsOneWidget);
    expect(find.text(r'$3,175'), findsOneWidget);
    expect(find.text('舰种构成'), findsOneWidget);
    expect(find.textContaining('RSI 机库同步'), findsOneWidget);
    expect(find.text('游戏定位'), findsOneWidget);
    expect(find.text('擅长岗位'), findsOneWidget);
    expect(find.text('想参与'), findsOneWidget);
    expect(find.text("Aster's Wing"), findsOneWidget);
    expect(find.text('Northwind 联合社区'), findsOneWidget);
    expect(find.textContaining('主岗位'), findsWidgets);
    expect(find.text('账号与识别'), findsNothing);
    // No chosen wallpaper: the page default fills the page, keyed as none.
    expect(find.byKey(const Key('profile-wallpaper-none')), findsOneWidget);
    final wallpaperStack = tester.getRect(
      find.byKey(const Key('profile-page-wallpaper-stack')),
    );
    final wallpaperBackdrop = tester.getRect(
      find.byKey(const Key('profile-wallpaper-none')),
    );
    expect(wallpaperBackdrop, wallpaperStack);
    expect(
      find.descendant(
        of: find.byKey(const Key('profile-identity-header')),
        matching: find.byKey(const Key('profile-wallpaper-image')),
      ),
      findsNothing,
    );
    expect(find.text('克拉克'), findsOneWidget);
    expect(find.textContaining('Carrack'), findsOneWidget);
    expect(find.text('秃鹫'), findsOneWidget);
    expect(find.text('宙斯 Mk II MR'), findsOneWidget);
    expect(
      find.byKey(const Key('profile-favorite-ship-image-ANVL_Carrack')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-favorite-ship-image-DRAK_Vulture')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-favorite-ship-image-RSI_Zeus_MR')),
      findsOneWidget,
    );

    final carrackCard = find.byKey(
      const Key('profile-favorite-ship-ANVL_Carrack'),
    );
    await tester.ensureVisible(carrackCard);
    await tester.tap(carrackCard);
    await tester.pumpAndSettle();
    expect(find.text('舰船资料'), findsOneWidget);
    expect(find.byKey(const Key('profile-ship-data-name')), findsOneWidget);
    final shipDialog = tester.getRect(find.byType(Dialog));
    final hero = tester.getRect(
      find.byKey(const Key('profile-ship-data-hero')),
    );
    expect(shipDialog.width, greaterThanOrEqualTo(620));
    expect(hero.width, greaterThan(550));
    expect(hero.width / hero.height, closeTo(shipArtCardAspectRatio, 0.01));
    expect(hero.center.dx, closeTo(shipDialog.center.dx, 1));
    expect(
      tester.getRect(find.byKey(const Key('profile-ship-data-facts'))).top,
      greaterThan(hero.bottom),
    );
    expect(find.text('克拉克'), findsWidgets);
    expect(find.text('Carrack'), findsWidgets);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('制造商')),
      findsOneWidget,
    );
    expect(find.text(r'$1,900'), findsWidgets);
    final originalSize = tester.view.physicalSize;
    tester.view.physicalSize = const Size(800, 500);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final compactHero = tester.getRect(
      find.byKey(const Key('profile-ship-data-hero')),
    );
    expect(compactHero.left, greaterThanOrEqualTo(24));
    expect(compactHero.right, lessThanOrEqualTo(776));
    expect(
      tester.getRect(find.byKey(const Key('profile-ship-data-close'))).bottom,
      lessThan(500),
    );
    tester.view.physicalSize = originalSize;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-ship-data-close')));
    await tester.pumpAndSettle();

    final grid = tester.getRect(find.byKey(const Key('profile-module-grid')));
    final favoriteShips = tester.getRect(
      find.byKey(const Key('profile-module-favorite-ships')),
    );
    final hangar = tester.getRect(
      find.byKey(const Key('profile-module-hangar-summary')),
    );
    final positions = tester.getRect(
      find.byKey(const Key('profile-module-skilled-roles')),
    );
    expect(favoriteShips.width, closeTo(grid.width, 0.1));
    expect(hangar.top, greaterThan(favoriteShips.bottom));
    expect(positions.top, greaterThan(hangar.bottom));
    expect(positions.width, closeTo(grid.width, 0.1));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('profile-showcase-main-role')))
          .data,
      isNotEmpty,
    );

    await tester.ensureVisible(find.byKey(const Key('profile-edit')));
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-editor-panel')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byKey(const Key('profile-module-size-favorite-ships')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('profile-module-down-favorite-ships')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-favorite-ship-image-RSI_Zeus_MR')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('profile-call-sign-field')),
      'Northwind',
    );
    await tester.enterText(
      find.byKey(const Key('profile-about-field')),
      '远征与支援玩家。',
    );
    await tester.ensureVisible(find.byKey(const Key('profile-current-avatar')));
    expect(find.byKey(const Key('profile-current-avatar')), findsOneWidget);
    expect(find.byKey(const Key('profile-avatar-2')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(find.text('Northwind'), findsOneWidget);
    expect(find.text('远征与支援玩家。'), findsOneWidget);
    expect(find.text('@Aster-Lin'), findsOneWidget);
    expect(find.byKey(const Key('profile-wallpaper-none')), findsOneWidget);
  });

  testWidgets('hangar overview reveals information by approved grid span', (
    tester,
  ) async {
    await _pumpSignedInShell(tester, size: const Size(1280, 1000));
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('profile-hangar-composition-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-hangar-recent-ship-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-hangar-recent-ship-image')),
      findsOneWidget,
    );
    expect(find.text('最近入库 · 2026-08-26'), findsOneWidget);
    expect(find.text('F7C-M 超级大黄蜂 MK II'), findsOneWidget);
    // One bar per role, scaled to the largest (Steam-style page).
    final combatSegment = tester.getRect(
      find.byKey(const Key('profile-hangar-composition-segment-0')),
    );
    final otherSegment = tester.getRect(
      find.byKey(const Key('profile-hangar-composition-segment-1')),
    );
    expect(combatSegment.height, 7);
    expect(otherSegment.top, greaterThan(combatSegment.bottom));
    expect(combatSegment.width / otherSegment.width, closeTo(2, 0.05));
    final combatColor = tester
        .widget<ColoredBox>(
          find.byKey(const Key('profile-hangar-composition-segment-0')),
        )
        .color;
    final otherColor = tester
        .widget<ColoredBox>(
          find.byKey(const Key('profile-hangar-composition-segment-1')),
        )
        .color;
    expect(combatColor, isNot(otherColor));

    await tester.ensureVisible(find.byKey(const Key('profile-edit')));
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();

    // One column: no cell size to choose, the overview keeps every panel.
    expect(
      find.byKey(
        Key('profile-module-size-${PersonalProfileModuleIds.hangarSummary}'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('profile-hangar-recent-ship-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-hangar-sync-footer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visitor preview hides owner actions and can return', (
    tester,
  ) async {
    await _pumpSignedInShell(tester);
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-positions-edit')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('profile-preview')));
    await tester.tap(find.byKey(const Key('profile-preview')));
    await tester.pumpAndSettle();

    expect(find.text('正在预览访客视角'), findsOneWidget);
    expect(find.byKey(const Key('profile-edit')), findsNothing);
    expect(find.byKey(const Key('profile-positions-edit')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('profile-preview-exit')));
    await tester.tap(find.byKey(const Key('profile-preview-exit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-edit')), findsOneWidget);
    expect(find.text('正在预览访客视角'), findsNothing);
  });

  testWidgets('retired wallpapers stay unavailable while visibility saves', (
    tester,
  ) async {
    await _pumpSignedInShell(tester, size: const Size(1280, 1000));
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-wallpaper-none')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('profile-edit')));
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('profile-background-picker-grid')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('profile-wallpaper-choice-formation-flight')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('profile-background-picker-open')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('profile-background-picker-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-wallpaper-choice-none')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-wallpaper-choice-levski-yard')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('profile-wallpaper-choice-asteroid-belt')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('profile-wallpaper-choice-lorville-corridor')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('profile-background-picker-close')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-edit-cancel')));
    await tester.tap(find.byKey(const Key('profile-edit-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-wallpaper-none')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('profile-edit')));
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('profile-visibility-selector')),
    );
    await tester.tap(find.byKey(const Key('profile-visibility-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅自己可见').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-wallpaper-none')), findsOneWidget);
    expect(find.text('仅自己可见'), findsOneWidget);
    // The owner is told what visitors still see.
    expect(find.byKey(const Key('profile-public-header-note')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('profile-preview')));
    await tester.tap(find.byKey(const Key('profile-preview')));
    await tester.pumpAndSettle();
    // Not a blank page any more (user rule, 2026-10-20): the always-public
    // header stays, and only the content below is shielded.
    expect(find.byKey(const Key('profile-identity-header')), findsOneWidget);
    expect(find.text('Aster Lin'), findsWidgets);
    expect(find.text('@Aster-Lin'), findsNothing);
    expect(
      find.byKey(const Key('profile-private-visitor-view')),
      findsOneWidget,
    );
    expect(find.text('其余内容未公开'), findsOneWidget);
    expect(find.textContaining('头像、名字和交易时段始终公开'), findsOneWidget);
    expect(find.byKey(const Key('profile-public-header-note')), findsNothing);
    expect(
      find.byKey(const Key('profile-module-favorite-ships')),
      findsNothing,
    );
    // No wallpaper of the owner's: the page default (a Fan Kit picture) shows.
    expect(find.byKey(const Key('profile-cig-fankit-notice')), findsOneWidget);
  });

  // build 65: in a window about half a 2560 screen wide the floating
  // notice sat on the side rail's 组织 block.
  for (final width in [1280.0, 2560.0]) {
    testWidgets('the Fan Kit notice never covers the page column at $width', (
      tester,
    ) async {
      await _pumpSignedInShell(tester, size: Size(width, 1000));
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
      await tester.pumpAndSettle();
      final notice = find.byKey(const Key('profile-cig-fankit-notice'));
      expect(notice, findsOneWidget);
      final column = tester.getRect(
        find.byKey(const Key('profile-steam-column')),
      );
      await tester.ensureVisible(notice);
      await tester.pumpAndSettle();
      final rect = tester.getRect(notice);
      final columnNow = tester.getRect(
        find.byKey(const Key('profile-steam-column')),
      );
      expect(
        rect.overlaps(columnNow),
        isFalse,
        reason: 'width $width: notice $rect, column $columnNow',
      );
      if (width == 2560) {
        // Wide: it floats in the wallpaper margin beside the column.
        expect(rect.left, greaterThanOrEqualTo(column.right));
      } else {
        // Narrow: it follows the page, under the column.
        expect(rect.top, greaterThanOrEqualTo(columnNow.bottom));
      }
    });
  }

  testWidgets('profile showcases move up and down the single column', (
    tester,
  ) async {
    await _pumpSignedInShell(tester, size: const Size(1280, 1000));
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-edit')));
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();

    final roles = find.byKey(const Key('profile-module-skilled-roles'));
    final hangar = find.byKey(const Key('profile-module-hangar-summary'));
    expect(
      tester.getTopLeft(roles).dy,
      greaterThan(tester.getTopLeft(hangar).dy),
    );
    // The last showcase (the trading card, shown last by default) cannot
    // move further down.
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('profile-module-down-trade-card')),
          )
          .onPressed,
      isNull,
    );
    final up = find.byKey(const Key('profile-module-up-skilled-roles'));
    await tester.ensureVisible(up);
    await tester.tap(up);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(roles).dy, lessThan(tester.getTopLeft(hangar).dy));
    expect(
      tester.getTopLeft(roles).dx,
      closeTo(tester.getTopLeft(hangar).dx, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('English profile remains localized at compact desktop size', (
    tester,
  ) async {
    await _pumpSignedInShell(
      tester,
      size: const Size(900, 620),
      preferences: InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(
          locale: const Locale('en', 'US'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsWidgets);
    expect(find.text('Favorite ships'), findsOneWidget);
    expect(find.text('Carrack'), findsOneWidget);
    expect(find.text('克拉克'), findsNothing);
    expect(find.text('Ship composition'), findsOneWidget);
    expect(find.textContaining('RSI hangar sync'), findsOneWidget);
    expect(find.textContaining('Expedition commander'), findsWidgets);
    expect(find.text('Organizations'), findsOneWidget);
    expect(find.text('Fleet member · ASTER'), findsOneWidget);
    expect(find.text('Operation host · NORTH'), findsOneWidget);
    expect(find.text('远征指挥'), findsNothing);
    expect(
      find.byKey(const Key('profile-module-skilled-roles')),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byKey(const Key('profile-module-grid'))).height,
      greaterThanOrEqualTo(140),
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('profile-preview')));
    await tester.tap(find.byKey(const Key('profile-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Previewing the visitor view'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account and identity opens inside the settings workspace', (
    tester,
  ) async {
    await _pumpSignedInShell(tester);
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('account-menu-account-and-identity')),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置分类'), findsOneWidget);
    expect(find.text('资料偏好'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-section-generalData')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings-section-aboutLegal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-help-support-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('help-topic-button-notices')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-cig-fankit-notice')), findsOneWidget);
    expect(find.text(CigFankitLegalNotice.requiredEnglish), findsOneWidget);
  });

  // 0.7.3 default is scan: the profile editor works there too. Buttons are
  // found by key and checked through semantics, not widget type.
  for (final requiresReload in [true, false]) {
    testWidgets(
      'scan interaction smoke: editor save; reload gate: $requiresReload',
      (tester) async {
        final port = _FailedEditPort(requiresReload);
        await _pumpSignedInShell(
          tester,
          personalProfilePort: port,
          interaction: InteractionStyle.scan,
        );
        await tester.tap(find.byKey(const Key('account-command')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('account-menu-personal-profile')),
        );
        await tester.pumpAndSettle();
        final edit = find.byKey(const Key('profile-edit'));
        expectScanSuite(tester, edit);
        expectButtonState(tester, edit, enabled: true);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('profile-call-sign-field'));
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Scan draft');
        final save = find.byKey(const Key('profile-save'));
        await tester.ensureVisible(save);
        expectButtonState(tester, save, enabled: true);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(port.saves, 1);
        expect(find.text('Scan draft'), findsOneWidget);
        expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
        expectButtonState(tester, save, enabled: !requiresReload);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpSignedInShell(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
  InMemoryAppPreferences? preferences,
  InMemoryShellChrome? shellChrome,
  PersonalProfilePort? personalProfilePort,
  InteractionStyle interaction = InteractionStyle.standard,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forTest(
    windowChrome: InMemoryWindowChrome(),
    preferences: await pinInteraction(preferences, interaction),
    shellChrome: shellChrome,
    accountPort: InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    personalProfilePort:
        personalProfilePort ??
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
  );
  await tester.pumpWidget(StarBridgeApp(composition: composition));
  await tester.pumpAndSettle();
}

class _FailedEditPort implements PersonalProfilePort {
  _FailedEditPort(this.requiresReload);
  final bool requiresReload;
  final source = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  int saves = 0;
  int reads = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<PersonalProfileSnapshot> read() {
    reads++;
    return source.read();
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    saves++;
    return PersonalProfileActionResult(
      PersonalProfileActionOutcome.failed,
      requiresReload: requiresReload,
      failureKey: requiresReload
          ? 'profile.error.writeUnconfirmed'
          : 'profile.local.failed',
    );
  }

  @override
  Future<void> close() => source.close();
}
