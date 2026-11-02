import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile_model.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile_copy.dart';

import '../../shared/clock_field_test.dart' show clockShown, pickClock;
import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_trade_precheck_test.dart' show PrecheckPort;

MarketRow fixtureProfile() => {
  'tradeTime': [1, 1, 1, 1, 1, 1, 1],
  'tradeStartTime': '23:30',
  'tradeEndTime': '01:00',
  'timezoneId': 1,
  'userMobile': 'contact',
  'mark': 'unchanged',
  'language': 0,
};

class ProfilePort extends PrecheckPort implements MarketplaceTradeProfilePort {
  ProfilePort() : super('marketplace.contact_required');
  int saves = 0;
  @override
  Future<MarketRow> tradeProfile([MarketRow? changes]) async {
    if (changes == null) return fixtureProfile();
    saves++;
    return {
      'profile': {...fixtureProfile(), ...changes},
      'confirmed': true,
    };
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('TRADE_PROFILE_CAPTURE')) return;
    for (final p in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Microsoft YaHei UI', 'assets/fonts/SourceHanSansCN-VF.ttf'),
    ]) {
      await (FontLoader(p.$1)..addFont(rootBundle.load(p.$2))).load();
    }
  });
  for (final mode in AppearanceMode.values.where(
    (m) => m == AppearanceMode.dark || m == AppearanceMode.light,
  )) {
    testWidgets('profile form ${mode.name} layout', (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        preview(
          TradeProfileForm(
            read: () async => fixtureProfile(),
            zones: () async => [
              {'id': 1, 'label': 'UTC +08:00', 'offsetMinutes': 480},
            ],
            current: () => true,
            write: (_) async => {},
          ),
          mode,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('TRADE_PROFILE_CAPTURE')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('listing-preview')),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final folder = Directory(
            '../.artifacts/trading-hall-intake-20261015/trade-profile-20261019',
          );
          await folder.create(recursive: true);
          await File('${folder.path}/form-${mode.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test(
    'validates cross-day, short window, days and contact; optional omissions',
    () {
      final row = fixtureProfile();
      expect(tradeProfileValidation(row), isNull);
      expect(
        tradeProfileValidation({
          ...row,
          'tradeStartTime': '10:00',
          'tradeEndTime': '10:30',
        }),
        'trade_profile.time_range',
      );
      expect(
        tradeProfileValidation({...row, 'tradeTime': List.filled(7, 0)}),
        'trade_profile.no_day',
      );
      expect(
        tradeProfileValidation({...row, 'userMobile': '1234'}),
        'trade_profile.contact_invalid',
      );
      final changes = tradeProfileChanges(row, {
        ...row,
        'userMobile': 'new contact',
      });
      expect(changes.containsKey('mark'), isFalse);
      expect(changes.containsKey('language'), isFalse);
      expect(changes.containsKey('profileBackground'), isFalse);
      expect(changes.values.contains(null), isFalse);
      expect(
        tradeProfileChanges(
          {...row, 'mark': null},
          {...row, 'mark': ''},
        ).containsKey('mark'),
        isFalse,
      );
    },
  );
  test(
    'all profile copy has three languages and English contains no Chinese',
    () {
      for (final entry in tradeProfileCopy.entries) {
        expect(entry.value.length, 3, reason: entry.key);
        expect(entry.value.every((v) => v.isNotEmpty), isTrue);
        expect(
          RegExp(r'[一-鿿]').hasMatch(entry.value[2]),
          isFalse,
          reason: entry.key,
        );
      }
    },
  );
  testWidgets('30 minute window never writes; server read-back is displayed', (
    tester,
  ) async {
    var writes = 0;
    // A stored half-hour window (SCM's site once allowed it) is shown as is
    // and must be fixed before saving.
    await tester.pumpWidget(
      preview(
        TradeProfileForm(
          read: () async => {
            ...fixtureProfile(),
            'tradeStartTime': '10:00',
            'tradeEndTime': '10:30',
          },
          zones: () async => [
            {'id': 1, 'label': 'UTC', 'offsetMinutes': 0},
          ],
          current: () => true,
          write: (changes) async {
            writes++;
            return {
              'profile': {
                ...fixtureProfile(),
                'userMobile': 'filtered contact',
              },
              'confirmed': true,
            };
          },
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(clockShown(tester, 'trade-profile-time-end'), '10:30');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('请选择开始和结束时间，交易时段至少 1 小时'), findsOneWidget);
    await pickClock(tester, 'trade-profile-time-end', 'hour', 11);
    expect(clockShown(tester, 'trade-profile-time-end'), '11:30');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('trade-profile-contact')),
          )
          .controller!
          .text,
      'filtered contact',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'preparation saves without another trade and preserves quantity draft',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = ProfilePort();
      final market = MarketplaceController(port);
      await tester.pumpWidget(
        preview(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmMarketTrade(context, market, {
                'orderNumber': 'O1',
                'itemName': 'Fixture',
                'creatorType': 1,
                'availableQuantity': 5,
                'locationId': 1,
                'unitPrice': 10,
              }),
              child: const Text('open'),
            ),
          ),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Preserve the order draft across the nested profile dialog.
      await tester.tap(find.byKey(const Key('market-confirm-quantity-add')));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('确认发起'));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      await tester.tap(find.text('完善交易资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(port.saves, 1);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(find.text('确认发起'), findsOneWidget);
      expect(find.byType(TradeProfileForm), findsNothing);
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      market.dispose();
    },
  );

  testWidgets('uncertain save cannot replay and changed account cannot write', (
    tester,
  ) async {
    var writes = 0, current = true;
    await tester.pumpWidget(
      preview(
        TradeProfileForm(
          read: () async => fixtureProfile(),
          zones: () async => [
            {'id': 1, 'label': 'UTC', 'offsetMinutes': 0},
          ],
          current: () => current,
          write: (changes) async {
            writes++;
            return {'profile': fixtureProfile(), 'confirmed': false};
          },
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
