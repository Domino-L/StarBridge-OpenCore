import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/achievements/swift_leaderboard.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/swift_leaderboard_page.dart';

import 'restricted_samples.dart';

const _at = '2026-11-03T12:00:00Z';
Map<String, Object?> _consent(String state) => {
  'schemaVersion': 1,
  'state': state,
  'optedIn': state == 'opted-in',
  'decidedAt': state == 'undecided' ? null : _at,
};
Map<String, Object?> _board({
  bool empty = false,
  bool opted = false,
  int? rank,
}) => {
  'schemaVersion': 1,
  'computedAt': _at,
  'entries': empty
      ? <Object?>[]
      : [
          {
            'rank': 1,
            'handle': 'Verified-Pilot',
            'bestMs': 500000,
            'achievedOn': '2026-11-03',
          },
        ],
  'me': {'rank': rank, 'bestMs': 3600000, 'optedIn': opted},
};

class _Port implements SwiftLeaderboardPort {
  String state = 'undecided';
  bool supported = true, empty = false, earned = false, failWrite = false;
  int reads = 0;
  bool failRead = false, failConsentRead = false;
  Completer<Map<String, Object?>>? boardHeld;
  final writes = <bool>[];
  Completer<Map<String, Object?>>? held;
  @override
  Future<Map<String, Object?>> call(String action, {bool? optIn}) async {
    if (action == 'earned') {
      return {
        'earnedAt': {if (earned) 'contract-tsg-swift': _at},
      };
    }
    if (!supported) return {'schemaVersion': 1, 'supported': false};
    if (action == 'consent.read' && failConsentRead) {
      throw StateError('synthetic consent read failure');
    }
    if (action == 'consent.write') {
      writes.add(optIn!);
      if (failWrite) throw StateError('synthetic write failure');
      state = optIn ? 'opted-in' : 'withdrawn';
    }
    if (action == 'read') {
      reads++;
      if (failRead) throw StateError('synthetic read failure');
      if (boardHeld != null) return boardHeld!.future;
      return {
        'supported': true,
        'board': _board(
          empty: empty,
          opted: state == 'opted-in',
          rank: state == 'opted-in' && !empty ? 1 : null,
        ),
      };
    }
    if (held != null) return held!.future;
    return {'supported': true, 'consent': _consent(state)};
  }
}

