import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_holo_online.dart';
import 'package:starbridge_flutter/features/common/organization_member_row.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_chat_workspace.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_command_row.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_views.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rail_previews.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';

const _source = 'officialFleet:7';
const _field = OfficialFleetMemberField(
  OfficialFleetMemberFieldState.notShared,
);

OfficialFleetMember _member(
  String name,
  OfficialFleetMemberPresence presence, {
  bool paused = false,
}) => OfficialFleetMember(
  memberRef: name,
  callsign: name,
  gameId: name,
  officialRankName: null,
  officialRankValue: null,
  presence: presence,
  server: _field,
  ship: _field,
  location: _field,
  starBridgeConnected: true,
  identityState: OfficialFleetMemberIdentityState.starBridge,
  sharingPaused: paused,
);

final _crew = [
  _member('Playing', OfficialFleetMemberPresence.inGame),
  _member('Online', OfficialFleetMemberPresence.online),
  _member('AwayOne', OfficialFleetMemberPresence.away),
  _member('AwayTwo', OfficialFleetMemberPresence.away),
  _member('Invisible', OfficialFleetMemberPresence.invisible),
  _member('ManualOffline', OfficialFleetMemberPresence.offline),
  _member('PausedAway', OfficialFleetMemberPresence.away, paused: true),
  _member('PausedPlaying', OfficialFleetMemberPresence.inGame, paused: true),
];

