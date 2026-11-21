import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/common/bridge_user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_public_facts.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_public_header.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_trade_strip.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_side_rail.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _facts = PersonalProfilePublicFacts(
  reputation: 128,
  completedTrades: 31,
  sellOrders: 5,
  buyOrders: 3,
  lastOnlineDay: '2026-11-08',
  siteRegisteredDay: '2025-03-12',
  gameRegisteredDay: '2018-11-03',
  language: 'zh',
  utcOffsetMinutes: 480,
  banned: false,
  banCount: 0,
);

class _Port implements PersonalProfilePort, PersonalProfileAccountFactsReader {
  final base = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  final changes = StreamController<void>.broadcast(sync: true);
  PersonalProfilePublicFacts? facts = _facts;
  PersonalProfileSnapshot? snapshot;
  Future<PersonalProfilePublicFacts?> Function()? pending;
  int factsReads = 0;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<PersonalProfileSnapshot> read() async => snapshot ?? await base.read();
  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) =>
      base.save(edit);
  @override
  Future<void> close() async {
    await changes.close();
    await base.close();
  }

  @override
  Future<PersonalProfilePublicFacts?> readAccountFacts() async {
    factsReads++;
    return pending == null ? facts : await pending!();
  }
}

class _Wire {
  _Wire({bool supported = true, bool visitorSupported = true}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    session.acceptHostCapabilities({
      if (supported) 'personalProfile.accountFacts.read.v1',
      if (visitorSupported) 'personalProfile.visitorAccountFacts.v1',
      'users.interaction',
      'communities.memberPersonalProfile',
    });
    adapter = BridgePersonalProfileAdapter(session);
    subscription = pair.host.incoming.listen((request) {
      names.add(request.name);
      if (request.name == 'personalProfile.readAccountFacts') {
        expect(request.payload, {'schemaVersion': 1});
        expect(request.accountContext?.toJson(), owner.toJson());
      }
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 7,
            accountContext: owner,
            payload: request.name == 'account.getCurrent'
                ? {'schemaVersion': 1, 'state': 'signedIn'}
                : payload,
            status: 'ok',
          ),
        ),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  static const owner = BridgeAccountContext(
    environment: 'synthetic',
    authority: 'synthetic',
    subject: 'owner',
  );
  late final BridgeClientSession session;
  late final BridgePersonalProfileAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final names = <String>[];
  Map<String, Object?> payload = {
    'schemaVersion': 1,
    'facts': {'language': 'zh', 'reputation': 128},
  };
  Future<void> close() async {
    await adapter.close();
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  }
}

Future<PersonalProfileModule> _show(
  WidgetTester tester,
  _Port port, {
  bool visitor = false,
  bool trade = false,
  Widget? content,
}) async {
  tester.view.physicalSize = const Size(1440, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final module = createPersonalProfileModule(port);
  addTearDown(module.dispose);
  await module.initialize();
  const locale = Locale('zh', 'CN');
  Widget page =
      content ?? PersonalProfilePage(module: module, isVisitor: visitor);
  if (trade) {
    page = ProfileTradeStripScope(
      builder: (_, view) => Builder(
        builder: (context) => Column(
          children: [
            ProfileTradeStrip(
              data: const ProfileTradeStripData(
                localDays: [true, true, true, true, true, false, false],
                localWindow: '19:30–23:00',
                reputation: '★ 999',
              ),
              isSelf: view == ProfileTradeStripView.owner,
            ),
            ProfileOwnerTradeFactsScope.supplement(
              context,
              hasReputation: true,
            ),
          ],
        ),
      ),
      child: page,
    );
  }
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
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
  return module;
}

void main() {
  for (final supported in [false, true]) {
    test('community visitor adapter gates account facts: $supported', () async {
      final wire = _Wire(visitorSupported: supported)
        ..payload = _visitorPayload();
      addTearDown(wire.close);
      final port = BridgeCommunities(wire.session);
      addTearDown(port.close);
      final page = await port.readMemberPersonalProfile(
        'synthetic-community',
        'synthetic-member',
      );
      expect(page.availability, PersonalProfileAvailability.available);
      expect(page.accountFacts?.language, supported ? 'zh' : null);
      expect(page.publicFacts, isNull);
    });
    test(
      'visitor adapter gates facts on Host capability: $supported',
      () async {
        final wire = _Wire(visitorSupported: supported)
          ..payload = _visitorPayload();
        addTearDown(wire.close);
        final port = BridgeUserInteraction(wire.session);
        addTearDown(port.close);
        final page = await port.profile(
          const UserTarget('friend', 'synthetic-ref'),
        );
        expect(page.availability, PersonalProfileAvailability.available);
        expect(page.accountFacts?.language, supported ? 'zh' : null);
        expect(page.publicFacts, isNull);
        expect(wire.names, ['account.getCurrent', 'users.profile']);
      },
    );
  }
  for (final bad in <Object?>[
    null,
    [],
    'bad',
    {'language': 7},
    {'lastOnlineDay': '2026-02-31'},
    {'lastOnlineVisible': true},
  ]) {
    test('malformed visitor facts leave full page intact: $bad', () {
      final snapshot = parsePersonalProfileSnapshot(
        _visitorPayload()..['accountFacts'] = bad,
        visitorAccountFactsSupported: true,
      );
      expect(snapshot.availability, PersonalProfileAvailability.available);
      expect(snapshot.callSign, 'Visitor');
      expect(snapshot.accountFacts, isNull);
    });
  }
  testWidgets('full authorized visitor shows account and trade facts once', (
    tester,
  ) async {
    final port = _Port()
      ..snapshot = parsePersonalProfileSnapshot(
        _visitorPayload(),
        visitorAccountFactsSupported: true,
      );
    await _show(tester, port, visitor: true);
    expect(port.factsReads, 0);
    expect(
      find.byKey(const Key('profile-visitor-account-facts')),
      findsOneWidget,
    );
    for (final text in [
      '账号资料',
      '最后上线',
      'SCM 注册',
      '游戏注册',
      '语言',
      '时区',
      '封禁记录',
      '出售订单',
      '求购订单',
      '已成交',
      '★ 128',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.byKey(const Key('profile-rail-status')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('owner and visitors share one trade-then-account band', (
    tester,
  ) async {
    void expectOneBand(String accountKey) {
      final band = find.byKey(const Key('profile-rail-trade'));
      expect(
        find.descendant(of: band, matching: find.byKey(Key(accountKey))),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('交易资料')).dy,
        lessThan(tester.getTopLeft(find.text('账号资料')).dy),
      );
    }

    await _show(tester, _Port(), trade: true);
    expectOneBand('profile-owner-account-facts');
    await tester.pumpWidget(const SizedBox());
    final snapshot = parsePersonalProfileSnapshot(
      _visitorPayload(),
      visitorAccountFactsSupported: true,
    );
    await _show(tester, _Port()..snapshot = snapshot, visitor: true);
    expectOneBand('profile-visitor-account-facts');
    await tester.pumpWidget(const SizedBox());
    await _show(
      tester,
      _Port()
        ..snapshot = parsePersonalProfileSnapshot({
          'schemaVersion': 1,
          'editable': false,
          'restricted': true,
          'visibility': 'private',
          'publicHeader': {
            'callSign': 'Visitor',
            'defaulted': true,
            'facts': _visitorFacts,
          },
        }, visitorAccountFactsSupported: true),
      visitor: true,
    );
    final band = find.byKey(const Key('profile-rail-trade'));
    expect(
      find.descendant(
        of: band,
        matching: find.byKey(const Key('profile-public-facts')),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('交易资料')).dy,
      lessThan(tester.getTopLeft(find.text('账号资料')).dy),
    );
  });
  testWidgets('old Host full visitor has no optional account block', (
    tester,
  ) async {
    final port = _Port()
      ..snapshot = parsePersonalProfileSnapshot(_visitorPayload());
    await _show(tester, port, visitor: true);
    expect(find.text('账号资料'), findsNothing);
    expect(find.text('出售订单'), findsNothing);
  });
  testWidgets('full visitor keeps an existing trade reputation', (
    tester,
  ) async {
    final snapshot = parsePersonalProfileSnapshot(
      _visitorPayload(),
      visitorAccountFactsSupported: true,
    );
    await _show(
      tester,
      _Port(),
      content: PersonalProfileSideRail(
        projection: PersonalProfileProjection.fromSnapshot(snapshot),
        isSelf: false,
        trade: const ProfileTradeStrip(
          data: ProfileTradeStripData(
            localDays: [true, true, true, true, true, false, false],
            localWindow: '19:30–23:00',
            reputation: '★ 999',
          ),
          isSelf: false,
        ),
      ),
    );
    expect(find.text('★ 999'), findsOneWidget);
    expect(find.text('★ 128'), findsNothing);
    expect(find.text('出售订单'), findsOneWidget);
    expect(find.text('已成交'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final defaulted in [false, true]) {
    testWidgets('restricted ignores top-level facts; defaulted=$defaulted', (
      tester,
    ) async {
      final snapshot = parsePersonalProfileSnapshot({
        'schemaVersion': 1,
        'editable': false,
        'restricted': true,
        'visibility': 'private',
        'accountFacts': _visitorFacts,
        'publicHeader': {
          'callSign': 'Visitor',
          'defaulted': defaulted,
          if (defaulted) 'facts': {'language': 'en'},
        },
      }, visitorAccountFactsSupported: true);
      expect(snapshot.accountFacts, isNull);
      expect(snapshot.publicFacts?.language, defaulted ? 'en' : null);
      await _show(tester, _Port()..snapshot = snapshot, visitor: true);
      expect(find.text('账号资料'), defaulted ? findsOneWidget : findsNothing);
      expect(find.text('中文'), findsNothing);
      expect(find.text('英文'), defaulted ? findsOneWidget : findsNothing);
      expect(find.text('出售订单'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  test('old Host returns null without sending any request', () async {
    final wire = _Wire(supported: false);
    addTearDown(wire.close);
    expect(await wire.adapter.readAccountFacts(), isNull);
    expect(wire.names, isEmpty);
  });
  test('owner bridge response reuses facts parser', () async {
    final wire = _Wire();
    addTearDown(wire.close);
    final facts = await wire.adapter.readAccountFacts();
    expect(facts?.language, 'zh');
    expect(facts?.reputation, 128);
    expect(wire.names, [
      'account.getCurrent',
      'personalProfile.readAccountFacts',
    ]);
  });
  for (final payload in <Map<String, Object?>>[
    {'schemaVersion': 1, 'facts': null},
    {'schemaVersion': 2, 'facts': {}},
    {'schemaVersion': 1.0, 'facts': {}},
    {'schemaVersion': 1},
    {'schemaVersion': 1, 'facts': []},
    {'schemaVersion': 1, 'facts': {}, 'extra': true},
    {
      'schemaVersion': 1,
      'facts': {'language': 'unknown'},
    },
    {
      'schemaVersion': 1,
      'facts': {'timezoneId': 77},
    },
    {
      'schemaVersion': 1,
      'facts': {'lastOnlineVisible': false},
    },
    {
      'schemaVersion': 1,
      'facts': {'lastOnlineDay': '2026-02-31'},
    },
  ]) {
    test('null or malformed facts do not fail page port: $payload', () async {
      final wire = _Wire()..payload = payload;
      addTearDown(wire.close);
      expect(await wire.adapter.readAccountFacts(), isNull);
    });
  }
  testWidgets('owner rail shows account facts and trade counts once', (
    tester,
  ) async {
    final port = _Port();
    await _show(tester, port);
    expect(
      find.byKey(const Key('profile-owner-account-facts')),
      findsOneWidget,
    );
    for (final text in [
      '账号资料',
      '最后上线',
      'SCM 注册',
      '游戏注册',
      '语言',
      '时区',
      '封禁记录',
      '出售订单',
      '求购订单',
      '已成交',
      '★ 128',
      '31',
      '5',
      '3',
    ]) {
      expect(
        find.descendant(
          of: find.byKey(
            Key(
              ['31', '5', '3'].contains(text)
                  ? 'profile-rail-trade'
                  : 'profile-side-rail',
            ),
          ),
          matching: find.text(text),
        ),
        findsOneWidget,
        reason: text,
      );
    }
    expect(port.factsReads, 1);
    await tester.pump(const Duration(minutes: 3));
    expect(port.factsReads, 1);
    await tester.ensureVisible(find.byKey(const Key('profile-refresh')));
    await tester.tap(find.byKey(const Key('profile-refresh')));
    await tester.pumpAndSettle();
    expect(port.factsReads, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('visitor does not read or show owner facts', (tester) async {
    final port = _Port();
    await _show(tester, port, visitor: true);
    expect(port.factsReads, 0);
    expect(find.byKey(const Key('profile-owner-account-facts')), findsNothing);
    expect(find.text('账号资料'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('full visitor preview reuses owner account and trade facts', (
    tester,
  ) async {
    final port = _Port();
    await _show(tester, port);
    await tester.ensureVisible(find.byKey(const Key('profile-preview')));
    await tester.tap(find.byKey(const Key('profile-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-owner-account-facts')), findsNothing);
    expect(
      find.byKey(const Key('profile-visitor-account-facts')),
      findsOneWidget,
    );
    expect(find.text('账号资料'), findsOneWidget);
    expect(find.text('出售订单'), findsOneWidget);
    expect(port.factsReads, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('null facts hide optional blocks without error', (tester) async {
    await _show(tester, _Port()..facts = null);
    expect(find.byKey(const Key('profile-owner-account-facts')), findsNothing);
    expect(find.text('账号资料'), findsNothing);
    expect(find.text('出售订单'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final defaulted in [false, true]) {
    testWidgets(
      'restricted owner preview follows visibility: defaulted=$defaulted',
      (tester) async {
        final payload = _visitorPayload()..['editable'] = true;
        final profile = payload['profile']! as Map<String, Object?>;
        profile['visibility'] = 'private';
        profile['revision'] = defaulted ? 0 : 7;
        profile['updatedAt'] = defaulted
            ? '1970-01-01T00:00:00Z'
            : '2026-11-08T00:00:00Z';
        (profile['identity']! as Map<String, Object?>)['gameHandle'] =
            'Synthetic';
        final port = _Port()..snapshot = parsePersonalProfileSnapshot(payload);
        await _show(tester, port);
        expect(find.text('账号资料'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('profile-preview')));
        await tester.tap(find.byKey(const Key('profile-preview')));
        await tester.pumpAndSettle();
        expect(find.text('账号资料'), defaulted ? findsOneWidget : findsNothing);
        expect(find.text('出售订单'), defaulted ? findsOneWidget : findsNothing);
        expect(port.factsReads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'visitor preview preserves trade reputation without duplication',
    (tester) async {
      await _show(tester, _Port(), trade: true);
      await tester.ensureVisible(find.byKey(const Key('profile-preview')));
      await tester.tap(find.byKey(const Key('profile-preview')));
      await tester.pumpAndSettle();
      expect(find.textContaining('★ 999'), findsOneWidget);
      expect(find.text('★ 128'), findsNothing);
      expect(find.text('出售订单'), findsOneWidget);
      expect(find.text('已成交'), findsOneWidget);
    },
  );
  testWidgets('unknown fields and empty account section stay hidden', (
    tester,
  ) async {
    await _show(
      tester,
      _Port()..facts = const PersonalProfilePublicFacts(sellOrders: 0),
    );
    expect(find.byKey(const Key('profile-owner-account-facts')), findsNothing);
    for (final text in [
      '最后上线',
      'SCM 注册',
      '游戏注册',
      '语言',
      '时区',
      '封禁记录',
      '求购订单',
      '已成交',
    ]) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expect(find.text('出售订单'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('existing trade reputation wins over facts reputation', (
    tester,
  ) async {
    await _show(tester, _Port(), trade: true);
    expect(find.textContaining('★ 999'), findsOneWidget);
    expect(find.text('★ 128'), findsNothing);
    expect(find.text('出售订单'), findsOneWidget);
    expect(find.text('已成交'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account invalidation drops old values and late response', (
    tester,
  ) async {
    final port = _Port();
    final old = Completer<PersonalProfilePublicFacts?>();
    port.pending = () => old.future;
    await _show(tester, port);
    expect(port.factsReads, 1);
    port.pending = null;
    port.facts = const PersonalProfilePublicFacts(language: 'en');
    port.changes.add(null);
    await tester.pumpAndSettle();
    expect(port.factsReads, 2);
    expect(find.text('英文'), findsOneWidget);
    old.complete(_facts);
    await tester.pumpAndSettle();
    expect(find.text('中文'), findsNothing);
    expect(find.text('出售订单'), findsNothing);
    expect(find.text('英文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _visitorFacts = <String, Object?>{
  'reputation': 128,
  'completedTrades': 31,
  'sellOrders': 5,
  'buyOrders': 3,
  'lastOnlineDay': '2026-11-08',
  'siteRegisteredDay': '2025-03-12',
  'gameRegisteredDay': '2018-11-03',
  'language': 'zh',
  'utcOffsetMinutes': 480,
  'banned': false,
  'banCount': 0,
};
Map<String, Object?> _visitorPayload() => {
  'schemaVersion': 1,
  'editable': false,
  'accountFacts': _visitorFacts,
  'profile': {
    'isPublic': false,
    'visibility': 'friendsOnly',
    'revision': 7,
    'identity': {'callSign': 'Visitor', 'gameHandle': ''},
    'content': {'modules': <Object?>[]},
  },
};
