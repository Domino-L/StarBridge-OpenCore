import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/home/home_page.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';

void main() {
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