OfficialFleetMemberDirectoryProjection _projection({
  List<OfficialFleetMember>? crew,
  int? total,
  OfficialFleetMemberDirectoryQuery query =
      const OfficialFleetMemberDirectoryQuery(sourceRef: _source),
  bool presence = true,
}) => OfficialFleetMemberDirectoryProjection.fromSnapshot(
  OfficialFleetMemberDirectorySnapshot.available(
    query: query,
    members: crew ?? _crew,
    totalCount: total ?? (crew ?? _crew).length,
    onlineCount: null,
    inGameCount: null,
    totalPages: 1,
    runtimeCapabilities: presence
        ? const OfficialFleetMemberRuntimeCapabilities.all()
        : const OfficialFleetMemberRuntimeCapabilities.none(),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  WidgetBuilder builder, {
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
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
      home: Scaffold(body: Builder(builder: builder)),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectPrivateMembersAbsent() {
  for (final name in [
    'Invisible',
    'ManualOffline',
    'PausedAway',
    'PausedPlaying',
  ]) {
    expect(find.text(name), findsNothing);
    expect(find.byTooltip(name), findsNothing);
    expect(find.byTooltip('$name · 暂离'), findsNothing);
  }
}

void main() {
  test('screen total includes away, keeps game count and offline privacy', () {
    final projection = _projection();
    expect(projection.visibleOnlineCount, 4);
    expect(projection.visibleInGameCount, 1);
    for (final member in _crew.skip(4)) {
      expect(member.publicPresence, OfficialFleetMemberPresence.offline);
      final alone = _projection(crew: [member]);
      expect(alone.visibleOnlineCount, 0);
      expect(alone.visibleInGameCount, 0);
    }
    expect(_crew[2].publicPresence, OfficialFleetMemberPresence.away);
  });

  test('away does not bypass completeness, query or capability guards', () {
    expect(_projection(total: 99).visibleOnlineCount, isNull);
    expect(_projection(presence: false).visibleOnlineCount, isNull);
    for (final query in [
      const OfficialFleetMemberDirectoryQuery(
        sourceRef: _source,
        search: 'Away',
      ),
      const OfficialFleetMemberDirectoryQuery(
        sourceRef: _source,
        filter: OfficialFleetMemberFilter.online,
      ),
    ]) {
      expect(_projection(query: query).visibleOnlineCount, isNull);
    }
  });

  testWidgets(
    'command avatars retain away label and member-page warning color',
    (tester) async {
      final rally = OfficialFleetRallyController(
        const UnavailableOfficialFleetRallyPort(),
      );
      addTearDown(rally.dispose);
      late Color warning;
      await _pump(tester, (context) {
        warning = context.tokens.colors.warning;
        final entry = officialFleetMemberEntry(context, _crew[2]);
        expect(entry.presence, OrganizationMemberPresence.away);
        return OfficialFleetCommandRow(members: _projection(), rally: rally);
      });
      for (final name in ['AwayOne', 'AwayTwo']) {
        final tooltip = find.byTooltip('$name · 暂离');
        expect(tooltip, findsOneWidget);
        final dot = find.descendant(
          of: tooltip,
          matching: find.byKey(ValueKey('official-fleet-command-away-$name')),
        );
        expect(dot, findsOneWidget);
        expect(tester.widget<ColoredBox>(dot).color, warning);
      }
      expect(find.byTooltip('Online'), findsOneWidget);
      expect(find.byTooltip('Playing'), findsOneWidget);
      _expectPrivateMembersAbsent();
    },
  );

  testWidgets('away avatars contribute to command overflow count', (
    tester,
  ) async {
    final rally = OfficialFleetRallyController(
      const UnavailableOfficialFleetRallyPort(),
    );
    addTearDown(rally.dispose);
    await _pump(
      tester,
      (_) => OfficialFleetCommandRow(
        members: _projection(
          crew: [
            ..._crew,
            for (var i = 0; i < 3; i++)
              _member('ExtraAway$i', OfficialFleetMemberPresence.away),
          ],
        ),
        rally: rally,
      ),
    );
    expect(find.text('+1'), findsOneWidget);
    _expectPrivateMembersAbsent();
  });

  for (final (locale, split, away, group) in [
    (const Locale('zh', 'CN'), '游戏中 1 · 在线 1 · 暂离 2', '暂离', '暂离 · 2'),
    (const Locale('zh', 'TW'), '遊戲中 1 · 在線 1 · 暫離 2', '暫離', '暫離 · 2'),
    (const Locale('en'), 'In game 1 · online 1 · away 2', 'Away', 'Away · 2'),
  ]) {
    testWidgets('member preview separates away in $locale', (tester) async {
      await _pump(
        tester,
        (context) => SizedBox(
          width: 360,
          child: OfficialFleetRailPreviews.members(
            context,
            _projection(),
            null,
            _source,
          ),
        ),
        locale: locale,
      );
      expect(find.text(split), findsOneWidget);
      for (final name in ['AwayOne', 'AwayTwo']) {
        expect(find.byTooltip('$name · $away'), findsOneWidget);
        expect(find.text(name.substring(0, 1)), findsWidgets);
      }
      expect(find.text('I'), findsNothing);
      expect(find.text('M'), findsNothing);
      expect(
        find.text('P'),
        findsOneWidget,
        reason: 'Only Playing, no paused row.',
      );
    });

    testWidgets('chat includes a distinct away group in $locale', (
      tester,
    ) async {
      final members = ValueNotifier(_projection());
      addTearDown(members.dispose);
      late Color warning;
      await _pump(tester, (context) {
        warning = context.tokens.colors.warning;
        return SizedBox(
          width: 260,
          child: OfficialFleetOnlinePane(members: members),
        );
      }, locale: locale);
      final column = tester.widget<OrganizationHoloOnlineColumn>(
        find.byType(OrganizationHoloOnlineColumn),
      );
      expect(column.count, '4');
      expect(column.groups.map((g) => g.members.length), [1, 1, 2]);
      final awayGroup = column.groups.singleWhere((g) => g.label == group);
      expect(awayGroup.members.map((m) => m.name), ['AwayOne', 'AwayTwo']);
      for (final member in awayGroup.members) {
        expect(member.detail, away);
        expect(member.dot, warning);
        expect(find.byKey(member.key), findsOneWidget);
      }
      expect(find.text(group), findsOneWidget);
      _expectPrivateMembersAbsent();

      await _pump(
        tester,
        (_) => SizedBox(
          width: 44,
          child: OfficialFleetOnlinePane(members: members, collapsed: true),
        ),
        locale: locale,
      );
      final rail = tester.widget<OrganizationHoloOnlineRail>(
        find.byType(OrganizationHoloOnlineRail),
      );
      expect(rail.count, '4');
      expect(rail.members.where((m) => m.detail == away), hasLength(2));
      expect(rail.members, hasLength(4));
    });
  }

  testWidgets(
    'chat keeps away label and page lower bound on incomplete roster',
    (tester) async {
      final members = ValueNotifier(_projection(total: 99));
      addTearDown(members.dispose);
      await _pump(
        tester,
        (_) => SizedBox(
          width: 260,
          child: OfficialFleetOnlinePane(members: members),
        ),
      );
      expect(
        tester
            .widget<OrganizationHoloOnlineColumn>(
              find.byType(OrganizationHoloOnlineColumn),
            )
            .count,
        '4+',
      );
      expect(find.text('暂离 · 2'), findsOneWidget);
      _expectPrivateMembersAbsent();
    },
  );

  testWidgets('away alone is online; privacy changes remove it from chat', (
    tester,
  ) async {
    final members = ValueNotifier(_projection(crew: [_crew[2]]));
    addTearDown(members.dispose);
    await _pump(
      tester,
      (_) => SizedBox(
        width: 260,
        child: OfficialFleetOnlinePane(members: members),
      ),
    );
    expect(find.text('暂离 · 1'), findsOneWidget);
    expect(find.text('现在没有成员在线'), findsNothing);
    expect(find.text('在线 · 1'), findsNothing);
    for (final member in _crew.skip(4)) {
      members.value = _projection(crew: [member]);
      await tester.pumpAndSettle();
      final column = tester.widget<OrganizationHoloOnlineColumn>(
        find.byType(OrganizationHoloOnlineColumn),
      );
      expect(column.count, '0');
      expect(column.groups, isEmpty);
      expect(find.text('现在没有成员在线'), findsOneWidget);
      expect(find.text('暂离 · 1'), findsNothing);
    }
  });
}
