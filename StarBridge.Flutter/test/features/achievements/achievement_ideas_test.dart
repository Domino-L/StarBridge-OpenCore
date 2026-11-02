import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/achievements/achievement_idea_form.dart';
import 'package:starbridge_flutter/features/achievements/achievement_ideas_port.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_ideas.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount;

class _Ideas implements AchievementIdeasPort {
  @override
  bool get available => true;
  @override
  bool get canPickImage => true;
  int calls = 0;
  String? name, condition, image, id;
  Completer<void>? pending;
  Completer<String?>? pendingImage;
  bool fail = false;
  @override
  Future<String?> pickImage({required int generation}) async {
    if (pendingImage != null) return pendingImage!.future;
    return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  }

  @override
  Future<void> submit({
    required int generation,
    required String submissionId,
    required String name,
    required String condition,
    String? imageData,
  }) async {
    calls++;
    this.name = name;
    this.condition = condition;
    image = imageData;
    id = submissionId;
    if (pending != null) await pending!.future;
    if (fail) throw const AchievementIdeaFailure('unconfirmed');
  }
}

Widget _app(
  ValueNotifier<AccountProjection> account,
  AchievementIdeasPort ideas, {
  Locale locale = const Locale('zh', 'CN'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (_, child) => MediaQuery(
    data: MediaQueryData(
      size: const Size(960, 720),
      disableAnimations: true,
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: AchievementsPage(account: account, ideas: ideas),
  ),
);
Future<void> _open(
  WidgetTester tester,
  _Ideas ideas, {
  ValueNotifier<AccountProjection>? account,
  Locale locale = const Locale('zh', 'CN'),
  double scale = 1,
}) async {
  final owner = account ?? ValueNotifier(achievementTestAccount(1));
  if (account == null) addTearDown(owner.dispose);
  await tester.pumpWidget(_app(owner, ideas, locale: locale, scale: scale));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('achievement-contribute')));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('achievement-idea-name')),
    '  归舟新章  ',
  );
  await tester.enterText(
    find.byKey(const Key('achievement-idea-condition')),
    '  拥有一艘飞船\n曾拥有即可。  ',
  );
  await tester.ensureVisible(find.byKey(const Key('achievement-idea-submit')));
}

