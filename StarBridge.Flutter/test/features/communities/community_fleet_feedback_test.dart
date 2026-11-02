import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_holo_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_ships_prefetch.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_wheel_gate.dart';

import '../friends/social_layout_test.dart' show app;

void main() {
  group('wheel gate', () {
    late Duration now;
    late OfficialFleetWheelGate gate;
    setUp(() {
      now = Duration.zero;
      gate = OfficialFleetWheelGate(now: () => now);
    });

    test('one notch at the top does not switch, two do', () {
      expect(gate.up(100, bodyAtTop: true), isFalse);
      now += const Duration(milliseconds: 100);
      expect(gate.up(100, bodyAtTop: true), isTrue);
    });

    test('the scroll that reached the top cannot carry on into a switch', () {
      gate.bodyMoved();
      for (var i = 0; i < 5; i++) {
        now += const Duration(milliseconds: 50);
        expect(gate.up(100, bodyAtTop: true), isFalse);
      }
      now += OfficialFleetWheelGate.rest;
      expect(gate.up(100, bodyAtTop: true), isFalse);
      now += const Duration(milliseconds: 100);
      expect(gate.up(100, bodyAtTop: true), isTrue);
    });

    test('below the top never switches', () {
      for (var i = 0; i < 5; i++) {
        now += const Duration(seconds: 1);
        expect(gate.up(500, bodyAtTop: false), isFalse);
      }
    });

    test('notches far apart do not add up', () {
      expect(gate.up(100, bodyAtTop: true), isFalse);
      now += OfficialFleetWheelGate.pause + const Duration(milliseconds: 1);
      expect(gate.up(100, bodyAtTop: true), isFalse);
    });
  });

  group('ship list prefetch', () {
    Future<int> pump(
      WidgetTester tester, {
      required int rows,
      bool canLoad = true,
    }) async {
      var loads = 0;
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          CommunityShipsPrefetch(
            canLoad: canLoad,
            load: () => loads++,
            child: ListView.builder(
              itemCount: rows,
              itemBuilder: (_, index) => SizedBox(height: 100, key: ValueKey(index)),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return loads;
    }

    testWidgets('a first page shorter than the window loads without scrolling', (
      tester,
    ) async {
      expect(await pump(tester, rows: 3), greaterThan(0));
    });

    testWidgets('a long page waits until two screens remain', (tester) async {
      expect(await pump(tester, rows: 200), 0);
    });

    testWidgets('nothing loads while it cannot', (tester) async {
      expect(await pump(tester, rows: 3, canLoad: false), 0);
    });
  });

  testWidgets('owners online and in game are separate, in their status colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const CommunityHoloShipsPreview(online: 2, inGame: 3, offline: 1)),
    );
    await tester.pump();
    final context = tester.element(find.byType(CommunityHoloShipsPreview));
    Text text(String key) => tester.widget<Text>(find.byKey(Key(key)));
    final online = text('community-tile-ships-online');
    final inGame = text('community-tile-ships-in-game');
    expect(online.data, contains('2'));
    expect(inGame.data, contains('3'));
    expect(online.style?.color, context.tokens.colors.info);
    expect(inGame.style?.color, context.tokens.colors.success);
    await tester.pumpWidget(
      app(const CommunityHoloShipsPreview(online: 0, inGame: 0, offline: 0)),
    );
    await tester.pump();
    expect(
      text('community-tile-ships-online').style?.color,
      context.tokens.colors.textDisabled,
    );
  });
}
