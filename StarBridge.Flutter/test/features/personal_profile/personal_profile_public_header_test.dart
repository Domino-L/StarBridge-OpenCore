// DEPLOY-QUEUE §4 (user-approved 2026-10-21): a visitor outside a profile's
// visibility sees the always-public header — avatar, name, trade days and
// window — and a shield instead of the rest; nothing else is invented.
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
import 'package:starbridge_flutter/features/personal_profile/personal_profile_public_header.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_trade_strip.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

Map<String, Object?> _payload({Object? window = const {}}) => {
  'schemaVersion': 1,
  'editable': false,
  'restricted': true,
  'visibility': 'friendsOnly',
  'publicHeader': {
    'callSign': 'Aster',
    'avatarAssetId': null,
    'tradeWindow': window == const {}
        ? {
            'days': [1, 1, 1, 1, 1, 0, 0],
            'start': '19:30',
            'end': '23:00',
            'timezoneId': 77,
            'ownerOffsetMinutes': 480,
          }
        : window,
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

void main() {
  test('a restricted payload becomes a header-only snapshot', () {
    final snapshot = parsePersonalProfileSnapshot(_payload());
    expect(snapshot.restricted, isTrue);
    expect(snapshot.allowEditing, isFalse);
    expect(snapshot.callSign, 'Aster');
    expect(snapshot.gameHandle, '');
    expect(snapshot.about, '');
    expect(snapshot.affiliations, isEmpty);
    expect(snapshot.affiliationStatus, 'hidden');
    expect(snapshot.moduleLayout, isEmpty);
    expect(snapshot.visibility, PersonalProfileVisibility.friendsOnly);
    expect(snapshot.publicTradeWindow!.start, '19:30');
    expect(snapshot.publicTradeWindow!.ownerOffsetMinutes, 480);
    // Never synced: no window, rather than an invented one.
    expect(
      parsePersonalProfileSnapshot(_payload(window: null)).publicTradeWindow,
      isNull,
    );
    for (final bad in [
      {
        'days': [1, 1, 1],
        'start': '19:30',
        'end': '23:00',
        'timezoneId': 77,
      },
      {
        'days': List.filled(7, 1),
        'start': '7pm',
        'end': '23:00',
        'timezoneId': 77,
      },
      {
        'days': List.filled(7, 1),
        'start': '19:30',
        'end': '23:00',
        'timezoneId': 77,
        'ownerOffsetMinutes': '480',
      },
    ]) {
      expect(
        () => parsePersonalProfileSnapshot(_payload(window: bad)),
        throwsA(isA<BridgeFormatException>()),
      );
    }
    expect(
      () => parsePersonalProfileSnapshot({..._payload(), 'editable': true}),
      throwsA(isA<BridgeFormatException>()),
    );
  });

  test('the window is shown in the viewer\'s local time', () {
    const window = PersonalProfilePublicTradeWindow(
      days: [true, true, true, true, true, false, false],
      start: '19:30',
      end: '23:00',
      ownerOffsetMinutes: 480,
    );
    // Viewer at UTC: eight hours earlier, same days.
    final utc = window.toStripData(
      localOffset: Duration.zero,
      // Monday 12:00 UTC = Monday 20:00 for the owner: open.
      now: DateTime.utc(2026, 10, 19, 12),
    );
    expect(utc.localWindow, '11:30–15:00');
    expect(utc.localDays, [true, true, true, true, true, false, false]);
    expect(utc.openNow, isTrue);
    expect(utc.ownerWindow, '19:30–23:00 · UTC+08:00');
    expect(utc.contact, isNull);
    expect(utc.reputation, isNull);
    // Viewer at UTC-8: sixteen hours earlier, still the same day.
    final pacific = window.toStripData(
      localOffset: const Duration(hours: -8),
      now: DateTime.utc(2026, 10, 19, 2),
    );
    expect(pacific.localWindow, '03:30–07:00');
    expect(pacific.localDays, [true, true, true, true, true, false, false]);
    // An early-morning window moves to the previous day for that viewer.
    const early = PersonalProfilePublicTradeWindow(
      days: [true, false, false, false, false, false, false],
      start: '07:00',
      end: '09:00',
      ownerOffsetMinutes: 480,
    );
    final moved = early.toStripData(localOffset: const Duration(hours: -8));
    expect(moved.localWindow, '15:00–17:00');
    expect(moved.localDays, [false, false, false, false, false, false, true]);
    expect(pacific.openNow, isFalse);
    // Same zone as the owner: nothing moves and no "owner setting" note.
    final same = window.toStripData(
      localOffset: const Duration(hours: 8),
      now: DateTime.utc(2026, 10, 19, 2),
    );
    expect(same.localWindow, '19:30–23:00');
    expect(same.ownerWindow, isNull);
    // Unknown owner zone: the owner's own setting, no open/closed claim.
    const unknown = PersonalProfilePublicTradeWindow(
      days: [true, false, false, false, false, false, false],
      start: '19:30',
      end: '23:00',
    );
    expect(unknown.toStripData().localWindow, '19:30–23:00');
    expect(unknown.toStripData().openNow, isNull);
  });

  testWidgets('a restricted visitor page shows the public header only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = createPersonalProfileModule(
      _Port(parsePersonalProfileSnapshot(_payload())),
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
    expect(find.byKey(const Key('profile-identity-header')), findsOneWidget);
    expect(find.text('Aster'), findsWidgets);
    expect(find.textContaining('@'), findsNothing);
    final strip = tester.widget<ProfileTradeStrip>(
      find.byType(ProfileTradeStrip),
    );
    expect(strip.isSelf, isFalse);
    expect(strip.data, isNotNull);
    expect(strip.data!.contact, isNull);
    expect(find.byKey(const Key('profile-trade-edit')), findsNothing);
    expect(
      find.byKey(const Key('profile-private-visitor-view')),
      findsOneWidget,
    );
    expect(find.text('其余内容未公开'), findsOneWidget);
    expect(find.textContaining('仅好友可见'), findsWidgets);
    // The organization column stays and says it is not public (2026-10-28).
    expect(find.text('不公开'), findsOneWidget);
    // No owner tools, no module grid.
    expect(find.byKey(const Key('profile-edit')), findsNothing);
    expect(find.byKey(const Key('profile-preview')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a never-saved profile: name and avatar, no trade strip claim', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The service answers for an owner who never saved a page: SCM name,
    // RSI avatar, default private visibility and no synced window.
    final payload = {..._payload(window: null), 'visibility': 'private'};
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
    expect(find.text('Aster'), findsWidgets);
    // A missing window may only mean "never synced": no strip, no claim.
    expect(find.byType(ProfileTradeStrip), findsNothing);
    expect(find.byKey(const Key('profile-trade-missing')), findsNothing);
    expect(find.text('其余内容未公开'), findsOneWidget);
    expect(find.textContaining('仅自己可见'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
