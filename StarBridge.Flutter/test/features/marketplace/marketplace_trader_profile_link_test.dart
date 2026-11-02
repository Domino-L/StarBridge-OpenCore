// User 10-30: a trader's avatar and name open their personal page. The Host's
// opaque reference is the only way there; no reference, no link.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/local_profile_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

const _reference = 'aaaabbbbccccddddeeeeffff00001111';
final _link = find.byKey(const ValueKey(('market-trader-profile', _reference)));

class _Port implements UserInteractionPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<PersonalProfileSnapshot> profile(UserTarget target) async =>
      PersonalProfileSnapshot.unavailable(
        failureKey: 'profile.visitor.notVisible',
      );
  @override
  Future<FriendRow?> social(UserTarget target) async => null;
  @override
  Future<FriendCommandResult> execute(String action, String reference) async =>
      const FriendCommandResult('unknown');
  @override
  Future<void> close() async {}
}

Future<List<(WidgetBuilder, String)>> _pump(
  WidgetTester tester,
  Map<String, Object?> row, {
  bool withPort = true,
}) async {
  final opened = <(WidgetBuilder, String)>[];
  final navigation = UserPageNavigation()
    ..open = (_, builder, title) async => opened.add((builder, title));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: UserInteractionScope(
        navigation: navigation,
        port: withPort ? _Port() : null,
        messagePage: null,
        child: Scaffold(body: MarketTrader(row)),
      ),
    ),
  );
  await tester.pump();
  return opened;
}

void main() {
  testWidgets('the name opens the visitor page by the opaque reference', (
    tester,
  ) async {
    final opened = await _pump(tester, {
      'seller': 'F*****e',
      'presence': 'online',
      'traderRef': _reference,
    });
    expect(_link, findsOneWidget);
    await tester.tap(find.text('F*****e'));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(opened.single.$2, 'navigation.profile');
    final page =
        opened.single.$1(tester.element(find.byType(Scaffold)))
            as UserProfilePage;
    expect(page.target.source, 'market');
    expect(page.target.reference, _reference);
    expect(page.target.contextRef, isNull);
    expect(page.target.query, isEmpty, reason: 'the name is not an identifier');
  });

  testWidgets('without a reference or a port there is no link', (tester) async {
    await _pump(tester, {'seller': 'F*****e', 'presence': 'online'});
    expect(find.byType(MarketTraderProfileLink), findsOneWidget);
    expect(_link, findsNothing);
    await _pump(tester, {
      'seller': 'F*****e',
      'presence': 'online',
      'traderRef': _reference,
    }, withPort: false);
    expect(_link, findsNothing);
    await _pump(tester, {
      'seller': 'F*****e',
      'presence': 'online',
      'traderRef': '',
    });
    expect(_link, findsNothing);
  });

  testWidgets('your own listing has no link', (tester) async {
    marketMyOrders.add('SO-mine');
    addTearDown(marketMyOrders.clear);
    await _pump(tester, {
      'seller': 'F*****e',
      'orderNumber': 'SO-mine',
      'traderRef': _reference,
    });
    expect(_link, findsNothing);
  });

  test('the rate limit has its own message in every language', () {
    for (final strings in [
      simplifiedLocalProfileStrings,
      traditionalLocalProfileStrings,
      englishLocalProfileStrings,
    ]) {
      expect(strings['profile.visitor.rateLimited'], isNotEmpty);
    }
  });
}
