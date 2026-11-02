// User-approved preview 2026-10-30: the visitor page of an SCM member who never
// chose a visibility. Masked name until a trade, trade and account facts, and a
// shield that does not claim anybody picked "only me".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

Map<String, Object?> _facts({bool? banned = false, int? banCount = 0}) => {
  'reputation': 128,
  'completedTrades': 31,
  'sellOrders': 5,
  'buyOrders': 3,
  'lastOnlineDay': '2026-10-29',
  'siteRegisteredDay': '2025-03-12',
  'gameRegisteredDay': '2018-11-03',
  'language': 'zh',
  'utcOffsetMinutes': 480,
  'banned': banned,
  'banCount': banCount,
};

Map<String, Object?> _payload({
  Object? facts,
  bool defaulted = true,
  bool masked = true,
  String visibility = 'private',
  String name = 'S*****1',
  Object? window,
}) => {
  'schemaVersion': 1,
  'editable': false,
  'restricted': true,
  'visibility': visibility,
  'publicHeader': {
    'callSign': name,
    'avatarAssetId': null,
    'tradeWindow': window,
    'defaulted': defaulted,
    'nameMasked': masked,
    'facts': facts,
  },
};

class _Port implements PersonalProfilePort {
  _Port(this.snapshot);
  final PersonalProfileSnapshot snapshot;
  final _changes = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => _changes.stream;
  @override
  Future<PersonalProfileSnapshot> read() async => snapshot;
  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async =>
      const PersonalProfileActionResult(PersonalProfileActionOutcome.rejected);
  @override
  Future<void> close() => _changes.close();
}

Future<void> _show(WidgetTester tester, Map<String, Object?> payload, {double width = 1280}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final module = createPersonalProfileModule(
    _Port(parsePersonalProfileSnapshot(payload)),
  );
  addTearDown(module.dispose);
  await tester.runAsync(module.initialize);
  const locale = Locale('zh', 'CN');
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Scaffold(
        body: PersonalProfilePage(module: module, isVisitor: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('facts parse by kind and a released payload has none', () {
    final snapshot = parsePersonalProfileSnapshot(_payload(facts: _facts()));
    expect(snapshot.defaultedPage, isTrue);
    expect(snapshot.nameMasked, isTrue);
    expect(snapshot.publicFacts!.completedTrades, 31);
    expect(snapshot.publicFacts!.utcOffsetMinutes, 480);
    final old = parsePersonalProfileSnapshot({
      'schemaVersion': 1,
      'editable': false,
      'restricted': true,
      'visibility': 'friendsOnly',
      'publicHeader': {'callSign': 'Aster', 'avatarAssetId': null, 'tradeWindow': null},
    });
    expect(old.defaultedPage, isFalse);
    expect(old.nameMasked, isFalse);
    expect(old.publicFacts, isNull);
    for (final bad in [
      {'reputation': 'high'},
      {'lastOnlineDay': '2026-10-29 21:30'},
      {'lastOnlineDay': '2026-99-99'},
      {'siteRegisteredDay': '2026-02-31'},
      {'language': 'klingon'},
      {'banned': 'no'},
      {'completedTrades': -1},
      {'banCount': -2},
      {'utcOffsetMinutes': 100000},
      {'userMobile': 'QQ 1'},
    ]) {
      expect(
        () => parsePersonalProfileSnapshot(_payload(facts: bad)),
        throwsA(isA<BridgeFormatException>()),
        reason: '$bad',
      );
    }
  });

  test('an explicit choice cannot carry facts', () {
    expect(
      () => parsePersonalProfileSnapshot(
        _payload(facts: _facts(), defaulted: false),
      ),
      throwsA(isA<BridgeFormatException>()),
    );
  });

  testWidgets('a never-saved person: masked name, every approved fact, no scope', (tester) async {
    await _show(tester, _payload(facts: _facts()));
    expect(find.text('S*****1'), findsOneWidget);
    expect(find.text('下单成功后显示完整 Handle'), findsOneWidget);
    for (final text in ['★ 128', '31', '5', '3', '2026 年 10 月 29 日', '2025 年 3 月 12 日',
        '2018 年 11 月 3 日', '中文', 'UTC+08:00', '无', '账号资料', '交易资料']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('其余内容未公开'), findsOneWidget);
    expect(find.textContaining('可见范围'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('after a trade the name is whole and the hint is gone', (tester) async {
    await _show(tester, _payload(facts: _facts(), masked: false, name: 'Starhopper_91'));
    expect(find.text('Starhopper_91'), findsOneWidget);
    expect(find.byKey(const Key('profile-masked-name-hint')), findsNothing);
    expect(find.text('账号资料'), findsOneWidget);
  });

  testWidgets('unknown facts are left out and a ban is plain', (tester) async {
    await _show(tester, _payload(facts: {
      'completedTrades': 2,
      'lastOnlineDay': '2026-09-02',
      'language': 'en',
      'utcOffsetMinutes': -300,
      'banned': true,
      'banCount': 2,
    }));
    expect(find.text('游戏注册'), findsNothing);
    expect(find.text('交易日'), findsNothing);
    expect(find.text('SCM 信誉'), findsNothing);
    expect(find.text('英文'), findsOneWidget);
    expect(find.text('UTC-05:00'), findsOneWidget);
    expect(find.text('封禁中 · 累计 2 次'), findsOneWidget);
  });

  testWidgets('an unproved ban state is not called none', (tester) async {
    await _show(tester, _payload(facts: {'completedTrades': 1, 'banned': null, 'banCount': 0}));
    expect(find.text('封禁记录'), findsNothing);
    expect(find.text('无'), findsNothing);
  });

  testWidgets('a past ban shows its count without the warning state', (tester) async {
    await _show(tester, _payload(facts: {'completedTrades': 1, 'banned': false, 'banCount': 3}));
    expect(find.text('累计 3 次'), findsOneWidget);
    expect(find.textContaining('封禁中'), findsNothing);
  });

  testWidgets('an explicit private choice stays exactly as it was', (tester) async {
    await _show(tester, _payload(defaulted: false, masked: false, name: 'Halley_Wu', window: {
      'days': [0, 0, 0, 0, 1, 1, 1],
      'start': '20:00',
      'end': '22:00',
      'timezoneId': 77,
      'ownerOffsetMinutes': 480,
    }));
    expect(find.text('Halley_Wu'), findsOneWidget);
    expect(find.byKey(const Key('profile-public-facts')), findsNothing);
    expect(find.text('账号资料'), findsNothing);
    expect(find.textContaining('可见范围'), findsOneWidget);
  });

  testWidgets('a screen reader can tell which trade days are on', (tester) async {
    final semantics = tester.ensureSemantics();
    await _show(tester, _payload(facts: _facts(), window: {
      'days': [1, 0, 0, 0, 0, 0, 0],
      'start': '19:30',
      'end': '23:00',
      'ownerOffsetMinutes': 480,
    }));
    expect(
      tester.getSemantics(find.text('一').first),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('二').first),
      isSemantics(isSelected: false),
    );
    semantics.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    for (final width in [420.0, 700.0, 900.0, 1280.0]) {
      testWidgets('nothing overflows at $width wide, text $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _show(tester, _payload(facts: _facts(banned: true, banCount: 12), window: {
          'days': [1, 1, 0, 1, 1, 1, 1],
          'start': '19:30',
          'end': '23:00',
          'timezoneId': 77,
          'ownerOffsetMinutes': 60,
        }), width: width);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
