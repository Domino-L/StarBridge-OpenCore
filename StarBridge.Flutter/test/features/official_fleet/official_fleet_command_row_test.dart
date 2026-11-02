import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_command_row.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';

const _source = 'officialFleet:7';
final _now = DateTime.utc(2026, 10, 22, 12);

OfficialFleetMember _member(
  String name,
  OfficialFleetMemberPresence presence, {
  String? location,
  bool sharingPaused = false,
}) => OfficialFleetMember(
  memberRef: name.padRight(64, '0').substring(0, 64),
  callsign: name,
  gameId: name,
  officialRankName: null,
  officialRankValue: null,
  presence: presence,
  server: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  ship: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  location: location == null
      ? const OfficialFleetMemberField(OfficialFleetMemberFieldState.notShared)
      : OfficialFleetMemberField.value(location),
  starBridgeConnected: true,
  identityState: OfficialFleetMemberIdentityState.starBridge,
  sharingPaused: sharingPaused,
);

OfficialFleetMemberDirectoryProjection _projection(
  List<OfficialFleetMember> members, {
  int? online,
  bool realtime = true,
}) => OfficialFleetMemberDirectoryProjection.fromSnapshot(
  OfficialFleetMemberDirectorySnapshot.available(
    query: const OfficialFleetMemberDirectoryQuery(sourceRef: _source),
    members: members,
    totalCount: members.length,
    onlineCount: online,
    inGameCount: members
        .where((m) => m.presence == OfficialFleetMemberPresence.inGame)
        .length,
    totalPages: 1,
    runtimeCapabilities: realtime
        ? const OfficialFleetMemberRuntimeCapabilities.all()
        : const OfficialFleetMemberRuntimeCapabilities.none(),
  ),
);

final class _Port implements OfficialFleetRallyPort {
  OfficialFleetRally? rally;
  bool canStart = false;
  @override
  bool get available => true;
  @override
  Future<OfficialFleetRallySnapshot> read(
    String s, {
    required bool online,
  }) async => OfficialFleetRallySnapshot(onlineCount: 3, rally: rally);
  @override
  Future<OfficialFleetRallyEligibility> eligibility(String s) async =>
      OfficialFleetRallyEligibility(
        canStart: canStart,
        onlineCount: 3,
        remainingThisHour: canStart ? 3 : 0,
      );
  @override
  Future<OfficialFleetRallySnapshot> start(
    String s, {
    required String operationId,
    required String text,
    required int minutes,
  }) => throw UnimplementedError();
  @override
  Future<OfficialFleetRallySnapshot> respond(
    String s,
    String id,
    OfficialFleetRallyAnswer a,
  ) => throw UnimplementedError();
  @override
  Future<OfficialFleetRallySnapshot> end(String s, String id) =>
      throw UnimplementedError();
}

