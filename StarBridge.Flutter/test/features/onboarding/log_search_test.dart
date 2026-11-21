import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_port.dart';

import 'package:starbridge_flutter/features/game_log/local_game_log_setup_panel.dart';

import '../friends/social_layout_test.dart' show app;
import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';
import 'bridge_onboarding_adapter_test.dart' as bridge;

const candidates = [
  OnboardingLogCandidate(r'C:\Games\StarCitizen\LIVE\Game.log', 'LIVE'),
  OnboardingLogCandidate(r'D:\Games\StarCitizen\EPTU\Game.log', 'EPTU'),
];

class SearchPort extends FakeOnboardingPort
    implements OnboardingLogCandidatePort {
  SearchPort(this.results) : super(observation());
  final List<OnboardingLogCandidate> results;
  int searches = 0, manual = 0;
  int? selected;
  bool blocked = false;
  Object? selectFailure;
  Completer<OnboardingReply>? held;
  static OnboardingFacts observation({
    List<OnboardingLogCandidate>? found,
    bool selected = false,
    bool blocked = false,
  }) => OnboardingFacts(
    eligibility: OnboardingEligibility.firstUse,
    available: true,
    canSave: true,
    activeMode: OnboardingMode.local,
    publicationSuspended: true,
    logReady: selected,
    sourceKey: selected ? 'selected-source-key' : null,
    version: selected ? 'LIVE' : null,
    logCandidates: found,
    logSearchBlocked: blocked,
  );
  @override
  Future<OnboardingReply> execute(
    OnboardingAction action,
    OnboardingCheckpoint checkpoint,
  ) async {
    actions.add(action);
    if (action == OnboardingAction.locateLogs) {
      searches++;
      if (held != null) return held!.future;
      this.facts = observation(found: results, blocked: blocked);
    } else if (action == OnboardingAction.selectLog) {
      manual++;
      if (selectFailure != null) throw selectFailure!;
    }
    return OnboardingReply(facts: this.facts);
  }

  @override
  Future<OnboardingReply> selectLogCandidate(
    int index,
    OnboardingCheckpoint checkpoint,
  ) async {
    expect(checkpoint.step, OnboardingStep.log);
    selected = index;
    actions.add(OnboardingAction.selectLog);
    this.facts = observation(selected: true);
    return OnboardingReply(facts: this.facts);
  }
}

class DelayedOpeningPort extends SearchPort {
  DelayedOpeningPort() : super([]);
  final release = Completer<void>();
  bool saving = false, raced = false;
  @override
  Future<OnboardingReply> save(OnboardingCheckpoint checkpoint) async {
    saves++;
    saving = true;
    await release.future;
    saving = false;
    return OnboardingReply(facts: this.facts, saved: checkpoint);
  }

  @override
  Future<OnboardingReply> execute(
    OnboardingAction action,
    OnboardingCheckpoint checkpoint,
  ) async {
    if (saving && action == OnboardingAction.locateLogs) {
      raced = true;
      throw StateError('Discovery raced the opening state-key write');
    }
    return super.execute(action, checkpoint);
  }
}

