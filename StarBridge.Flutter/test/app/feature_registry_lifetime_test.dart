import 'package:starbridge_flutter/features/common/organization_communication.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_announcement_management.dart';

import '../features/communities/bridge_communities_test.dart'
    show CommunityHarness;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';

void main() {
  test('official management configures once and outlives workspace without closing borrowed transport', () async {
    final host = CommunityHarness(
      capabilities: [
        'officialFleet.readAnnouncementEditor',
        'officialFleet.manageAnnouncements',
        'officialFleet.readAnnouncementOutcome',
      ],
    );
    addTearDown(host.close);
    final communication = OrganizationCommunication(null);
    var created = 0;
    void configure() => communication.configureAnnouncementManagement(
      owner: host.adapter,
      create: () {
        created++;
        return BridgeOfficialFleetAnnouncementManagement(host.adapter);
      },
    );
    configure();
    final outcomes = communication.announcementOutcomes;
    configure();
    expect(created, 1);
    communication.retainReadOnly();
    communication.reset();
    expect(communication.announcementOutcomes, same(outcomes));
    expect(host.adapter.isClosed, isFalse);
    communication.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(host.adapter.isClosed, isFalse);
  });
  test('feature resources survive navigation queries and retire once with registry', () {
    var disposed = 0;
    final feature = FeatureDescriptor(
      id: 'home',
      route: '/',
      labelKey: 'home',
      descriptionKey: 'home',
      icon: StarBridgeIconSemantic.home,
      navigationRegion: NavigationRegion.brand,
      order: 0,
      buildDestination: (_) => const SizedBox.shrink(),
      onDispose: () => disposed++,
    );
    final registry = FeatureRegistry([feature]);
    expect(registry.home, same(feature));
    registry.byRoute('/');
    registry.inRegion(NavigationRegion.brand);
    expect(disposed, 0);
    registry.dispose();
    registry.dispose();
    expect(disposed, 1);
  });
}
