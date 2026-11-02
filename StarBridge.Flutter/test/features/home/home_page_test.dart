import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence_widgets.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_layers.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_scope.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_halloween_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';

import '../../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;

import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/home/home_page.dart';
import 'package:starbridge_flutter/features/home/home_scene.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';

void main() {
  testWidgets('launch backdrop survives identity refresh and leaving Home', (
    tester,
  ) async {
    final rooms = PartyRoomsModule(
      _RoomPort(RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026))),
    );
    addTearDown(rooms.dispose);
    final chrome = InMemoryShellChrome();
    Widget page() => _app(
      HomePage(
        chrome: chrome,
        rooms: rooms,
        scene: const ColoredBox(color: Colors.black),
      ),
    );
    final expected = {
      HomeScenes.orisonNight: '十字军 · 奥里森',
      HomeScenes.area18Dusk: '弧光星 · 18区',
      HomeScenes.lorvilleSkyline: '赫斯顿 · 罗威尔',
      HomeScenes.lorvillePort: '赫斯顿 · 罗威尔',
    }[HomeScenes.forLaunch]!;
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text(expected), findsOneWidget);
    chrome.replace(
      InMemoryShellChrome.connectedProjection.copyWith(
        accountLabel: 'Synthetic Pilot',
        accountSignedIn: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(expected), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text(expected), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home caption follows backdrop in each supported locale', (
    tester,
  ) async {
    final rooms = PartyRoomsModule(
      _RoomPort(RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026))),
    );
    addTearDown(rooms.dispose);
    final chrome = InMemoryShellChrome();
    for (final entry in [
      (const Locale('zh', 'CN'), HomeScenes.area18Dusk, '弧光星 · 18区'),
      (const Locale('zh', 'TW'), HomeScenes.area18Dusk, '弧光星 · 18區'),
      (const Locale('en'), HomeScenes.area18Dusk, 'ArcCorp · Area18'),
      (const Locale('zh', 'CN'), HomeScenes.orisonNight, '十字军 · 奥里森'),
      (const Locale('zh', 'TW'), HomeScenes.orisonNight, '十字軍 · 奧里森'),
      (const Locale('en'), HomeScenes.orisonNight, 'Crusader · Orison'),
      (const Locale('zh', 'CN'), HomeScenes.lorvilleSkyline, '赫斯顿 · 罗威尔'),
      (const Locale('zh', 'TW'), HomeScenes.lorvilleSkyline, '赫斯頓 · 羅威爾'),
      (const Locale('en'), HomeScenes.lorvilleSkyline, 'Hurston · Lorville'),
      (const Locale('zh', 'CN'), HomeScenes.lorvillePort, '赫斯顿 · 罗威尔'),
      (const Locale('zh', 'TW'), HomeScenes.lorvillePort, '赫斯頓 · 羅威爾'),
      (const Locale('en'), HomeScenes.lorvillePort, 'Hurston · Lorville'),
    ]) {
      await tester.pumpWidget(
        _app(
          HomePage(
            chrome: chrome,
            rooms: rooms,
            backdrop: entry.$2,
            scene: const ColoredBox(color: Colors.black),
          ),
          locale: entry.$1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.$3), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'home follows confirmed offline instead of stale online or game state',
    (tester) async {
      final port = ModePort(), mode = ConnectionModeController(port);
      await tester.runAsync(mode.refresh);
      final source = ValueNotifier(
        const ManualPresenceSnapshot(
          scope: 7,
          confirmedMode: PresenceVisibility.online,
          automaticKey: 'presence.inGame',
        ),
      );
      final presence = ManualPresenceController(
        source: source,
        connectionMode: mode,
      );
      final chrome = InMemoryShellChrome(
        initial: InMemoryShellChrome.connectedProjection.copyWith(
          accountSignedIn: true,
          gamePresence: GamePresenceState.running,
        ),
      );
      final rooms = PartyRoomsModule(
        _RoomPort(
          RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026)),
        ),
      );
      await tester.pumpWidget(
        _app(
          HomePage(
            chrome: chrome,
            rooms: rooms,
            presence: presence,
            scene: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('游戏中'), findsOneWidget);
      port.current = modeFact('offline');
      await tester.runAsync(mode.refresh);
      await tester.pumpAndSettle();
      expect(find.text('离线'), findsOneWidget);
      expect(find.text('游戏中'), findsNothing);
      expect(find.text('应用在线'), findsNothing);
      port.current = modeFact('online');
      await tester.runAsync(mode.refresh);
      await tester.pumpAndSettle();
      expect(find.text('离线'), findsNothing);
      expect(find.text('游戏中'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      rooms.dispose();
      presence.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    },
  );
  testWidgets('home status matches the account menu badge as it changes', (
    tester,
  ) async {
    final source = ValueNotifier(
      const ManualPresenceSnapshot(
        scope: 1,
        confirmedMode: PresenceVisibility.invisible,
        automaticKey: 'presence.online',
      ),
    );
    final presence = ManualPresenceController(source: source);
    final chrome = InMemoryShellChrome(
      initial: InMemoryShellChrome.connectedProjection.copyWith(
        accountSignedIn: true,
        gamePresence: GamePresenceState.running,
      ),
    );
    final rooms = PartyRoomsModule(
      _RoomPort(RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026))),
    );
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            ManualPresenceBadge(controller: presence),
            Expanded(
              child: HomePage(
                chrome: chrome,
                rooms: rooms,
                presence: presence,
                scene: const ColoredBox(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final badge = find.byKey(const Key('manual-presence-self'));
    final hero = find.byKey(const Key('home-hero'));
    List<String> heroTexts() => [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: hero, matching: find.byType(Text)),
      ))
        text.data ?? '',
    ];
    Color heroDot() {
      final dot = tester.widget<Container>(
        find.descendant(of: hero, matching: find.byType(Container)).first,
      );
      return (dot.decoration! as BoxDecoration).color!;
    }

    Future<void> show(String automaticKey) async {
      source.value = ManualPresenceSnapshot(
        scope: 1,
        confirmedMode: PresenceVisibility.online,
        automaticKey: automaticKey,
      );
      await tester.pumpAndSettle();
    }

    final colors = tester.element(badge).tokens.colors;
    // 隐身：游戏在运行、应用连着，也只写隐身。
    expect(tester.widget<Text>(badge).data, '隐身');
    expect(heroTexts(), contains('隐身'));
    expect(heroTexts(), isNot(contains('应用在线')));
    expect(heroTexts(), isNot(contains('游戏中')));
    expect(heroDot(), colors.offline);
    await show('presence.online');
    expect(tester.widget<Text>(badge).data, '应用在线');
    expect(heroTexts(), contains('应用在线'));
    expect(heroDot(), colors.info);
    await show('presence.away');
    expect(tester.widget<Text>(badge).data, '暂离');
    expect(heroTexts(), contains('暂离'));
    expect(heroDot(), colors.warning);
    await show('presence.inGame');
    expect(tester.widget<Text>(badge).data, '游戏中');
    expect(heroTexts(), contains('游戏中'));
    expect(heroDot(), colors.success);
    await show('presence.offline');
    expect(tester.widget<Text>(badge).data, '离线');
    expect(heroTexts(), contains('离线'));
    expect(heroDot(), colors.offline);
    await tester.pumpWidget(const SizedBox());
    rooms.dispose();
    presence.dispose();
    source.dispose();
  });

  testWidgets('home writes no status until it is confirmed', (tester) async {
    final source = ValueNotifier(const ManualPresenceSnapshot(scope: 1));
    final presence = ManualPresenceController(source: source);
    final rooms = PartyRoomsModule(
      _RoomPort(RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026))),
    );
    await tester.pumpWidget(
      _app(
        HomePage(
          chrome: InMemoryShellChrome(
            initial: InMemoryShellChrome.connectedProjection.copyWith(
              accountSignedIn: true,
            ),
          ),
          rooms: rooms,
          presence: presence,
          backdrop: HomeScenes.area18Dusk,
          scene: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('待确认'), findsNothing);
    expect(find.text('应用在线'), findsNothing);
    expect(find.text('弧光星 · 18区'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    rooms.dispose();
    presence.dispose();
    source.dispose();
  });

  testWidgets('signed out home keeps the app status', (tester) async {
    final source = ValueNotifier(
      const ManualPresenceSnapshot(
        scope: 1,
        confirmedMode: PresenceVisibility.invisible,
      ),
    );
    final presence = ManualPresenceController(source: source);
    final rooms = PartyRoomsModule(
      _RoomPort(RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026))),
    );
    await tester.pumpWidget(
      _app(
        HomePage(
          chrome: InMemoryShellChrome(),
          rooms: rooms,
          presence: presence,
          scene: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('隐身'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    rooms.dispose();
    presence.dispose();
    source.dispose();
  });

  group('holiday blessing', () {
    late PartyRoomsModule rooms;
    setUp(() {
      rooms = PartyRoomsModule(
        _RoomPort(
          RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026)),
        ),
      );
    });
    tearDown(() => rooms.dispose());

    Future<String> greeting(
      WidgetTester tester, {
      required AppearanceLayers layers,
      Locale locale = const Locale('zh', 'CN'),
      String account = 'Lin',
    }) async {
      await tester.pumpWidget(
        AppearanceScope(
          layers: layers,
          child: _app(
            HomePage(
              chrome: InMemoryShellChrome(
                initial: InMemoryShellChrome.connectedProjection.copyWith(
                  accountLabel: account,
                  accountSignedIn: true,
                ),
              ),
              rooms: rooms,
              now: DateTime(2026, 10, 31, 20),
              scene: const ColoredBox(color: Colors.black),
            ),
            locale: locale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester.widget<Text>(find.byKey(const Key('home-greeting'))).data!;
    }

    testWidgets('every holiday has one in each language', (tester) async {
      const expected = {
        ('halloween', 'zh', 'CN'): '万圣节快乐 🎃',
        ('halloween', 'zh', 'TW'): '萬聖節快樂 🎃',
        ('halloween', 'en', 'US'): 'Happy Halloween 🎃',
        ('xmas', 'zh', 'CN'): '圣诞和新年快乐 🎄',
        ('xmas', 'zh', 'TW'): '聖誕和新年快樂 🎄',
        ('xmas', 'en', 'US'): 'Happy holidays 🎄',
      };
      for (final theme in BuiltInHolidayCalendar().themes) {
        for (final locale in AppStrings.supportedLocales) {
          final text = await greeting(
            tester,
            layers: AppearanceLayers(holiday: theme),
            locale: locale,
          );
          final line =
              expected[(theme.id, locale.languageCode, locale.countryCode)]!;
          expect(text, endsWith(line), reason: '${theme.id} $locale');
        }
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sits at the end of the greeting', (tester) async {
      final holiday = AppearanceLayers(holiday: halloweenHolidayTheme);
      final zh = await greeting(tester, layers: holiday);
      expect(zh, startsWith('晚上好，Lin '));
      expect(zh, endsWith('，万圣节快乐 🎃'));
      final en = await greeting(
        tester,
        layers: holiday,
        locale: const Locale('en'),
      );
      expect(en, startsWith('Good evening, Lin · '));
      expect(en, endsWith('. Happy Halloween 🎃'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('none outside a holiday or with the switch off', (
      tester,
    ) async {
      final plain = await greeting(tester, layers: AppearanceLayers.standard);
      expect(plain, startsWith('晚上好，Lin '));
      expect(plain, isNot(contains('快乐')));
      final off = await greeting(
        tester,
        layers: AppearanceLayers(
          holiday: xmasHolidayTheme,
          holidayEnabled: false,
        ),
      );
      expect(off, plain);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('long name in a narrow window stays inside', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await greeting(
        tester,
        layers: AppearanceLayers(holiday: xmasHolidayTheme),
        account:
            'A_Very_Long_Citizen_Handle_For_Testing_Width_Limits_0123456789',
      );
      final box = tester.getRect(find.byKey(const Key('home-greeting')));
      expect(box.right, lessThanOrEqualTo(1280));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('home scene follows viewport height beyond the old banner cap', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rooms = PartyRoomsModule(
      _RoomPort(
        RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026, 9, 13)),
      ),
    );
    addTearDown(rooms.dispose);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpWidget(
      _app(
        HomePage(
          chrome: InMemoryShellChrome(),
          rooms: rooms,
          scene: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('home-hero'))).height,
      closeTo(720 * .62, .1),
    );
    tester.view.physicalSize = const Size(2560, 1392);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('home-hero'))).height,
      closeTo(1392 * .62, .1),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 400);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('home-hero'))).height, 250);
    expect(tester.takeException(), isNull);
  });
  testWidgets('signed out greeting keeps the title without a substitute name', (
    tester,
  ) async {
    final rooms = PartyRoomsModule(
      _RoomPort(
        RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026, 9, 13)),
      ),
    );
    final chrome = InMemoryShellChrome(
      initial: InMemoryShellChrome.connectedProjection.copyWith(
        accountLabel: 'Old Name',
        accountSignedIn: false,
      ),
    );
    await tester.pumpWidget(
      _app(
        HomePage(
          chrome: chrome,
          rooms: rooms,
          now: DateTime(2026, 9, 13, 8),
          scene: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final greeting = tester
        .widget<Text>(find.byKey(const Key('home-greeting')))
        .data!;
    expect(greeting, isNot(contains('Old Name')));
    expect(greeting, isNot(contains('旅行者')));
    expect(greeting, matches(RegExp(r'^早上好，\S+$')));
    await tester.pumpWidget(const SizedBox.shrink());
    rooms.dispose();
  });
  testWidgets('凌晨算晚上，5 点到 10 点才是早上好', (tester) async {
    final rooms = PartyRoomsModule(
      _RoomPort(
        RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026, 9, 13)),
      ),
    );
    final chrome = InMemoryShellChrome();
    for (final (hour, expected) in const [
      (0, '晚上好'),
      (1, '晚上好'),
      (4, '晚上好'),
      (5, '早上好'),
      (10, '早上好'),
      (11, '中午好'),
      (18, '晚上好'),
    ]) {
      await tester.pumpWidget(
        _app(
          HomePage(
            key: ValueKey(hour),
            chrome: chrome,
            rooms: rooms,
            now: DateTime(2026, 9, 13, hour),
            scene: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('home-greeting'))).data,
        startsWith(expected),
        reason: '$hour 点',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    rooms.dispose();
  });
  testWidgets('home supports narrow English layout without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rooms = PartyRoomsModule(
      _RoomPort(
        RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026, 9, 13)),
      ),
    );
    await tester.pumpWidget(
      _app(
        HomePage(
          chrome: InMemoryShellChrome(),
          rooms: rooms,
          now: DateTime(2026, 9, 13, 8),
          scene: const ColoredBox(color: Colors.black),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Good morning,'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('More features in development'), findsOneWidget);
    expect(find.byKey(const Key('home-fortune-observe')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    rooms.dispose();
  });
  testWidgets('home retains live identity without loading removed cards', (
    tester,
  ) async {
    final port = _RoomPort(
      RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026, 9, 13)),
    );
    final rooms = PartyRoomsModule(port);
    final chrome = InMemoryShellChrome(
      initial: InMemoryShellChrome.connectedProjection.copyWith(
        accountLabel: 'domino_CN',
        accountSignedIn: true,
        gamePresence: GamePresenceState.running,
      ),
    );
    await tester.pumpWidget(
      _app(
        HomePage(
          chrome: chrome,
          rooms: rooms,
          now: DateTime(2026, 9, 13, 20),
          scene: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('晚上好，domino_CN'), findsOneWidget);
    expect(find.text('更多功能开发中'), findsOneWidget);
    expect(find.text('当前房间'), findsNothing);
    expect(find.text('今日星海运势'), findsNothing);
    expect(find.byKey(const Key('home-hero-bottom-fade')), findsOneWidget);
    expect(port.reads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    rooms.dispose();
  });

  testWidgets('home shows development message without room actions', (
    tester,
  ) async {
    final rooms = PartyRoomsModule(
      _RoomPort(
        RoomDirectory(rooms: const [], serverTime: DateTime.utc(2026, 9, 13)),
      ),
    );
    await tester.pumpWidget(
      _app(
        HomePage(
          chrome: InMemoryShellChrome(),
          rooms: rooms,
          now: DateTime(2026, 9, 13, 8),
          scene: const ColoredBox(color: Color(0xFF102C39)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('更多功能开发中'), findsOneWidget);
    expect(find.text('浏览房间'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    rooms.dispose();
  });
}

Widget _app(Widget home, {Locale locale = const Locale('zh', 'CN')}) {
  final tokens = StyleRegistry()
      .resolve('future-restraint-a', AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(body: home),
  );
}

final class _RoomPort implements PartyRoomsPort {
  _RoomPort(this.directory);
  final RoomDirectory directory;
  int reads = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<RoomReadResult> read() async {
    reads++;
    return RoomReadResult(RoomReadState.ready, directory: directory);
  }

  @override
  Future<void> close() async {}
}
