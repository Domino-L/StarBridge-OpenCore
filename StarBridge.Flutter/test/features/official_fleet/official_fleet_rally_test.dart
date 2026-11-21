import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/presence/account_presence_scope.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally_views.dart';

import '../../_support/visual_output_dir.dart';
import '../friends/social_layout_test.dart' show loadFonts;

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
  _Port({this.canStart = false, this.remaining = 2, this.onlineCount = 37});
  bool canStart;
  final int remaining;
  final int onlineCount;
  OfficialFleetRally? rally = _rally();
  final reads = <bool>[];
  final starts = <(String, int)>[];
  final answers = <OfficialFleetRallyAnswer>[];
  String? failure;
  @override
  bool get available => true;
  OfficialFleetRallySnapshot get _state =>
      OfficialFleetRallySnapshot(onlineCount: onlineCount, rally: rally);
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
        onlineCount: onlineCount,
        remainingThisHour: canStart ? remaining : 0,
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

Widget _app(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
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
        locale,
      ),
      home: Scaffold(body: child),
    );

Finder _compose(String control) =>
    find.byKey(Key('official-fleet-rally-$control'));

Future<void> _openCompose(
  WidgetTester tester, {
  Locale locale = const Locale('zh', 'CN'),
  double width = 800,
  int remaining = 2,
  GlobalKey? capture,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final port = _Port(canStart: true, remaining: remaining, onlineCount: 12)
    ..rally = null;
  final owner = (await tester.runAsync(() => _bound(port)))!;
  addTearDown(owner.dispose);
  expect(owner.canStart, isTrue);
  expect(owner.current, isNull);
  final account = ValueNotifier(
    const AccountProjection.loading().copyWith(
      sessionState: AccountSessionState.signedIn,
      profile: const AccountProfile(displayName: 'Test Leader'),
    ),
  );
  addTearDown(account.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: AccountPresenceScope(
        account: account,
        connection: null,
        child: _app(
          OfficialFleetRallyStartButton(controller: owner),
          locale: locale,
        ),
      ),
    ),
  );
  // Let MaterialApp finish loading its localizations before looking up the
  // page's start button.
  await tester.pumpAndSettle();
  final start = _compose('start');
  expect(start, findsOneWidget);
  await tester.tap(start);
  await tester.pumpAndSettle();
}

Iterable<Color?> _quotaDotColors(WidgetTester tester) => tester
    .widget<Row>(_compose('quota-dots'))
    .children
    .cast<Container>()
    .map((dot) => (dot.decoration! as BoxDecoration).color);

bool _selected(WidgetTester tester, String control) => tester
    .widgetList<Semantics>(
      find.ancestor(of: _compose(control), matching: find.byType(Semantics)),
    )
    .any((widget) => widget.properties.selected == true);

bool _canSend(WidgetTester tester) =>
    tester
        .widget<StarBridgeActionButton>(
          find.ancestor(
            of: _compose('send'),
            matching: find.byType(StarBridgeActionButton),
          ),
        )
        .onActivate !=
    null;