Widget _app(
  Widget child, {
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
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);
void main() {
  const boardTest = 'shared byte fixture validates all board states';
  final boardSample = restrictedAchievementSample('leaderboard-response.json');
  final consentSample = restrictedAchievementSample('leaderboard-consent.json');
  test(
    boardTest,
    () {
      final boards = jsonDecode(boardSample.readAsStringSync()) as Map;
      for (final sample in boards.values) {
        SwiftBoard.parse(Map<String, Object?>.from(sample as Map));
      }
      expect(
        SwiftBoard.parse(
          Map<String, Object?>.from(boards['meUnranked'] as Map),
        ).rank,
        isNull,
      );
    },
    skip: restrictedSampleSkipReason(boardTest, boardSample),
  );
  const consentTest = 'shared byte fixture validates all consent states';
  test(
    consentTest,
    () {
      final choices = jsonDecode(consentSample.readAsStringSync()) as Map;
      for (final sample in choices.values) {
        SwiftConsent.parse(Map<String, Object?>.from(sample as Map));
      }
    },
    skip: restrictedSampleSkipReason(consentTest, consentSample),
  );
  test('rejects invalid handles, times, ordering, rank and consent', () {
    for (final patch in [
      {'schemaVersion': 2},
      {'computedAt': 'bad'},
      {
        'me': {'rank': 1, 'bestMs': 500000, 'optedIn': false},
      },
      {
        'entries': [
          {
            'rank': 1,
            'handle': 'SCM nickname!',
            'bestMs': 500000,
            'achievedOn': '2026-11-03',
          },
        ],
      },
      {
        'entries': [
          {
            'rank': 1,
            'handle': 'Pilot',
            'bestMs': 5400001,
            'achievedOn': '2026-11-03',
          },
        ],
      },
      {
        'entries': [
          {
            'rank': 2,
            'handle': 'Pilot',
            'bestMs': 500000,
            'achievedOn': '2026-11-03',
          },
        ],
      },
    ]) {
      expect(
        () => SwiftBoard.parse({..._board(), ...patch}),
        throwsFormatException,
      );
    }
    expect(
      () => SwiftConsent.parse({..._consent('withdrawn'), 'optedIn': true}),
      throwsFormatException,
    );
  });
  test(
    'prompt requires supported undecided state and only claims once',
    () async {
      final p = _Port(), c = SwiftLeaderboardController(_Port());
      expect(c.claimPrompt(), false);
      c.dispose();
      final controller = SwiftLeaderboardController(p);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.claimPrompt(), true);
      expect(controller.claimPrompt(), false);
      controller.reset();
      p.state = 'withdrawn';
      await controller.load();
      expect(controller.claimPrompt(), false);
      controller.reset();
      p.state = 'opted-in';
      await controller.load();
      expect(controller.claimPrompt(), false);
      controller.reset();
      p.supported = false;
      await controller.load();
      expect(controller.claimPrompt(), false);
    },
  );
  test('award prompts only after swift earned, choice writes and prevents re-prompt', () async {
    final p = _Port(), c = SwiftLeaderboardController(_Port());
    c.dispose();
    final controller = SwiftLeaderboardController(p);
    addTearDown(controller.dispose);
    await controller.checkAward(earned: p.earned);
    expect(controller.awardPending, false);
    p.earned = true;
    await controller.checkAward(earned: p.earned);
    expect(controller.awardPending, true);
    expect(controller.claimPrompt(), true);
    expect(await controller.choose(false), true);
    await controller.checkAward(earned: p.earned);
    expect(controller.awardPending, false);
    expect(p.writes, [false]);
    expect(controller.consent!.state, 'withdrawn');
  });
  test('withdrawal clears stale list and settings share consent', () async {
    final p = _Port()..state = 'opted-in';
    final c = SwiftLeaderboardController(p);
    addTearDown(c.dispose);
    await c.load(includeBoard: true);
    expect(c.board!.entries, hasLength(1));
    expect(await c.choose(false), true);
    expect(c.board, isNull);
    expect(c.bestMs, 3600000);
    expect(c.consent!.optedIn, false);
    await c.load(includeBoard: true);
    expect(c.board!.optedIn, false);
    expect(p.writes, [false]);
  });
  test(
    'date-only schema rejects timestamps, invalid dates and legacy fields',
    () {
      for (final date in [
        '2026-11-03T12:00:00Z',
        '2026-02-30',
        '2026-1-3',
        'invalid',
      ]) {
        final raw = _board();
        (raw['entries'] as List).first['achievedOn'] = date;
        expect(() => SwiftBoard.parse(raw), throwsFormatException);
      }
      final raw = _board();
      (raw['entries'] as List).first['achievedAt'] = _at;
      expect(() => SwiftBoard.parse(raw), throwsFormatException);
      expect(
        SwiftBoard.parse(_board()).entries.single.achievedOn,
        DateTime.utc(2026, 11, 3),
      );
    },
  );
  testWidgets(
    'open page refreshes withdrawal every 60 seconds and reopening revalidates',
    (tester) async {
      final p = _Port()..state = 'withdrawn';
      final c = SwiftLeaderboardController(p);
      await tester.pumpWidget(_app(SwiftLeaderboardPage(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text('1  Verified-Pilot'), findsOneWidget);
      p.empty = true;
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(p.reads, 2);
      expect(find.text('1  Verified-Pilot'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      p.empty = false;
      await tester.pumpWidget(_app(SwiftLeaderboardPage(controller: c)));
      await tester.pumpAndSettle();
      expect(p.reads, 3);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'failed or hanging refresh cannot retain rows beyond 60 seconds',
    (tester) async {
      final p = _Port()..state = 'withdrawn';
      final c = SwiftLeaderboardController(p);
      await c.load(includeBoard: true);
      await tester.pump(const Duration(seconds: 30));
      p.failRead = true;
      await c.load(includeBoard: true);
      expect(c.failed, true);
      expect(c.board!.entries, hasLength(1));
      p.failRead = false;
      p.boardHeld = Completer();
      final pending = c.load(includeBoard: true);
      await tester.pump(const Duration(seconds: 30));
      expect(c.board, isNull);
      p.boardHeld!.complete({'supported': true, 'board': _board(empty: true)});
      await pending;
      c.dispose();
    },
  );
  testWidgets(
    'own withdrawal removes rows and immediately refreshes from shared settings state',
    (tester) async {
      final p = _Port()..state = 'opted-in';
      final c = SwiftLeaderboardController(p);
      await c.load(includeBoard: true);
      c.openPage();
      p.boardHeld = Completer();
      expect(await c.choose(false), true);
      await tester.pump();
      expect(c.board, isNull);
      expect(c.consent!.optedIn, false);
      expect(p.reads, 2);
      p.boardHeld!.complete({'supported': true, 'board': _board(empty: true)});
      await tester.pump();
      c.closePage();
      c.dispose();
    },
  );
  test('every board read revalidates another player withdrawal', () async {
    final p = _Port()..state = 'withdrawn';
    final c = SwiftLeaderboardController(p);
    addTearDown(c.dispose);
    await c.load(includeBoard: true);
    expect(c.board!.entries, hasLength(1));
    p.empty = true;
    await c.load(includeBoard: true);
    expect(p.reads, 2);
    expect(c.board!.entries, isEmpty);
  });
  test('failed write preserves choice and late response is discarded on account reset', () async {
    final p = _Port()..state = 'opted-in';
    final c = SwiftLeaderboardController(p);
    addTearDown(c.dispose);
    await c.load();
    p.failWrite = true;
    expect(await c.choose(false), false);
    expect(c.writeFailed, true);
    expect(c.consent!.optedIn, true);
    c.reset();
    p.held = Completer();
    final loading = c.load();
    c.reset();
    p.held!.complete({'supported': true, 'consent': _consent('opted-in')});
    await loading;
    expect(c.consent, isNull);
    expect(c.board, isNull);
    expect(c.bestMs, isNull);
  });
  testWidgets('first leaderboard opening asks once and writes Not now', (
    tester,
  ) async {
    final p = _Port(), c = SwiftLeaderboardController(_Port());
    c.dispose();
    final controller = SwiftLeaderboardController(p);
    await tester.pumpWidget(
      _app(SwiftLeaderboardEntry(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('排行榜'));
    await tester.pumpAndSettle();
    expect(find.text('上榜会公开你的已验证游戏呼号、最好用时和达成日期'), findsOneWidget);
    await tester.tap(find.text('暂不加入'));
    await tester.pumpAndSettle();
    expect(p.writes, [false]);
    expect(find.text('未加入排行榜'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排行榜'));
    await tester.pumpAndSettle();
    expect(find.text('暂不加入'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('award prompt joins once; no prompt before earning', (
    tester,
  ) async {
    final p = _Port(), c = SwiftLeaderboardController(_Port());
    c.dispose();
    final controller = SwiftLeaderboardController(p);
    await tester.pumpWidget(
      _app(SwiftAwardPrompt(controller: controller, child: const Text('home'))),
    );
    await controller.checkAward(earned: p.earned);
    await tester.pumpAndSettle();
    expect(find.text('加入排行榜'), findsNothing);
    p.earned = true;
    await controller.checkAward(earned: p.earned);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入排行榜'));
    await tester.pumpAndSettle();
    expect(p.writes, [true]);
    await controller.checkAward(earned: p.earned);
    await tester.pumpAndSettle();
    expect(find.text('暂不加入'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('404 hides detail entry and setting', (tester) async {
    final p = _Port()..supported = false;
    final c = SwiftLeaderboardController(p);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            SwiftLeaderboardEntry(controller: c),
            SwiftLeaderboardSetting(controller: c),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('排行榜'), findsNothing);
    expect(find.text('打击群·闪击公开排行榜'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('failed first read hides detail entry until supported', (
    tester,
  ) async {
    final p = _Port()..failConsentRead = true;
    final c = SwiftLeaderboardController(p);
    await tester.pumpWidget(_app(SwiftLeaderboardEntry(controller: c)));
    await tester.pumpAndSettle();
    expect(c.failed, true);
    expect(c.supported, isNull);
    expect(find.text('排行榜'), findsNothing);
    p.failConsentRead = false;
    await c.load(includeBoard: true);
    await tester.pumpAndSettle();
    expect(c.supported, true);
    expect(find.text('排行榜'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('settings withdrawal shares saved state', (tester) async {
    final p = _Port()..state = 'opted-in';
    final c = SwiftLeaderboardController(p);
    await tester.pumpWidget(_app(SwiftLeaderboardSetting(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打击群·闪击公开排行榜'));
    await tester.pumpAndSettle();
    expect(p.writes, [false]);
    expect(c.consent!.state, 'withdrawn');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test(
    'old account collection cannot trigger a new account award prompt',
    () async {
      final p = _Port();
      final c = SwiftLeaderboardController(p, currentGeneration: () => 2);
      final source = ValueNotifier(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'contract-tsg-swift': DateTime.parse(_at)},
        ),
      );
      c.watchAchievements(source);
      await Future<void>.delayed(Duration.zero);
      expect(c.supported, isNull);
      expect(c.awardPending, false);
      source.value = AchievementCollection(
        generation: 2,
        status: AchievementCollectionStatus.ready,
        earnedAt: {'contract-tsg-swift': DateTime.parse(_at)},
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.awardPending, true);
      c.dispose();
      source.dispose();
    },
  );
  test('public list caps at 100 while own rank may exceed it', () {
    final entries = [
      for (var i = 1; i <= 100; i++)
        {
          'rank': i,
          'handle': 'Pilot-$i',
          'bestMs': 500000 + i,
          'achievedOn': '2026-11-03',
        },
    ];
    final raw = {
      ..._board(),
      'entries': entries,
      'me': {'rank': 101, 'bestMs': 600000, 'optedIn': true},
    };
    final b = SwiftBoard.parse(raw);
    expect(b.entries.length, 100);
    expect(b.rank, 101);
    expect(
      () => SwiftBoard.parse({
        ...raw,
        'entries': [
          ...entries,
          {
            'rank': 101,
            'handle': 'Pilot-101',
            'bestMs': 600000,
            'achievedOn': '2026-11-03',
          },
        ],
      }),
      throwsFormatException,
    );
  });
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      '${locale.toLanguageTag()} consent and setting fit 320px large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final p = _Port();
        final c = SwiftLeaderboardController(p);
        await c.checkAward(earned: true);
        await tester.pumpWidget(
          _app(
            SwiftAwardPrompt(controller: c, child: const SizedBox()),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        final strings = AppStrings.resolve(locale);
        expect(
          find.text(strings.text('leaderboard.disclosure')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(strings.text('leaderboard.later')));
        await tester.pumpAndSettle();
        expect(p.writes, [false]);
        await tester.pumpWidget(
          _app(
            SingleChildScrollView(
              child: SwiftLeaderboardSetting(controller: c),
            ),
            locale: locale,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(strings.text('leaderboard.setting')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
    for (final empty in [true, false]) {
      testWidgets('${locale.toLanguageTag()} empty=$empty 320px large text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final p = _Port()
          ..state = 'withdrawn'
          ..empty = empty;
        final c = SwiftLeaderboardController(p);
        await c.load(includeBoard: true);
        await tester.pumpWidget(
          _app(SwiftLeaderboardPage(controller: c), locale: locale, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!empty) expect(find.text('1  Verified-Pilot'), findsOneWidget);
        expect(
          find.text(AppStrings.resolve(locale).text('leaderboard.notJoined')),
          findsOneWidget,
        );
        expect(
          find.text(AppStrings.resolve(locale).text('leaderboard.basis')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    }
  }
}
