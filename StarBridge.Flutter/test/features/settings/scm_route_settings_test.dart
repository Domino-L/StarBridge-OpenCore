import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/scm_route_port.dart';
import 'package:starbridge_flutter/features/settings/scm_route_settings.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_shared_friends_read.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

class _FakeRoute implements ScmRoutePort {
  _FakeRoute(this.status);
  ScmRouteStatus status;
  int reads = 0;
  final saves = <ScmRouteMode>[];
  Object? readError, saveError;

  @override
  Future<ScmRouteStatus> read() async {
    reads++;
    if (readError case final Object error) throw error;
    return status;
  }

  @override
  Future<ScmRouteStatus> save(ScmRouteMode mode) async {
    saves.add(mode);
    if (saveError case final Object error) throw error;
    return status = ScmRouteStatus(
      mode: mode,
      active: status.active,
      reason: status.reason,
      restartRequired: mode != ScmRouteMode.auto,
    );
  }
}

ScmRouteStatus _status(
  ScmRouteActive active, {
  ScmRouteMode mode = ScmRouteMode.auto,
  ScmRouteReason? reason,
  bool restart = false,
}) => ScmRouteStatus(
  mode: mode,
  active: active,
  reason: reason,
  restartRequired: restart,
);

Widget _app(Widget home, {Locale locale = const Locale('zh', 'CN')}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(body: SingleChildScrollView(child: home)),
  );
}

