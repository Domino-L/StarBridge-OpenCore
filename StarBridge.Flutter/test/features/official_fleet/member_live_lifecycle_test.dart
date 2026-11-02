import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/official_fleet_self_presence_composition.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

import '../settings/local_privacy_page_test.dart' show app, viewport;
import '../settings/official_runtime_privacy_test.dart'
    show OfficialPrivacyFixture;
import 'member_live_refresh_test.dart' show PendingMembers, pilot, source;

void main() {
  test('production binding uses confirmed chrome presence and saved audience, not draft consent', () async {
    final port = PendingMembers();
    final members = createOfficialFleetMembersModule(port);
    final privacyPort = OfficialPrivacyFixture()..savedFields = 1;
    final privacy = LocalPrivacyController(privacyPort);
    final local = ValueNotifier(
      const ManualPresenceSnapshot(
        scope: 'synthetic',
        confirmedMode: PresenceVisibility.online,
        automaticKey: 'presence.online',
      ),
    );
    final presence = ManualPresenceController(source: local);
    bindOfficialFleetSelfPresence(members, presence, privacy);
    addTearDown(() {
      members.dispose();
      presence.dispose();
      local.dispose();
      privacy.dispose();
    });
    await privacy.refresh();
    final opening = members.open(source);
    port.complete(0, [pilot('self')]);
    await opening;
    expect(
      members.projection.value.members.single.publicPresence,
      OfficialFleetMemberPresence.away,
    );
    // This is an in-memory fixture receipt, with no Host or network connection.
    await privacy.applyPublication();
    expect(
      members.projection.value.members.single.publicPresence,
      OfficialFleetMemberPresence.online,
    );
    local.value = const ManualPresenceSnapshot(
      scope: 'synthetic',
      confirmedMode: PresenceVisibility.online,
      automaticKey: 'presence.away',
    );
    expect(
      members.projection.value.members.single.publicPresence,
      OfficialFleetMemberPresence.away,
    );
    local.value = const ManualPresenceSnapshot(
      scope: 'synthetic',
      confirmedMode: PresenceVisibility.online,
      automaticKey: 'presence.online',
    );
    expect(
      members.projection.value.members.single.publicPresence,
      OfficialFleetMemberPresence.online,
    );
    privacy.publicationView = PrivacyPublicationView(
      'withdrawn',
      revision: privacy.revision,
    );
    local.value = const ManualPresenceSnapshot(
      scope: 'synthetic',
      confirmedMode: PresenceVisibility.online,
      automaticKey: 'presence.online',
      hasRealtimeAuthority: true,
      realtimeStatus: 1,
    );
    expect(
      members.projection.value.members.single.publicPresence,
      OfficialFleetMemberPresence.offline,
    );
    privacyPort.savedFields = 0;
    await privacy.refresh();
    privacy.editOfficialFields(1);
    expect(
      members.projection.value.members.single.publicPresence,
      OfficialFleetMemberPresence.offline,
    );
    expect(port.reads, hasLength(1));
  });

  testWidgets(
    'five-minute fallback is silent, pauses offstage and retires on dispose',
    (tester) async {
      viewport(tester, const Size(1400, 1000));
      final port = PendingMembers();
      final module = createOfficialFleetModule(
        InMemoryOfficialFleetAdapter.forReview(signedIn: true),
        UnavailableOfficialFleetOverviewAdapter(),
        port,
        UnavailableOfficialFleetShipsAdapter(),
      );
      addTearDown(module.dispose);
      await module.initialize();
      port.complete(0, [pilot('self')]);
      await tester.pump();
      Widget surface(bool visible) => app(
        TickerMode(
          enabled: visible,
          child: OfficialFleetPage(module: module),
        ),
      );
      await tester.pumpWidget(surface(true));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 5));
      expect(port.reads, hasLength(2));
      expect(module.members.projection.value.isRefreshing, isFalse);
      expect(find.textContaining('正在更新成员'), findsNothing);
      port.complete(1, [pilot('self')]);
      await tester.pump();
      await tester.pumpWidget(surface(false));
      await tester.pump(const Duration(minutes: 10));
      expect(port.reads, hasLength(2));
      await tester.pumpWidget(surface(true));
      await tester.pump(const Duration(minutes: 5));
      expect(port.reads, hasLength(3));
      port.complete(2, [pilot('self')]);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 10));
      expect(port.reads, hasLength(3));
    },
  );
}
