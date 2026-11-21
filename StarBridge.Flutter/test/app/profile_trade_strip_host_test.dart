import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/profile_trade_strip_host.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_trade_strip.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_public_facts.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_public_header.dart';

import '../features/marketplace/marketplace_slice4_test.dart' show preview;
import '../features/marketplace/marketplace_trade_profile_test.dart'
    show ProfilePort;

MarketRow _profile({List<int> days = const [1, 1, 1, 1, 1, 0, 0]}) => {
  'tradeTime': days,
  'tradeStartTime': '19:30',
  'tradeEndTime': '23:00',
  'timezoneId': 77,
  'userMobile': 'Discord aster#0420',
  'point': 128,
  'completedTransactionCount': 31,
};

class _FailingProfilePort extends ProfilePort {
  @override
  Future<MarketRow> tradeProfile([MarketRow? changes]) async =>
      throw const MarketplaceTradeError('trade_profile.rejected');
}

class _SummaryProfilePort extends ProfilePort {
  _SummaryProfilePort(this.summary);
  final bool summary;
  @override
  Future<MarketRow> tradeProfile([MarketRow? changes]) async => {
    ..._profile(),
    if (!summary) 'point': null,
  };
}

void main() {
  for (final summary in [false, true]) {
    testWidgets(
      // With account facts the strip keeps only days and window and the
      // numbers come from the facts, as on every visitor page (user 11-08).
      'account facts replace the hall summary in the strip: $summary',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = MarketplaceController(_SummaryProfilePort(summary));
        addTearDown(c.dispose);
        Widget page(ProfileTradeStripView view) => preview(
          ProfileOwnerTradeFactsScope(
            facts: const PersonalProfilePublicFacts(
              reputation: 999,
              completedTrades: 80,
              sellOrders: 5,
              buyOrders: 3,
            ),
            child: ProfileTradeStripHost(c, view: view),
          ),
          AppearanceMode.dark,
        );
        await tester.pumpWidget(page(ProfileTradeStripView.visitor));
        await tester.pumpAndSettle();
        expect(find.textContaining('★ 999'), findsOneWidget);
        expect(find.textContaining('★ 128'), findsNothing);
        expect(find.text('80'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        await tester.pumpWidget(page(ProfileTradeStripView.restrictedVisitor));
        await tester.pumpAndSettle();
        expect(find.textContaining('★'), findsNothing);
        expect(find.text('80'), findsNothing);
        expect(find.text('5'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('trade profile maps to the strip in local time', (tester) async {
    final local = DateTime.now().timeZoneOffset.inMinutes;
    final c = MarketplaceController(ProfilePort());
    addTearDown(c.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      preview(
        Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    // Same zone as the viewer: nothing moves.
    marketZoneOffsets[77] = local;
    var data = profileTradeStripData(context, c, _profile())!;
    expect(data.localDays, [true, true, true, true, true, false, false]);
    expect(data.localWindow, '19:30–23:00');
    // Only the channel, never the account itself.
    expect(data.contact, 'Discord');
    for (final (raw, channel) in [
      ('QQ 123456789', 'QQ'),
      ('123456789', 'QQ'),
      ('微信 aster_lin', '微信'),
      ('wx: aster', '微信'),
      ('13800138000', '手机'),
      ('kook 开黑啦 1234', 'KOOK'),
      ('aster@example.com', '邮箱'),
      ('游戏内私信 Aster-Lin', '已填写'),
    ]) {
      expect(profileContactChannel(context, raw), channel, reason: raw);
    }
    expect(profileContactChannel(context, '  '), isNull);
    expect(data.reputation, startsWith('★ 128'));
    // Owner one hour ahead of the viewer: the window moves an hour earlier.
    marketZoneOffsets[77] = local + 60;
    data = profileTradeStripData(context, c, _profile())!;
    expect(data.localWindow, '18:30–22:00');
    // No trade day selected: the owner is asked to set it up.
    expect(
      profileTradeStripData(context, c, _profile(days: List.filled(7, 0))),
      isNull,
    );
    marketZoneOffsets.remove(77);
  });

  testWidgets('host shows the owner strip once read, nothing while unknown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MarketplaceController(ProfilePort());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      preview(ProfileTradeStripHost(c), AppearanceMode.dark),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProfileTradeStrip), findsOneWidget);
    expect(find.byKey(const Key('profile-trade-edit')), findsOneWidget);

    final failing = MarketplaceController(_FailingProfilePort());
    addTearDown(failing.dispose);
    await tester.pumpWidget(
      preview(ProfileTradeStripHost(failing), AppearanceMode.dark),
    );
    await tester.pumpAndSettle();
    // A failed read never claims "not set up".
    expect(find.byType(ProfileTradeStrip), findsNothing);
    expect(find.byKey(const Key('profile-trade-missing')), findsNothing);
  });

  testWidgets('visitor views: restricted visitors see only days and window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MarketplaceController(ProfilePort());
    addTearDown(c.dispose);
    ProfileTradeStrip strip() =>
        tester.widget<ProfileTradeStrip>(find.byType(ProfileTradeStrip));

    await tester.pumpWidget(
      preview(
        ProfileTradeStripHost(c, view: ProfileTradeStripView.visitor),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    // Within the visibility: contact channel and reputation follow it.
    expect(strip().isSelf, isFalse);
    expect(find.byKey(const Key('profile-trade-edit')), findsNothing);
    final full = strip().data;
    if (full != null) {
      expect(full.localDays, isNotEmpty);
    }

    await tester.pumpWidget(
      preview(
        ProfileTradeStripHost(c, view: ProfileTradeStripView.restrictedVisitor),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    // Outside it: the always-public days and window, nothing else.
    expect(strip().isSelf, isFalse);
    expect(find.byKey(const Key('profile-trade-edit')), findsNothing);
    final restricted = strip().data;
    if (restricted != null) {
      expect(restricted.localDays, full!.localDays);
      expect(restricted.localWindow, full.localWindow);
      expect(restricted.contact, isNull);
      expect(restricted.reputation, isNull);
    }
  });
}
