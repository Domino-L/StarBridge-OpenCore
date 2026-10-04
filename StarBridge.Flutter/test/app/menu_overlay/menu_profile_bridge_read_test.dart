import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profiles_session.dart';
import 'package:starbridge_flutter/features/common/bridge_user_interaction.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/platform/window/menu_profile_navigation.dart';

import '../../features/communities/bridge_communities_test.dart'
    show CommunityHarness;
import '../../features/communities/community_visitor_profile_test.dart'
    show visitorPayload;

void main() {
  test('visitor hidden and unplaced modules display in both clients', () {
    final payload = <String, Object?>{
      ...visitorPayload,
      'profile': {
        ...(visitorPayload['profile'] as Map),
        'content': {
          'modules': [
            {'id': 'overview', 'span': 2, 'isVisible': true},
            {
              'id': 'hangarSummary',
              'span': 1,
              'isVisible': false,
              'position': -1,
            },
          ],
        },
      },
    };
    final client = parsePersonalProfileSnapshot(payload);
    expect(client.moduleLayout.first.position, -1);
    final menu = MenuProfileView.parse(MenuProfileView.encode(client));
    expect(menu.state, 'ready');
    expect(menu.snapshot!.moduleLayout.first.position, -1);
    expect(menu.snapshot!.moduleLayout.last.isVisible, false);
    final encoded = MenuProfileView.encode(client);
    (encoded['modules'] as List).first['position'] = -2;
    expect(MenuProfileView.parse(encoded).state, 'unavailable');
  });
  testWidgets('authorized visitor bridge response survives menu projection', (
    tester,
  ) async {
    final host = CommunityHarness(
      legacy: true,
      capabilities: ['users.interaction'],
      responses: {'users.profile': visitorPayload},
    );
    addTearDown(host.close);
    final views = <Map<String, Object?>>[];
    final session = MenuProfilesSession(
      () => BridgeUserInteraction(host.session),
      views.add,
    );
    session.open(
      'visitor',
      MenuProfileTarget(
        source: 'conversation',
        reference: 'a' * 32,
        query: '',
        isCurrent: () => true,
        isAccountCurrent: () => true,
      ),
    );
    await tester.pumpAndSettle();
    expect(views.last['state'], 'ready');
    expect(views.last['name'], 'Visitor Pilot');
    session.dispose();
    await tester.pump();
  });
}
