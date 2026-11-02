import '../../app/menu_overlay/menu_resolved_copy_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_member_copy.dart';
import 'package:starbridge_flutter/features/common/organization_member_runtime_cells.dart';
import 'package:starbridge_flutter/features/communities/community_member_runtime.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_copy.dart';
import 'package:starbridge_flutter/features/communities/community_online_members_controller.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_member_presentation.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_view.dart'
    show organizationPresence, MenuOrganizationRow;

import 'community_workspace_test.dart' show workspacePayload;
import '../friends/social_layout_test.dart' show app;

void main() {
  test('0.7.1 non-game runtime uses three separate not-in-game values', () {
    ({String server, String ship, String location}) render(
      String state, {
      bool? session,
    }) {
      final row =
          Map<String, Object?>.from(
            (workspacePayload()['members'] as List).single as Map,
          )..addAll({
            'liveStatus': state,
            'online': true,
            'hasServerSession': session,
          });
      final member = CommunityWorkspaceMember.parse(row);
      final cells = communityMemberRuntimeCells(
        member,
        text: (key) => key,
        regionText: (value) => value,
      );
      final values = communityMemberRuntime(
        member,
        text: (key) => key,
        regionText: (value) => value,
      );
      expect(
        (values.server, values.ship, values.location),
        (cells.server.text, cells.ship.text, cells.location.text),
      );
      if (state != 'InGame') {
        for (final cell in [cells.server, cells.ship, cells.location]) {
          expect(cell.isPlaceholder, isTrue);
        }
      }
      return values;
    }

    for (final state in [
      'Offline',
      'ManualOffline',
      'Invisible',
      'Paused',
      'Unknown',
      'AppOnline',
      'Away',
    ]) {
      final values = render(state);
      expect(
        (values.server, values.ship, values.location),
        ('notInGame', 'notInGame', 'notInGame'),
        reason: state,
      );
    }
    expect(render('InGame', session: false).server, 'notInServer');
  });

  testWidgets('0.7.1 runtime copy is restored and rejects missing keys', (
    tester,
  ) async {
    late BuildContext context;
    var built = false;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            built = true;
            return const SizedBox(key: Key('runtime-copy-context'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built, isTrue);
    context = tester.element(find.byKey(const Key('runtime-copy-context')));
    expect(memberBoardText(context, 'hidden'), '暂无可见信息');
    expect(memberBoardText(context, 'restricted'), '暂无可见信息');
    expect(memberBoardText(context, 'waitingRecognition'), '等待识别');
    expect(memberBoardText(context, 'waitingServerSync'), '等待服务器同步');
    expect(memberBoardText(context, 'locationPending'), '地点待确认');
    expect(memberBoardText(context, 'lowConfidenceLocation'), '低可信度位置');
    expect(
      () => memberBoardText(context, 'missing-member-copy-key'),
      throwsA(isA<StateError>()),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    '0.7.1 real runtime mapping preserves typed facts across menu transport',
    () {
      MemberRuntimeCells render(Map<String, Object?> changes) {
        final row =
            Map<String, Object?>.from(
              (workspacePayload()['members'] as List).single as Map,
            )..addAll({
              'liveStatus': 'InGame',
              'online': true,
              'serverRegion': 'USA',
              'ship': 'C2 Hercules',
              'location': 'Orison',
              'arrivalPendingConfirmation': false,
              'arrivalTargetCode': null,
              ...changes,
            });
        final member = CommunityWorkspaceMember.parse(row);
        final direct = communityMemberRuntimeCells(
          member,
          text: (key) =>
              memberBoardTextForLocale(const Locale('zh', 'CN'), key),
          regionText: (value) => value,
        );
        final menu = MenuOrganizationRow.parse(
          resolvedMenuCopy(organizationMemberPresentation(member, null, 'om1').presentation),
        );
        expect(menu.ship, direct.ship.text);
        expect(menu.location, direct.location.text);
        expect(
          menu.serverKind,
          direct.server.isPlaceholder ? 'placeholder' : 'value',
        );
        expect(
          menu.shipKind,
          direct.ship.isPlaceholder ? 'placeholder' : 'value',
        );
        expect(
          menu.locationKind,
          direct.location.isPlaceholder ? 'placeholder' : 'value',
        );
        return direct;
      }

      final visible = render({});
      expect(visible.ship.text, 'C2 Hercules');
      expect(visible.ship.isPlaceholder, isFalse);
      expect(visible.server.isPlaceholder, isFalse);
      expect(visible.location.isPlaceholder, isFalse);
      final hidden = render({
        'serverRegion': null,
        'ship': null,
        'location': null,
      });
      for (final cell in [hidden.server, hidden.ship, hidden.location]) {
        expect(cell.text, '暂无可见信息');
        expect(cell.isPlaceholder, isTrue);
      }
      final identifying = render({
        'serverRegion': 'Unknown',
        'hasServerSession': true,
        'ship': 'Unknown',
        'location': 'Unknown',
      });
      expect(identifying.server.text, '等待服务器同步');
      expect(identifying.server.isPlaceholder, isTrue);
      for (final cell in [identifying.ship, identifying.location]) {
        expect(cell.text, '等待识别');
        expect(cell.isPlaceholder, isTrue);
      }
      final noServer = render({'hasServerSession': false});
      expect(noServer.server.text, '未进入服务器');
      expect(noServer.server.isPlaceholder, isTrue);
      expect(noServer.ship.text, '未进入服务器');
      expect(noServer.location.text, '未进入服务器');
      final waitingForSession = render({
        'serverRegion': 'Unknown',
        'ship': 'Unknown',
        'location': 'Unknown',
      });
      for (final cell in [
        waitingForSession.server,
        waitingForSession.ship,
        waitingForSession.location,
      ]) {
        expect(cell.text, '等待服务器同步');
        expect(cell.isPlaceholder, isTrue);
      }
      final withheldWithoutSession = render({
        'serverRegion': null,
        'hasServerSession': false,
        'ship': null,
        'location': null,
        'arrivalPendingConfirmation': true,
        'arrivalTargetCode': 'Private destination',
      });
      for (final cell in [
        withheldWithoutSession.server,
        withheldWithoutSession.ship,
        withheldWithoutSession.location,
      ]) {
        expect(cell.text, '暂无可见信息');
        expect(cell.isPlaceholder, isTrue);
      }
      final arrival = render({
        'location': 'Unknown',
        'arrivalPendingConfirmation': true,
        'arrivalTargetCode': 'Orison',
      });
      expect(arrival.location.text, 'Orison · 地点待确认');
      expect(arrival.location.isPlaceholder, isTrue);
      expect(
        render({'location': 'Unknown', 'arrivalPendingConfirmation': true})
            .location
            .text,
        '地点待确认',
      );
      expect(
        render({'location': 'Unknown', 'locationHiddenReason': 'lowConfidence'})
            .location
            .text,
        '低可信度位置',
      );
      expect(
        render({'location': null, 'locationHiddenReason': 'lowConfidence'})
            .location
            .text,
        '暂无可见信息',
      );
      expect(
        render({
          'location': null,
          'arrivalPendingConfirmation': true,
          'arrivalTargetCode': 'Private destination',
        }).location.text,
        '暂无可见信息',
      );
      expect(const MemberRuntimeCell.value('').text, '');
      expect(const MemberRuntimeCell.placeholder('').text, '');
      final payload = workspacePayload();
      final defaultMember = CommunityWorkspaceMember.parse(
        Map<String, Object?>.from((payload['members'] as List).single as Map)
          ..addAll({'roleColor': '#9DAAB3'}),
      );
      final display = resolvedMenuCopy(organizationMemberPresentation(
        defaultMember,
        null,
        'om1',
      ).presentation);
      expect(display['roleColor'], '');
      for (final invalid in ['url', '', 'value-with-extra', 1, true]) {
        expect(
          () => MenuOrganizationRow.parse({...display, 'shipKind': invalid}),
          throwsFormatException,
        );
      }
    },
  );

  test('0.7.1 runtime wording matches the exact release in every locale', () {
    const expected = <String, (String, String, String)>{
      'appOnline': ('应用在线', '應用程式上線', 'App online'),
      'hidden': ('暂无可见信息', '暫無可見資訊', 'No visible information'),
      'restricted': ('暂无可见信息', '暫無可見資訊', 'No visible information'),
      'notInGame': ('未进入游戏', '未進入遊戲', 'Not in game'),
      'notInServer': ('未进入服务器', '未進入伺服器', 'Not in a server'),
      'waitingRecognition': ('等待识别', '等待識別', 'Waiting for recognition'),
      'waitingServerSync': ('等待服务器同步', '等待伺服器同步', 'Waiting for server sync'),
      'locationPending': ('地点待确认', '地點待確認', 'Location pending confirmation'),
      'lowConfidenceLocation': ('低可信度位置', '低可信度位置', 'Low-confidence location'),
    };
    for (final (index, locale) in const [
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('en', 'US'),
    ].indexed) {
      String text(String key) => memberBoardTextForLocale(locale, key);
      for (final entry in expected.entries) {
        final value = entry.value;
        expect(
          text(entry.key),
          [value.$1, value.$2, value.$3][index],
          reason: '${entry.key}/$locale must match cf0cf8f8.',
        );
      }
      expect(() => text('missing-member-copy-key'), throwsA(isA<StateError>()));
    }
  });

  test('unavailable presence matches offline and never counts online in either surface', () {
    final row = Map<String, Object?>.from(
      (workspacePayload()['members'] as List).single as Map,
    );
    for (final state in ['', 'Unknown', ' hidden ', 'Unrecognized']) {
      for (final online in [false, true]) {
        final member = CommunityWorkspaceMember.parse({
          ...row,
          'liveStatus': state,
          'online': online,
        });
        expect(member.publicPresence, 'offline', reason: '$state/$online');
        expect(member.publicOnline, isFalse);
        expect(member.publicInGame, isFalse);
        expect(CommunityOnlineMembersController.visibleOnline(member), isFalse);
        expect(organizationPresence(online, state), 'offline');
        expect(
          organizationMemberPresentation(
            member,
            null,
            'profile',
          ).presentation['presence'],
          'offline',
        );
        final runtime = communityMemberRuntime(
          member,
          text: (key) => communityWorkspaceCopy[key]!.$1,
          regionText: (value) => value,
        );
        expect(
          (runtime.server, runtime.ship, runtime.location),
          ('未进入游戏', '未进入游戏', '未进入游戏'),
        );
      }
    }
    for (final state in ['Offline', 'Paused', 'Invisible', 'ManualOffline']) {
      final member = CommunityWorkspaceMember.parse({
        ...row,
        'liveStatus': state,
        'online': true,
      });
      expect(member.publicPresence, 'offline');
      expect(member.publicOnline, isFalse);
      expect(member.publicInGame, isFalse);
      expect(CommunityOnlineMembersController.visibleOnline(member), isFalse);
      expect(organizationPresence(true, state), 'offline');
    }
  });

  test(
    'organization projection makes hidden presence identical to offline',
    () {
      CommunityWorkspaceMember member(String state, {bool online = true}) {
        final payload = workspacePayload();
        final row =
            Map<String, Object?>.from(
              (payload['members'] as List).single as Map,
            )..addAll({
              'liveStatus': state,
              'online': online,
              'serverRegion': 'USA',
              'ship': 'Secret ship',
              'location': 'Secret location',
              'hasServerSession': true,
              'arrivalPendingConfirmation': true,
              'arrivalTargetCode': 'Secret destination',
            });
        return CommunityWorkspaceMember.parse(row);
      }

      final offline = member('Offline', online: false);
      final expected = organizationMemberPresentation(offline, null, 'profile');
      for (final state in [
        'ManualOffline',
        'manual-offline',
        'MANUAL_OFFLINE',
        ' Invisible ',
        'iNvIsIbLe',
        'Paused',
        ' pAuSeD ',
        'Stopped',
        'SyncPaused',
        'Unknown',
        ' hidden ',
        'Unrecognized',
        '',
      ]) {
        final hidden = member(state);
        expect(hidden.online, isFalse, reason: state);
        expect(hidden.liveStatus.toLowerCase(), 'offline', reason: state);
        expect(hidden.serverRegion, isNull, reason: state);
        expect(hidden.ship, isNull, reason: state);
        expect(hidden.location, isNull, reason: state);
        expect(hidden.hasServerSession, isNull, reason: state);
        expect(hidden.arrivalPendingConfirmation, isFalse, reason: state);
        expect(hidden.arrivalTargetCode, isNull, reason: state);
        expect(hidden.shipLabels, isEmpty, reason: state);
        expect(hidden.locationLabels, isEmpty, reason: state);
        expect(hidden.arrivalTargetLabels, isEmpty, reason: state);
        expect(hidden.locationConfidence, isNull, reason: state);
        expect(hidden.locationHiddenReason, isNull, reason: state);
        expect(hidden.lastUpdated, isNull, reason: state);
        expect(CommunityOnlineMembersController.visibleOnline(hidden), isFalse);
        final actual = organizationMemberPresentation(hidden, null, 'profile');
        expect(resolvedMenuCopy(actual.row), resolvedMenuCopy(expected.row), reason: state);
        expect(resolvedMenuCopy(actual.presentation), resolvedMenuCopy(expected.presentation), reason: state);
      }
    },
  );

  test(
    'offline projection retains validation and leaves caller input intact',
    () {
      final row = Map<String, Object?>.from(
        (workspacePayload()['members'] as List).single as Map,
      )..addAll({'liveStatus': 'Paused', 'ship': 'Private ship'});
      final original = Map<String, Object?>.from(row);
      CommunityWorkspaceMember.parse(row);
      expect(row, original);
      for (final entry in <String, Object?>{
        'online': 'true',
        'arrivalPendingConfirmation': 'false',
        'serverRegion': 4,
        'ship': 4,
        'location': 4,
      }.entries) {
        expect(
          () =>
              CommunityWorkspaceMember.parse({...row, entry.key: entry.value}),
          throwsFormatException,
          reason: entry.key,
        );
      }
    },
  );

  for (var language = 0; language < 3; language++) {
    test('WPF session matrix, privacy and placeholders locale $language', () {
      String text(String key) {
        final value = communityWorkspaceCopy[key]!;
        return [value.$1, value.$2, value.$3][language];
      }

      ({String server, String ship, String location}) render(
        Map<String, Object?> overrides,
      ) {
        final payload = workspacePayload();
        final row = (payload['members'] as List).single as Map<String, Object?>;
        row.addAll({
          'ship': 'Unknown',
          'location': 'Unknown',
          'arrivalPendingConfirmation': false,
          'arrivalTargetCode': null,
          ...overrides,
        });
        return communityMemberRuntime(
          CommunityWorkspaceMember.parse(row),
          text: text,
          regionText: (value) => value,
        );
      }

      for (final state in ['Offline', 'AppOnline', 'Away']) {
        final values = render({'liveStatus': state});
        expect(
          (values.server, values.ship, values.location),
          (text('notInGame'), text('notInGame'), text('notInGame')),
        );
      }
      final noSession = render({'hasServerSession': false});
      expect(
        (noSession.server, noSession.ship, noSession.location),
        (text('notInServer'), text('notInServer'), text('notInServer')),
      );
      expect(render({}).ship, text('waitingRecognition'));
      expect(render({'serverRegion': null}).ship, text('waitingServerSync'));
      expect(
        render({'serverRegion': 'Unknown'}).server,
        text('waitingServerSync'),
        reason:
            'Approved difference from 0.7.1: explain missing server, never —.',
      );
      expect(render({'ship': '  C2 Hercules  '}).ship, 'C2 Hercules');
      expect(render({'ship': null}).ship, text('hidden'));
      expect(
        render({'locationHiddenReason': 'lowConfidence'}).location,
        text('lowConfidenceLocation'),
      );
      expect(
        render({'locationHiddenReason': 'lowConfidence', 'location': null})
            .location,
        text('hidden'),
      );
      expect(
        render({'locationHiddenReason': 'lowConfidence', 'location': 'Orison'})
            .location,
        'Orison',
      );
      expect(
        render({
          'locationHiddenReason': 'lowConfidence',
          'arrivalPendingConfirmation': true,
        }).location,
        text('locationPending'),
      );
      expect(
        render({'locationHiddenReason': 'other'}).location,
        text('waitingRecognition'),
      );
      expect(
        render({'liveStatus': 'Paused', 'ship': 'C2 Hercules'}).ship,
        text('notInGame'),
      );
      expect(
        render({'arrivalPendingConfirmation': true}).location,
        text('locationPending'),
      );
      for (final placeholder in [
        'unknown',
        'NONE',
        'N/A',
        '未知',
        '未进入服务器',
        '等待识别',
      ]) {
        expect(render({'ship': placeholder}).ship, text('waitingRecognition'));
      }
    });
  }
}
