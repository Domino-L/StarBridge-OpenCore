import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_views.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import '../friends/social_layout_test.dart' show app, loadFonts;

const _image =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
final _reference = 'a' * 64;
const _query = OfficialFleetMemberDirectoryQuery(sourceRef: 'officialFleet:7');

Map<String, Object?> _row(String state, {Object? isSelf}) => {
  'memberRef': _reference,
  'callsign': state == 'starBridge' ? 'StarBridge pilot' : 'SCM pilot',
  'officialRankName': 'Member',
  'officialRankValue': null,
  'presence': 'unknown',
  'starBridgeConnected': state == 'starBridge' ? true : null,
  'identityState': state,
  if (state == 'starBridge') ...{
    'avatarImageData': _image,
    'profileTargetRef': _reference,
  },
  'isSelf': ?isSelf,
};

OfficialFleetMember _member(Map<String, Object?> row) =>
    parseOfficialFleetMembers({
      'schemaVersion': 1,
      'sourceRef': _query.sourceRef,
      'search': _query.search,
      'filter': 'all',
      'pageNumber': _query.pageNumber,
      'pageSize': _query.pageSize,
      'totalCount': 1,
      'totalPages': 1,
      'coverage': 'scmRegisteredMembers',
      'onlineCount': null,
      'inGameCount': null,
      'members': [row],
    }, _query).members.single;

void main() {
  setUpAll(loadFonts);

  test('only a linked row may carry the Host self marker', () {
    expect(_member(_row('starBridge', isSelf: true)).isSelf, isTrue);
    expect(_member(_row('starBridge')).isSelf, isFalse);
    for (final row in [
      _row('starBridge', isSelf: false),
      _row('starBridge', isSelf: 'true'),
      _row('scm', isSelf: true),
      _row('restricted', isSelf: true),
    ]) {
      expect(() => _member(row), throwsA(isA<BridgeFormatException>()));
    }
  });

  for (final self in [true, false]) {
    testWidgets(
      '${self ? 'own' : 'other'} linked row offers ${self ? 'the own personal page' : 'only the visitor profile'}',
      (tester) async {
        var selfOpened = 0, visitorOpened = 0;
        final navigation = UserPageNavigation()
          ..open = (context, builder, _) async {
            visitorOpened++;
          }
          ..openSelf = (context) async {
            selfOpened++;
          };
        await tester.pumpWidget(
          app(
            UserInteractionScope(
              navigation: navigation,
              port: null,
              messagePage: null,
              child: SizedBox(
                width: 320,
                child: OfficialFleetMemberRow(
                  member: _member(
                    _row('starBridge', isSelf: self ? true : null),
                  ),
                  wide: false,
                  onOpen: () => fail('The complete row must not be clickable'),
                  sourceRef: _query.sourceRef,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<UserAvatarMenu>(find.byType(UserAvatarMenu)).isSelf,
          self,
        );
        await tester.tap(find.textContaining('StarBridge pilot'));
        await tester.pumpAndSettle();
        if (self) {
          await tester.tap(find.text('个人页面'));
          await tester.pumpAndSettle();
        } else {
          // The visitor read itself is covered by the member identity tests.
          expect(find.text('个人页面'), findsNothing);
          expect(find.text('查看资料'), findsOneWidget);
        }
        expect(selfOpened, self ? 1 : 0);
        expect(visitorOpened, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
