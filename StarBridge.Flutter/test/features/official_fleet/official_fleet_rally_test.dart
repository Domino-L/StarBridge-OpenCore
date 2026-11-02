import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally_views.dart';

const _source = 'officialFleet:7';
final _now = DateTime.utc(2026, 10, 22, 12);

OfficialFleetRally _rally({
  String state = 'active',
  OfficialFleetRallyAnswer? answer,
  int coming = 9,
}) => OfficialFleetRally(
  rallyId: 'a' * 32,
  text: '新巴贝奇集合',
  minutes: 30,
  startedAt: _now,
  expiresAt: _now.add(const Duration(minutes: 30)),
  state: state,
  coming: coming,
  cannot: 3,
  pending: 25,
  answer: answer,
);

final class _Port implements OfficialFleetRallyPort {
  _Port({this.canStart = false});
  bool canStart;
  OfficialFleetRally? rally = _rally();
  final reads = <bool>[];
  final starts = <(String, int)>[];
  final answers = <OfficialFleetRallyAnswer>[];
  String? failure;
  @override
  bool get available => true;
  OfficialFleetRallySnapshot get _state =>
      OfficialFleetRallySnapshot(onlineCount: 37, rally: rally);
  @override
  Future<OfficialFleetRallySnapshot> read(
    String sourceRef, {
    required bool online,
  }) async {
    reads.add(online);
    return _state;
  }

  @override
  Future<OfficialFleetRallyEligibility> eligibility(String sourceRef) async =>
      OfficialFleetRallyEligibility(
        canStart: canStart,
        onlineCount: 37,
        remainingThisHour: canStart ? 2 : 0,
      );
  @override
  Future<OfficialFleetRallySnapshot> start(
    String sourceRef, {
    required String operationId,
    required String text,
    required int minutes,
  }) async {
    if (failure case final code?) throw OfficialFleetRallyFailure(code);
    expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(operationId), isTrue);
    starts.add((text, minutes));
    rally = _rally(coming: 0);
    return _state;
  }

  @override
  Future<OfficialFleetRallySnapshot> respond(
    String sourceRef,
    String rallyId,
    OfficialFleetRallyAnswer answer,
  ) async {
    answers.add(answer);
    rally = _rally(answer: answer, coming: 10);
    return _state;
  }

  @override
  Future<OfficialFleetRallySnapshot> end(
    String sourceRef,
    String rallyId,
  ) async {
    rally = _rally(state: 'ended');
    return _state;
  }
}

Future<OfficialFleetRallyController> _bound(
  _Port port, {
  bool online = true,
}) async {
  final controller = OfficialFleetRallyController(
    port,
    countedOnline: () => online,
    now: () => _now.add(const Duration(minutes: 2)),
    interval: const Duration(days: 1),
  );
  controller.bind(_source, fleetName: 'Test Squadron');
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return controller;
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ],
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  ),
  home: Scaffold(body: child),
);

void main() {
  test(
    'a member is prompted once; invisible clients are not counted',
    () async {
      final port = _Port();
      final member = await _bound(port);
      expect(port.reads, [true]);
      expect(member.prompt?.text, '新巴贝奇集合');
      expect(member.takeAnnouncement(), isNotNull);
      expect(
        member.takeAnnouncement(),
        isNull,
        reason: 'one desktop notice per rally',
      );
      member.dismiss();
      expect(member.prompt, isNull);
      member.dispose();

      final hidden = await _bound(_Port(), online: false);
      expect((hidden.port as _Port).reads, [false]);
      hidden.dispose();
    },
  );

  test('the owner is never prompted by their own rally', () async {
    final owner = await _bound(_Port(canStart: true));
    expect(owner.canStart, isTrue);
    expect(owner.prompt, isNull);
    owner.dispose();
  });

  test('answering records the answer and clears the prompt', () async {
    final port = _Port();
    final member = await _bound(port);
    expect(await member.respond(OfficialFleetRallyAnswer.coming), isNull);
    expect(port.answers, [OfficialFleetRallyAnswer.coming]);
    expect(member.current?.answer, OfficialFleetRallyAnswer.coming);
    expect(member.prompt, isNull);
    member.dispose();
  });

  testWidgets('owner strip shows counts and the end button only', (
    tester,
  ) async {
    final owner = (await tester.runAsync(() => _bound(_Port(canStart: true))))!;
    await tester.pumpWidget(_app(OfficialFleetRallyStrip(controller: owner)));
    await tester.pump();
    expect(find.text('「新巴贝奇集合」'), findsOneWidget);
    expect(find.textContaining('马上到'), findsOneWidget);
    expect(find.byKey(const Key('official-fleet-rally-end')), findsOneWidget);
    expect(
      find.byKey(const Key('official-fleet-rally-answer-coming')),
      findsNothing,
    );
    expect(find.text('剩余 28 分钟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-fleet-rally-end')));
    await tester.pump();
    expect(
      find.text('召集已结束'),
      findsOneWidget,
      reason: 'the owner keeps the result',
    );
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
  });

  testWidgets('member strip answers and hides once the rally ends', (
    tester,
  ) async {
    final port = _Port();
    final member = (await tester.runAsync(() => _bound(port)))!;
    await tester.pumpWidget(_app(OfficialFleetRallyStrip(controller: member)));
    await tester.pump();
    expect(find.byKey(const Key('official-fleet-rally-end')), findsNothing);
    await tester.tap(
      find.byKey(const Key('official-fleet-rally-answer-cannot')),
    );
    await tester.pump();
    expect(port.answers, [OfficialFleetRallyAnswer.cannot]);
    port.rally = _rally(state: 'ended');
    await tester.runAsync(member.refresh);
    await tester.pump();
    expect(find.byKey(const Key('official-fleet-rally-strip')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    member.dispose();
  });

  testWidgets('the start dialog needs a line and sends the chosen length', (
    tester,
  ) async {
    final port = _Port(canStart: true)..rally = null;
    final owner = (await tester.runAsync(() => _bound(port)))!;
    await tester.pumpWidget(
      _app(OfficialFleetRallyStartButton(controller: owner)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-fleet-rally-start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('此刻在线的成员（37 人）'), findsOneWidget);
    expect(find.textContaining('还能发 2 次'), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-fleet-rally-send')));
    await tester.pump();
    expect(port.starts, isEmpty, reason: 'no text yet');
    await tester.tap(
      find.byKey(const Key('official-fleet-rally-preset-voice')),
    );
    await tester.tap(find.byKey(const Key('official-fleet-rally-minutes-15')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-fleet-rally-send')));
    await tester.pumpAndSettle();
    expect(port.starts, [('上语音', 15)]);
    expect(find.byKey(const Key('official-fleet-rally-dialog')), findsNothing);
    expect(
      find.byKey(const Key('official-fleet-rally-start')),
      findsNothing,
      reason: 'a running rally hides the start button',
    );
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
  });

  testWidgets('a refused start explains itself in the dialog', (tester) async {
    final port = _Port(canStart: true)
      ..rally = null
      ..failure = 'rateLimited';
    final owner = (await tester.runAsync(() => _bound(port)))!;
    await tester.pumpWidget(
      _app(OfficialFleetRallyStartButton(controller: owner)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-fleet-rally-start')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('official-fleet-rally-text')),
      '集合',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-fleet-rally-send')));
    await tester.pumpAndSettle();
    expect(find.text('这一小时的 3 次召集已经用完。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
  });
}