void main() {
  for (final close in [false, true]) {
    testWidgets(
      'automatic discovery waits for opening checkpoint, close=$close',
      (tester) async {
        final port = DelayedOpeningPort();
        final c = OnboardingController(port, skipWelcomeIntro: true);
        var disposed = false;
        addTearDown(() {
          if (!disposed) c.dispose();
        });
        await tester.pumpWidget(
          app(OnboardingPage(controller: c, onClose: () {})),
        );
        await tester.pumpAndSettle();
        expect(port.saves, 1);
        expect(port.saving, isTrue);
        expect(port.raced, isFalse);
        expect(port.searches, 0);
        if (close) {
          c.dispose();
          disposed = true;
          await tester.pumpWidget(const SizedBox.shrink());
        }
        port.release.complete();
        await tester.pumpAndSettle();
        expect(port.raced, isFalse);
        expect(port.searches, close ? 0 : 1);
        expect(port.selected, isNull);
        if (!close) expect(c.value.error, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'installed online guide keeps original manual selection without local discovery',
    (tester) async {
      final port = FakeOnboardingPort(facts());
      final c = await pumpSetup(
        tester,
        step: OnboardingStep.log,
        mode: OnboardingMode.local,
        port: port,
      );
      port.facts = facts(
        activeMode: OnboardingMode.online,
        publicationSuspended: false,
      );
      await c.refresh();
      await tester.pumpAndSettle();
      port.actions.clear();
      final again = find.byKey(const Key('onboarding-refresh'));
      await tester.ensureVisible(again);
      await tester.tap(again);
      await tester.pumpAndSettle();
      expect(port.actions, isEmpty);
      final manual = find.byKey(const Key('onboarding-action-selectLog'));
      await tester.ensureVisible(manual);
      await tester.tap(manual);
      await tester.pumpAndSettle();
      expect(port.actions, [OnboardingAction.selectLog]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'settings log panel shares discovery and preserves issued candidate on click',
    (tester) async {
      final f = bridge.Fixture();
      addTearDown(f.close);
      final raw = bridge.wire();
      (raw['facts']! as Map<String, Object?>)['logCandidates'] = [
        {'path': candidates[0].path, 'version': 'LIVE'},
      ];
      f.onRequest = (r) => f.respond(r, payload: raw);
      await tester.pumpWidget(app(LocalGameLogSetupPanel(session: f.session)));
      await tester.pumpAndSettle();
      expect(
        f.requests.where((r) => r.payload['action'] == 'locateLogs'),
        hasLength(1),
      );
      expect(
        f.requests.where((r) => r.payload['action'] == 'selectLog'),
        isEmpty,
      );
      final before = f.requests.length;
      final use = find.byKey(const Key('game-log-use-candidate'));
      await tester.ensureVisible(use);
      await tester.tap(use);
      await tester.pumpAndSettle();
      expect(f.requests[before].payload['action'], 'selectLog');
      expect(f.requests[before].payload['candidateIndex'], 0);
      expect(f.requests.last.payload['action'], 'refresh');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('returning to log searches once for the new visit', (
    tester,
  ) async {
    final port = SearchPort(candidates.take(1).toList());
    final c = await pumpSetup(
      tester,
      step: OnboardingStep.log,
      mode: OnboardingMode.local,
      port: port,
    );
    final use = find.byKey(const Key('game-log-use-candidate'));
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    await c.next();
    await tester.pumpAndSettle();
    c.back();
    await tester.pumpAndSettle();
    expect(port.searches, 2);
  });
  for (final count in [0, 1, 2]) {
    testWidgets('automatic search result $count requires explicit selection', (
      tester,
    ) async {
      final port = SearchPort(candidates.take(count).toList());
      final controller = await pumpSetup(
        tester,
        step: OnboardingStep.log,
        mode: OnboardingMode.local,
        port: port,
      );
      expect(port.searches, 1);
      expect(port.selected, isNull);
      expect(port.manual, 0);
      expect(controller.value.facts.logReady, isFalse);
      expect(
        find.text(count == 0 ? '没有找到游戏日志，请手动选择' : '找到了你的游戏日志'),
        findsOneWidget,
      );
      for (final item in candidates.take(count)) {
        expect(find.text(item.path), findsOneWidget);
        expect(find.text(item.version), findsOneWidget);
      }
      if (count == 0) {
        expect(find.text('选择 Game.log'), findsOneWidget);
        expect(find.text('我没有游戏日志，稍后再设置'), findsOneWidget);
      } else {
        expect(find.text('选择其他'), findsOneWidget);
        expect(find.text('使用这个'), findsNWidgets(count));
        final use = find.byKey(
          Key(count == 1 ? 'game-log-use-candidate' : 'game-log-candidate-1'),
        );
        await tester.ensureVisible(use);
        await tester.tap(use);
        await tester.pumpAndSettle();
        expect(port.selected, count == 1 ? 0 : 1);
        expect(port.actions.last, OnboardingAction.selectLog);
        expect(port.manual, 0);
        expect(controller.value.facts.logReady, isTrue);
      }
      await controller.searchLogsOnEntry();
      await tester.pumpAndSettle();
      expect(port.searches, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'choose another opens original picker and search again repeats discovery',
    (tester) async {
      final port = SearchPort(candidates.take(1).toList());
      await pumpSetup(
        tester,
        step: OnboardingStep.log,
        mode: OnboardingMode.local,
        port: port,
      );
      final other = find.byKey(const Key('onboarding-action-selectLog'));
      await tester.ensureVisible(other);
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(port.manual, 1);
      expect(port.selected, isNull);
      final again = find.byKey(const Key('onboarding-refresh'));
      await tester.ensureVisible(again);
      await tester.tap(again);
      await tester.pumpAndSettle();
      expect(port.searches, 2);
      expect(port.selected, isNull);
    },
  );
  testWidgets(
    'searching uses checking copy and discards response after dispose',
    (tester) async {
      final port = SearchPort([])..held = Completer<OnboardingReply>();
      final c = await pumpSetup(
        tester,
        step: OnboardingStep.log,
        mode: OnboardingMode.local,
        port: port,
      );
      expect(find.text('正在检查当前与允许读取的历史日志。'), findsOneWidget);
      expect(port.searches, 1);
      await tester.pumpWidget(const SizedBox());
      port.held!.complete(
        OnboardingReply(facts: SearchPort.observation(found: candidates)),
      );
      await tester.pumpAndSettle();
      expect(c.value.facts.logReady, isFalse);
      expect(port.selected, isNull);
    },
  );
  test('candidate wire is bounded, exact and cannot carry invalid paths', () {
    for (final value in [
      [
        {'path': r'\\server\LIVE\Game.log', 'version': 'LIVE'},
      ],
      [
        {'path': r'C:\Games\LIVE\..\LIVE\Game.log', 'version': 'LIVE'},
      ],
      [
        {'path': candidates[0].path, 'version': 'PTU'},
      ],
      [
        {'path': candidates[0].path, 'version': 'LIVE', 'selected': true},
      ],
      List.generate(9, (_) => {'path': candidates[0].path, 'version': 'LIVE'}),
    ]) {
      final raw = bridge.wire();
      (raw['facts']! as Map<String, Object?>)['logCandidates'] = value;
      expect(() => OnboardingWire.parse(raw), throwsFormatException);
    }
  });
  test('candidate bridge action uses selectLog and an issued index with no path input', () async {
    final f = bridge.Fixture();
    addTearDown(f.close);
    final raw = bridge.wire();
    (raw['facts']! as Map<String, Object?>)['logCandidates'] = [
      {'path': candidates[0].path, 'version': 'LIVE'},
    ];
    f.onRequest = (request) => f.respond(request, payload: raw);
    final reply = await f.adapter.read();
    final checkpoint = OnboardingCheckpoint(
      step: OnboardingStep.log,
      mode: OnboardingMode.local,
      sourceKey: reply.facts.sourceKey,
      evidenceKey: reply.facts.evidenceKey,
    );
    await f.adapter.selectLogCandidate(0, checkpoint);
    final request = f.requests.last;
    expect(request.name, 'onboarding.execute');
    expect(request.payload['action'], 'selectLog');
    expect(request.payload['candidateIndex'], 0);
    expect(request.payload.containsKey('path'), isFalse);
    expect(request.accountContext, isNull);
    expect(() => f.adapter.selectLogCandidate(1, checkpoint), throwsStateError);
  });
  for (final found in [
    <OnboardingLogCandidate>[],
    candidates.take(1).toList(),
  ]) {
    testWidgets(
      'a search stopped by a slow disk is not shown as nothing found: ${found.length}',
      (tester) async {
        final copy = OnboardingCopy(const Locale('zh', 'CN'));
        final port = SearchPort(found)..blocked = true;
        await pumpSetup(
          tester,
          step: OnboardingStep.log,
          mode: OnboardingMode.local,
          port: port,
        );
        await tester.pumpAndSettle();
        expect(port.searches, 1);
        expect(find.text(copy.text('logSearch.blocked')), findsOneWidget);
        expect(find.text(copy.text('logSearch.empty')), findsNothing);
        if (found.isNotEmpty) {
          expect(find.text(found.single.path), findsOneWidget);
          expect(find.text(copy.text('logSearch.found')), findsOneWidget);
        }
        expect(port.selected, isNull);
      },
    );
  }
  testWidgets(
    'an unwritable data folder explains storage, not a generic retry',
    (tester) async {
      final copy = OnboardingCopy(const Locale('zh', 'CN'));
      final port = SearchPort([])
        ..selectFailure = const BridgeClientException(
          'firstUse.storage_unavailable',
        );
      await pumpSetup(
        tester,
        step: OnboardingStep.log,
        mode: OnboardingMode.local,
        port: port,
      );
      await tester.pumpAndSettle();
      final manual = find.byKey(const Key('onboarding-action-selectLog'));
      await tester.ensureVisible(manual);
      await tester.tap(manual);
      await tester.pumpAndSettle();
      expect(find.text(copy.text('storageUnavailable')), findsOneWidget);
      expect(find.text(copy.text('error')), findsNothing);
    },
  );
  test('blocked search wire is an optional exact boolean', () {
    final raw = bridge.wire();
    (raw['facts']! as Map<String, Object?>)['logSearchBlocked'] = true;
    expect(OnboardingWire.parse(raw).$2.facts.logSearchBlocked, isTrue);
    expect(
      OnboardingWire.parse(bridge.wire()).$2.facts.logSearchBlocked,
      isFalse,
    );
    (raw['facts']! as Map<String, Object?>)['logSearchBlocked'] = 'yes';
    expect(() => OnboardingWire.parse(raw), throwsFormatException);
  });
}
