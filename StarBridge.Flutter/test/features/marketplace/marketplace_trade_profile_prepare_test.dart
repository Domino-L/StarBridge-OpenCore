import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';

import '../../shared/clock_field_test.dart' show pickClock;
import 'marketplace_slice4_test.dart' show preview;

/// What the Host projects for an account that never set its SCM trade profile.
MarketRow unsetProfile() => {
  'tradeTime': List.filled(7, 0),
  'tradeStartTime': null,
  'tradeEndTime': null,
  'timezoneId': null,
  'userMobile': null,
  'mark': null,
  'language': 0,
};

void main() {
  testWidgets(
    'preparation opens every incomplete section and saves both in one go',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sent = <MarketRow>[];
      await tester.pumpWidget(
        preview(
          TradeProfileForm(
            read: () async => unsetProfile(),
            zones: () async => [
              {'id': 1, 'label': 'UTC', 'offsetMinutes': 0},
            ],
            current: () => true,
            // SCM only reported the first missing item.
            missing: 'marketplace.trade_time_required',
            write: (changes) async {
              sent.add(changes);
              return {
                'profile': {...unsetProfile(), ...changes},
                'confirmed': true,
              };
            },
          ),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      // Contact is also empty in the read-back profile, so it is not folded away.
      expect(
        find.byKey(const ValueKey('trade-profile-contact')),
        findsOneWidget,
      );
      await tester.tap(find.text('每天'));
      await pickClock(tester, 'trade-profile-time-start', 'hour', 20);
      await pickClock(tester, 'trade-profile-time-start', 'minute', 0);
      await pickClock(tester, 'trade-profile-time-end', 'hour', 22);
      await pickClock(tester, 'trade-profile-time-end', 'minute', 0);
      await tester.tap(find.byKey(const Key('trade-profile-zone')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UTC').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('trade-profile-contact')),
        'discord:fixture',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single['userMobile'], 'discord:fixture');
      expect(sent.single['tradeTime'], List.filled(7, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a complete section stays folded until validation points at it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      preview(
        TradeProfileForm(
          read: () async => {
            ...unsetProfile(),
            'userMobile': 'discord:fixture',
          },
          zones: () async => [
            {'id': 1, 'label': 'UTC', 'offsetMinutes': 0},
          ],
          current: () => true,
          missing: 'marketplace.trade_time_required',
          write: (_) async => throw StateError('must not write'),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trade-profile-contact')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (code, expected) in [
    ('trade_profile.rejected', '暂时读不到交易资料，请稍后重新读取 (trade_profile.rejected)'),
    ('marketplace.unavailable', '暂时读不到交易资料，请稍后重新读取 (marketplace.unavailable)'),
    ('account.reauthorization_required', null),
  ]) {
    testWidgets('a failed read says so and keeps the code ($code)', (
      tester,
    ) async {
      var logins = 0;
      await tester.pumpWidget(
        preview(
          TradeProfileForm(
            read: () async => throw MarketplaceTradeError(code),
            zones: () async => [],
            current: () => true,
            login: () async => logins++,
            write: (_) async => throw StateError('must not write'),
          ),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('暂时无法保存'), findsNothing);
      if (expected != null) {
        expect(find.text(expected), findsOneWidget);
      } else {
        await tester.tap(find.text('重新授权 SCM'));
        expect(logins, 1);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