void main() {
  testWidgets('shows the active route and, when it fell back, why', (
    tester,
  ) async {
    final cases = <(ScmRouteStatus, String, String?)>[
      (_status(ScmRouteActive.domestic), '国内线', null),
      (_status(ScmRouteActive.overseas), '海外线', null),
      (
        _status(
          ScmRouteActive.overseas,
          reason: ScmRouteReason.domesticUnavailable,
        ),
        '海外线',
        '国内线暂时不可用，已自动换回海外线。',
      ),
      (
        _status(
          ScmRouteActive.overseas,
          reason: ScmRouteReason.domesticLoginFailed,
        ),
        '海外线',
        '上次在国内线上登录没成功，这次先用海外线。',
      ),
      (
        _status(
          ScmRouteActive.overseas,
          mode: ScmRouteMode.overseas,
          reason: ScmRouteReason.userOverseas,
        ),
        '海外线',
        '你选了一直使用海外线。',
      ),
    ];
    for (final (status, active, reason) in cases) {
      await tester.pumpWidget(
        _app(ScmRouteSettings(key: UniqueKey(), port: _FakeRoute(status))),
      );
      await tester.pumpAndSettle();
      expect(find.text('SCM 线路'), findsOneWidget);
      expect(find.text('当前线路'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('settings-scm-route-active')))
            .data,
        active,
      );
      expect(
        find.byKey(const Key('settings-scm-route-reason')),
        reason == null ? findsNothing : findsOneWidget,
      );
      if (reason != null) expect(find.text(reason), findsOneWidget);
      expect(find.byKey(const Key('settings-scm-route-restart')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'choosing overseas saves and shows the restart notice; choosing back clears it',
    (tester) async {
      final port = _FakeRoute(_status(ScmRouteActive.domestic));
      await tester.pumpWidget(_app(ScmRouteSettings(port: port)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('海外'));
      await tester.pumpAndSettle();
      expect(port.saves, [ScmRouteMode.overseas]);
      expect(find.text('改动会在重启应用后生效。'), findsOneWidget);
      // This run keeps the route it started with.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('settings-scm-route-active')))
            .data,
        '国内线',
      );
      await tester.tap(find.text('自动'));
      await tester.pumpAndSettle();
      expect(port.saves, [ScmRouteMode.overseas, ScmRouteMode.auto]);
      expect(find.byKey(const Key('settings-scm-route-restart')), findsNothing);
    },
  );

  testWidgets('a failed save keeps the old choice and says so', (tester) async {
    final port = _FakeRoute(_status(ScmRouteActive.overseas))
      ..saveError = StateError('disk');
    await tester.pumpWidget(_app(ScmRouteSettings(port: port)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('海外'));
    await tester.pumpAndSettle();
    expect(find.text('没能保存，请再试一次。'), findsOneWidget);
    expect(find.byKey(const Key('settings-scm-route-restart')), findsNothing);
  });

  testWidgets('a failed read is shown with a retry, not hidden', (
    tester,
  ) async {
    final port = _FakeRoute(_status(ScmRouteActive.overseas))
      ..readError = StateError('host');
    await tester.pumpWidget(_app(ScmRouteSettings(port: port)));
    await tester.pumpAndSettle();
    expect(find.text('SCM 线路'), findsOneWidget);
    expect(find.text('暂时读不到线路状态。'), findsOneWidget);
    port.readError = null;
    await tester.tap(find.byKey(const Key('settings-scm-route-retry')));
    await tester.pumpAndSettle();
    expect(port.reads, 2);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('settings-scm-route-active')))
          .data,
      '海外线',
    );
  });

  testWidgets('narrow width and English copy render without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        ScmRouteSettings(
          port: _FakeRoute(
            _status(
              ScmRouteActive.overseas,
              reason: ScmRouteReason.domesticLoginFailed,
            ),
          ),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SCM route'), findsOneWidget);
    expect(find.text('Overseas route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('read and save reach the Host through a real session without an account', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 3,
    );
    final seen = <BridgeEnvelope>[];
    final incoming = pair.host.incoming.listen((request) {
      seen.add(request);
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: const {
              'mode': 'auto',
              'active': 'overseas',
              'reason': null,
              'restartRequired': false,
            },
          ),
        ),
      );
    });
    addTearDown(() async {
      await incoming.cancel();
      await session.close();
      await pair.host.close();
    });
    final route = BridgeScmRoute(session);
    expect((await route.read()).active, ScmRouteActive.overseas);
    expect((await route.save(ScmRouteMode.auto)).reason, isNull);
    expect(seen.map((r) => r.name), [
      BridgeScmRoute.readRequest,
      BridgeScmRoute.saveRequest,
    ]);
    expect(seen.every((r) => r.accountContext == null), isTrue);
  });

  test('route requests stay outside account read boundaries', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 3,
    );
    final accountReads = <BridgeEnvelope>[];
    BridgeEnvelope reply(BridgeEnvelope request, Map<String, Object?> payload) =>
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: payload,
        );
    final incoming = pair.host.incoming.listen((request) {
      if (request.name == 'account.getCurrent') {
        accountReads.add(request);
        return;
      }
      unawaited(
        pair.host.send(
          reply(request, const {
            'mode': 'auto',
            'active': 'overseas',
            'reason': null,
            'restartRequired': false,
          }),
        ),
      );
    });
    addTearDown(() async {
      await incoming.cancel();
      await session.close();
      await pair.host.close();
    });
    const read = {'schemaVersion': 1};
    final first = session.request('account.getCurrent', payload: read);
    final route = BridgeScmRoute(session);
    await route.read();
    await route.save(ScmRouteMode.overseas);
    final second = session.request('account.getCurrent', payload: read);
    await Future<void>.delayed(Duration.zero);
    expect(accountReads, hasLength(1));
    await pair.host.send(reply(accountReads.single, read));
    await Future.wait([first, second]);

    final friends = SharedFriendsReads(
      (_, _, _, _) => throw UnimplementedError(),
      (_) => false,
    );
    expect(friends.boundary(BridgeScmRoute.readRequest), isFalse);
    expect(friends.boundary(BridgeScmRoute.saveRequest), isFalse);
    expect(friends.boundary('account.logout'), isTrue);
  });

  test('the rally sample reaches the Host without an account', () {
    expect(
      () => BridgeRequestPolicy.requireAccountContext(
        'notificationSettings.previewRally',
        null,
      ),
      returnsNormally,
    );
  });

  test('the Host response must be exactly the four closed fields', () {
    final good = {
      'mode': 'auto',
      'active': 'domestic',
      'reason': null,
      'restartRequired': false,
    };
    final parsed = BridgeScmRoute.parse(good);
    expect(parsed.mode, ScmRouteMode.auto);
    expect(parsed.active, ScmRouteActive.domestic);
    expect(parsed.reason, isNull);
    expect(
      BridgeScmRoute.parse({...good, 'reason': 'domesticLoginFailed'}).reason,
      ScmRouteReason.domesticLoginFailed,
    );
    for (final bad in <Map<String, Object?>>[
      {...good, 'host': 'flowcld.xyz'},
      {'mode': 'auto', 'active': 'domestic', 'restartRequired': false},
      {...good, 'mode': 'domestic'},
      {...good, 'active': 'cn'},
      {...good, 'reason': 'other'},
      {...good, 'restartRequired': 'yes'},
    ]) {
      expect(
        () => BridgeScmRoute.parse(bad),
        throwsA(isA<BridgeFormatException>()),
      );
    }
  });
}