void main() {
  testWidgets('selecting an image never claims to submit or sends an idea', (
    tester,
  ) async {
    final ideas = _Ideas()..pendingImage = Completer<String?>();
    await _open(tester, ideas);
    await tester.tap(find.byKey(const Key('achievement-idea-image')));
    await tester.pump();
    expect(find.text('正在选择图片…'), findsOneWidget);
    expect(find.text('正在提交…'), findsNothing);
    expect(ideas.calls, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('achievement-idea-submit')),
          )
          .onPressed,
      isNull,
    );
    ideas.pendingImage!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('添加图片'), findsOneWidget);
    expect(find.byKey(const Key('achievement-idea-status')), findsNothing);
    expect(ideas.calls, 0);
  });
  testWidgets('entry validates fields and sends one trimmed idea while busy', (
    tester,
  ) async {
    final ideas = _Ideas()..pending = Completer<void>();
    await _open(tester, ideas);
    await tester.tap(find.byKey(const Key('achievement-idea-submit')));
    await tester.pumpAndSettle();
    expect(ideas.calls, 0);
    expect(find.text('请为成就取一个名字。'), findsOneWidget);
    await fill(tester);
    await tester.tap(find.byKey(const Key('achievement-idea-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('achievement-idea-submit')));
    expect(ideas.calls, 1);
    expect(ideas.name, '归舟新章');
    expect(ideas.condition, '拥有一艘飞船\n曾拥有即可。');
    expect(ideas.image, isNull);
    expect(ideas.id, matches(RegExp(r'^[a-f0-9]{32}$')));
    ideas.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('感谢你的想法，已提交给星海舰桥。'), findsOneWidget);
    expect(find.byKey(const Key('achievement-idea-submit')), findsNothing);
  });
  testWidgets('failed send retains draft and receipt; close confirms discard', (
    tester,
  ) async {
    final ideas = _Ideas()..fail = true;
    await _open(tester, ideas);
    await fill(tester);
    await tester.tap(find.byKey(const Key('achievement-idea-submit')));
    await tester.pumpAndSettle();
    final id = ideas.id;
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('achievement-idea-name')))
          .controller!
          .text,
      '  归舟新章  ',
    );
    await tester.tap(find.byKey(const Key('achievement-idea-submit')));
    await tester.pumpAndSettle();
    expect(ideas.id, id);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃这次填写？'), findsOneWidget);
    await tester.tap(find.text('继续填写'));
    await tester.pumpAndSettle();
    expect(find.byType(AchievementIdeaForm), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃填写'));
    await tester.pumpAndSettle();
    expect(find.byType(AchievementIdeaForm), findsNothing);
  });
  testWidgets('optional image can be previewed and removed before submitting', (
    tester,
  ) async {
    final ideas = _Ideas();
    await _open(tester, ideas);
    await tester.tap(find.byKey(const Key('achievement-idea-image')));
    await tester.pumpAndSettle();
    expect(find.text('移除图片'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tester.ensureVisible(find.text('移除图片'));
    await tester.tap(find.text('移除图片'));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.tap(find.byKey(const Key('achievement-idea-submit')));
    await tester.pumpAndSettle();
    expect(ideas.image, isNull);
  });
  testWidgets('account switch dismisses draft and ignores late submission', (
    tester,
  ) async {
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    final ideas = _Ideas()..pending = Completer<void>();
    await _open(tester, ideas, account: account);
    await fill(tester);
    await tester.tap(find.byKey(const Key('achievement-idea-submit')));
    await tester.pump();
    account.value = achievementTestAccount(2);
    await tester.pumpAndSettle();
    expect(find.byType(AchievementIdeaForm), findsNothing);
    ideas.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('感谢你的想法，已提交给星海舰桥。'), findsNothing);
  });
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
  ]) {
    testWidgets('narrow large text form fits ${locale.toLanguageTag()}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _open(tester, _Ideas(), locale: locale, scale: 1.6);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const Key('achievement-idea-submit')),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  test('bridge submission pins owner, sends no editable identity and never replays', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities([
      'account.achievementIdeaSubmit',
      'achievementIdeas.images',
    ]);
    var wrongOwner = false, fail = false, calls = 0;
    var failureCode = 'ideas.unconfirmed';
    final owner = const BridgeAccountContext(
      environment: 'test',
      authority: 'scm',
      subject: 'synthetic',
    );
    final subscription = pair.host.incoming.listen((request) {
      if (request.name == 'bridge.cancel') return;
      if (request.name != 'account.getCurrent') {
        calls++;
        expect(request.accountContext!.subject, 'synthetic');
        expect(
          request.payload.keys,
          unorderedEquals([
            'schemaVersion',
            'submissionId',
            'name',
            'condition',
            'imageData',
          ]),
        );
      }
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 1,
            accountContext: wrongOwner && request.name != 'account.getCurrent'
                ? const BridgeAccountContext(
                    environment: 'test',
                    authority: 'scm',
                    subject: 'other',
                  )
                : owner,
            status: fail && request.name != 'account.getCurrent'
                ? 'error'
                : 'ok',
            error: fail && request.name != 'account.getCurrent'
                ? BridgeErrorBody(
                    code: failureCode,
                    message: 'synthetic',
                    retryable: true,
                  )
                : null,
            payload: request.name == 'account.getCurrent'
                ? {'schemaVersion': 1, 'state': 'signedIn'}
                : {'schemaVersion': 1, 'sent': true},
          ),
        ),
      );
    });
    addTearDown(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
    final port = BridgeAchievementIdeas(session);
    Future<void> send() => port.submit(
      generation: 1,
      submissionId: 'a' * 32,
      name: 'idea',
      condition: 'condition',
    );
    await send();
    expect(calls, 1);
    wrongOwner = true;
    await expectLater(send(), throwsA(isA<Object>()));
    expect(calls, 2);
    wrongOwner = false;
    fail = true;
    await expectLater(send(), throwsA(isA<AchievementIdeaFailure>()));
    expect(calls, 3);
    failureCode = 'ideas.busy';
    await expectLater(
      send(),
      throwsA(
        isA<AchievementIdeaFailure>().having((e) => e.code, 'code', 'busy'),
      ),
    );
    expect(calls, 4);
    failureCode = 'ideas.rate_limited';
    await expectLater(
      send(),
      throwsA(
        isA<AchievementIdeaFailure>().having(
          (e) => e.code,
          'code',
          'rateLimited',
        ),
      ),
    );
    expect(calls, 5);
  });
}