Future<void> _saveComposeImage(GlobalKey capture, String state) async {
  const batch = 'CX-RALLY-COMPOSE-073';
  const define = String.fromEnvironment('STARBRIDGE_TEST_VISUAL_DIR');
  final environment = Platform.environment['STARBRIDGE_TEST_VISUAL_DIR'];
  // Screenshots are written only when a visual output directory is configured;
  // otherwise the run leaves the working tree untouched and the assertions still run.
  if (!((environment?.isNotEmpty ?? false) || define.isNotEmpty)) return;
  final path = visualOutputDir(batch);
  final boundary =
      capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(path).create(recursive: true);
    await File('$path/rally-compose-$state.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

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
    expect(
      tester.widget<Text>(_compose('target')).semanticsLabel,
      contains('此刻在线的成员（37 人）'),
    );
    expect(
      tester.widget<Text>(_compose('quota')).semanticsLabel,
      contains('还能发 2 次'),
    );
    expect(find.textContaining('37 人此刻在线'), findsOneWidget);
    expect(find.text('这一小时还能发 2 / 3 次'), findsOneWidget);
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
    final error = find.text('这一小时的 3 次召集已经用完。');
    expect(error, findsOneWidget);
    expect(_compose('error'), findsOneWidget);
    expect(
      tester.getRect(error).bottom,
      lessThan(tester.getTopLeft(_compose('quota')).dy),
    );
    expect(
      tester.getRect(error).bottom,
      lessThan(tester.getTopLeft(_compose('send')).dy),
    );
    expect(
      tester.widget<Text>(error).style?.color,
      tester.element(error).tokens.colors.danger,
    );
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
  });

  testWidgets(
    'compose opens with an inert preview, default duration and all keys',
    (tester) async {
      await _openCompose(tester);
      for (final control in [
        'start',
        'dialog',
        'text',
        'target',
        'cancel',
        'send',
        'preset-gather',
        'preset-voice',
        'preset-support',
        'preset-online',
        'minutes-15',
        'minutes-30',
        'minutes-60',
      ]) {
        expect(_compose(control), findsOneWidget, reason: control);
      }
      final preview = _compose('preview');
      expect(preview, findsOneWidget);
      expect(tester.getSemantics(preview).label, '预览：召集内容会显示在这里');
      expect(find.bySemanticsLabel('马上到'), findsNothing);
      expect(find.text('马上到').hitTestable(), findsNothing);
      expect(find.text('来不了').hitTestable(), findsNothing);
      expect(
        find.text('Test Squadron · Test Leader 召集 · 剩余 30 分钟'),
        findsOneWidget,
      );
      expect(find.text('常用'), findsOneWidget);
      expect(find.text('0/40'), findsOneWidget);
      final field = find.descendant(
        of: _compose('text'),
        matching: find.byType(InputDecorator),
      );
      final input = tester.widget<InputDecorator>(field);
      expect(input.decoration.suffixIcon, isNotNull);
      expect(
        tester.getRect(field).contains(tester.getCenter(_compose('counter'))),
        isTrue,
      );
      expect(_selected(tester, 'minutes-15'), isFalse);
      expect(_selected(tester, 'minutes-30'), isTrue);
      expect(_selected(tester, 'minutes-60'), isFalse);
      expect(find.textContaining('12 人此刻在线'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('有效时间')).dy,
        tester.getTopLeft(find.text('通知谁')).dy,
      );
      expect(find.text('这一小时还能发 2 / 3 次'), findsOneWidget);
      final tokens = tester.element(preview).tokens;
      expect(_quotaDotColors(tester), [
        tokens.colors.stateAccent,
        tokens.colors.stateAccent,
        tokens.surfaces.status.border,
      ]);
      expect(_canSend(tester), isFalse);
    },
  );

  testWidgets(
    'filled compose selects a preset and updates preview and duration',
    (tester) async {
      await _openCompose(tester);
      await tester.tap(_compose('preset-gather'));
      await tester.pump();
      expect(_selected(tester, 'preset-gather'), isTrue);
      expect(_selected(tester, 'preset-voice'), isFalse);
      expect(find.text('2/40'), findsOneWidget);
      expect(find.text('「集合」'), findsOneWidget);
      expect(_canSend(tester), isTrue);
      await tester.tap(_compose('minutes-60'));
      await tester.pump();
      expect(_selected(tester, 'minutes-60'), isTrue);
      expect(_selected(tester, 'minutes-30'), isFalse);
      expect(
        find.text('Test Squadron · Test Leader 召集 · 剩余 60 分钟'),
        findsOneWidget,
      );
      await tester.enterText(_compose('text'), '集合，派罗争夺区');
      await tester.pump();
      expect(_selected(tester, 'preset-gather'), isFalse);
      expect(find.text('8/40'), findsOneWidget);
      expect(find.text('「集合，派罗争夺区」'), findsOneWidget);
    },
  );

  testWidgets('exhausted compose shows danger quota and disables send', (
    tester,
  ) async {
    await _openCompose(tester, remaining: 0);
    await tester.enterText(_compose('text'), '集合');
    await tester.pump();
    final quota = tester.widget<Text>(_compose('quota'));
    final tokens = tester.element(_compose('quota')).tokens;
    expect(quota.textSpan?.toPlainText(), '这一小时还能发 0 / 3 次');
    expect(
      (quota.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.text == '0')
          .style
          ?.color,
      tokens.colors.danger,
    );
    expect(
      _quotaDotColors(tester),
      List.filled(3, tokens.surfaces.status.border),
    );
    final usedUp = find.text('已经用完，下个小时再发');
    expect(usedUp, findsOneWidget);
    expect(tester.widget<Text>(usedUp).style?.color, tokens.colors.danger);
    expect(_canSend(tester), isFalse);
  });

  for (final locale in const [Locale('zh', 'CN'), Locale('en', 'US')]) {
    testWidgets(
      'narrow $locale compose stacks duration above audience without overflow',
      (tester) async {
        await _openCompose(tester, width: 390, locale: locale);
        final duration = tester.getRect(_compose('duration-track'));
        final target = tester.getRect(_compose('target'));
        expect(duration.bottom, lessThan(target.top));
        final bounds = tester.getRect(_compose('dialog'));
        for (final inside in [
          'text',
          'preview',
          'duration-track',
          'target',
          'send',
        ]) {
          final rect = tester.getRect(_compose(inside));
          expect(rect.left, greaterThanOrEqualTo(bounds.left), reason: inside);
          expect(rect.right, lessThanOrEqualTo(bounds.right), reason: inside);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Chinese preview adds exactly one pair of corner quotes', (
    tester,
  ) async {
    await _openCompose(tester);
    for (final input in ['集合', '「集合」']) {
      await tester.enterText(_compose('text'), input);
      await tester.pump();
      expect(tester.widget<Text>(_compose('preview-body')).data, '「集合」');
    }
  });

  testWidgets('English preview adds exactly one pair of curly quotes', (
    tester,
  ) async {
    await _openCompose(tester, locale: const Locale('en', 'US'));
    for (final input in ['Gather now', '“Gather now”']) {
      await tester.enterText(_compose('text'), input);
      await tester.pump();
      expect(
        tester.widget<Text>(_compose('preview-body')).data,
        '“Gather now”',
      );
    }
  });

  testWidgets('compose keeps the original keyboard traversal order', (
    tester,
  ) async {
    await _openCompose(tester);
    FocusNode buttonFocus(String control) =>
        tester.widget<ButtonStyleButton>(_compose(control)).focusNode!;
    final first = buttonFocus('preset-gather');
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('「集合」'), findsOneWidget);

    final field = tester.widget<EditableText>(
      find.descendant(
        of: _compose('text'),
        matching: find.byType(EditableText),
      ),
    );
    for (final focus in [
      buttonFocus('preset-voice'),
      buttonFocus('preset-support'),
      buttonFocus('preset-online'),
      field.focusNode,
      buttonFocus('minutes-15'),
      buttonFocus('minutes-30'),
      buttonFocus('minutes-60'),
      buttonFocus('cancel'),
      buttonFocus('send'),
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);
    }
  });

  group('compose visual captures', () {
    setUpAll(loadFonts);
    for (final state in ['open', 'filled', 'exhausted']) {
      testWidgets('captures $state compose', (tester) async {
        final capture = GlobalKey();
        await _openCompose(
          tester,
          capture: capture,
          width: 900,
          remaining: state == 'exhausted' ? 0 : 2,
        );
        if (state != 'open') {
          await tester.enterText(_compose('text'), '集合，派罗争夺区');
          if (state == 'exhausted') {
            FocusManager.instance.primaryFocus?.unfocus();
          }
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => _saveComposeImage(capture, state));
      });
    }
  });
}