Future<OfficialFleetRallyController> _rally(_Port port) async {
  final controller = OfficialFleetRallyController(
    port,
    now: () => _now,
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

OfficialFleetMemberDirectoryProjection _held() =>
    OfficialFleetMemberDirectoryProjection.fromSnapshot(
      OfficialFleetMemberDirectorySnapshot.unavailable(
        query: const OfficialFleetMemberDirectoryQuery(sourceRef: _source),
        failureKey: 'officialFleet.members.error.unavailable',
      ),
      presenceWasShown: true,
    );

void main() {
  final crew = [
    _member('多米诺', OfficialFleetMemberPresence.inGame, location: '斯坦顿 · 新巴贝奇'),
    _member(
      'Kestrel',
      OfficialFleetMemberPresence.inGame,
      location: '斯坦顿 · 新巴贝奇',
    ),
    _member('Rook', OfficialFleetMemberPresence.inGame, location: '派罗 · 鲁因站'),
    _member('Nova', OfficialFleetMemberPresence.online),
    _member('Ghost', OfficialFleetMemberPresence.invisible),
    _member(
      'Paused',
      OfficialFleetMemberPresence.inGame,
      location: '秘密',
      sharingPaused: true,
    ),
    _member('Off', OfficialFleetMemberPresence.offline),
  ];

  test('a realtime roster shows the row without a server count', () {
    expect(
      OfficialFleetCommandRow.available(_projection(crew, online: 4)),
      isTrue,
    );
    expect(
      OfficialFleetCommandRow.available(
        _projection(crew, online: 4, realtime: false),
      ),
      isFalse,
    );
    expect(OfficialFleetCommandRow.available(_projection(crew)), isTrue);
    expect(
      OfficialFleetCommandRow.available(
        const OfficialFleetMemberDirectoryProjection.idle(),
      ),
      isFalse,
    );
  });

  testWidgets('a failed read keeps the row and its height, with no names', (
    tester,
  ) async {
    final rally = (await tester.runAsync(() => _rally(_Port())))!;
    Future<double> height(
      OfficialFleetMemberDirectoryProjection members,
    ) async {
      await tester.pumpWidget(
        _app(
          OfficialFleetCommandRow(
            members: members,
            rally: rally,
            sourceRef: _source,
          ),
        ),
      );
      await tester.pump();
      return tester
          .getSize(find.byKey(const Key('official-fleet-command-row')))
          .height;
    }

    final shown = await height(
      _projection([
        _member('Nova', OfficialFleetMemberPresence.online),
      ], online: 1),
    );
    expect(find.byTooltip('Nova'), findsOneWidget);
    final held = await height(_held());
    expect(held, shown, reason: 'The page below must not move.');
    expect(find.byTooltip('Nova'), findsNothing);
    expect(find.text('暂时无法显示'), findsOneWidget);
    expect(OfficialFleetCommandRow.available(_held()), isFalse);
    expect(OfficialFleetCommandRow.holdsPlace(_held()), isTrue);
    await tester.pumpWidget(const SizedBox());
    rally.dispose();
  });

  testWidgets('online crew, the busiest shared location, owner actions', (
    tester,
  ) async {
    final port = _Port()..canStart = true;
    final rally = (await tester.runAsync(() => _rally(port)))!;
    var announced = 0;
    await tester.pumpWidget(
      _app(
        OfficialFleetCommandRow(
          members: _projection(crew, online: 12),
          rally: rally,
          sourceRef: _source,
          onAnnounce: () => announced++,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('此刻在线'), findsOneWidget);
    // Invisible and sharing-paused members count as offline, never as online.
    expect(find.byType(Tooltip), findsNWidgets(4));
    // Complete pages derive counts from visible rows, even with stale metrics.
    expect(find.text('+8'), findsNothing);
    expect(find.text('多米诺 和 Kestrel 在 斯坦顿 · 新巴贝奇'), findsOneWidget);
    expect(find.textContaining('秘密'), findsNothing);
    expect(find.byKey(const Key('official-fleet-rally-start')), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-fleet-command-announce')));
    expect(announced, 1);
    await tester.pumpWidget(const SizedBox());
    rally.dispose();
  });

  testWidgets('members see no owner actions; nobody in game reads plainly', (
    tester,
  ) async {
    final rally = (await tester.runAsync(() => _rally(_Port())))!;
    await tester.pumpWidget(
      _app(
        OfficialFleetCommandRow(
          members: _projection([
            _member('Nova', OfficialFleetMemberPresence.online),
          ], online: 1),
          rally: rally,
          sourceRef: _source,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('official-fleet-rally-start')), findsNothing);
    expect(
      find.byKey(const Key('official-fleet-command-announce')),
      findsNothing,
    );
    expect(find.text('暂时没有成员在游戏中'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    rally.dispose();
  });

  testWidgets('a running rally replaces the row', (tester) async {
    final port = _Port()
      ..rally = OfficialFleetRally(
        rallyId: 'a' * 32,
        text: '集合',
        minutes: 30,
        startedAt: _now,
        expiresAt: _now.add(const Duration(minutes: 30)),
        state: 'active',
        coming: 0,
        cannot: 0,
        pending: 3,
      );
    final rally = (await tester.runAsync(() => _rally(port)))!;
    await tester.pumpWidget(
      _app(
        OfficialFleetCommandRow(
          members: _projection(crew, online: 4),
          rally: rally,
          sourceRef: _source,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('official-fleet-command-row')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    rally.dispose();
  });
}
