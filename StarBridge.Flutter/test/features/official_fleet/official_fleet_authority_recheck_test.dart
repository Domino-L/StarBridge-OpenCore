// Enabling management changes what the page offers without a restart (user
// 2026-10-31), and the compact header never prints a literal null.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_port.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_session.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_outcomes_controller.dart';
import 'package:starbridge_flutter/features/common/organization_communication.dart';
import 'package:starbridge_flutter/features/common/organization_holo_deck.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_management.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_activity_section.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_workspace_header.dart';

import '../common/organization_announcement_management_session_test.dart'
    show FixtureManagementPort;
import '../communities/community_announcements_controller_test.dart'
    show AnnouncementsFake;
import '../communities/community_announcements_test.dart'
    show announcementAuthor, announcementRow;
import '../friends/social_layout_test.dart' show app, loadFonts;

final class _Rally implements OfficialFleetRallyPort {
  bool canStart = false, failEligibility = false;
  int eligibilityReads = 0, onlineCount = 1;
  @override
  bool get available => true;
  @override
  Future<OfficialFleetRallySnapshot> read(
    String sourceRef, {
    required bool online,
  }) async => OfficialFleetRallySnapshot(onlineCount: onlineCount, rally: null);
  @override
  Future<OfficialFleetRallyEligibility> eligibility(String sourceRef) async {
    eligibilityReads++;
    if (failEligibility) throw const OfficialFleetRallyFailure('unavailable');
    return OfficialFleetRallyEligibility(
      canStart: canStart,
      onlineCount: 1,
      remainingThisHour: canStart ? 2 : 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Editor extends FixtureManagementPort {
  _Editor(this.reads);
  final AnnouncementsFake reads;
  bool refused = true;
  @override
  Future<OrganizationAnnouncementEditor> readEditor(String sourceRef) async {
    editorReads++;
    if (refused) throw const CommunityFailure('notAllowed');
    return OrganizationAnnouncementEditor.parse({
      'schemaVersion': 1,
      'state': 'available',
      'sourceRef': sourceRef,
      'editRef': 'e' * 32,
      'revision': reads.revision,
      'allowedActions': const ['publish'],
      'current': null,
    }, sourceRef);
  }
}

void main() {
  setUpAll(loadFonts);

  group('rally eligibility', () {
    late _Rally port;
    late OfficialFleetRallyController rally;
    setUp(() async {
      port = _Rally();
      rally = OfficialFleetRallyController(port, countedOnline: () => true);
      addTearDown(rally.dispose);
      rally.bind('officialFleet:7');
      await pumpEventQueue();
    });

    test('asking again after enabling opens the rally at once', () async {
      expect(rally.canStart, isFalse);
      port.canStart = true;
      await rally.refresh(eligibility: true);
      expect(rally.canStart, isTrue);
    });

    test('a question asked during another read is answered right after', () async {
      final reads = port.eligibilityReads;
      port.canStart = true;
      final running = rally.refresh();
      await rally.refresh(eligibility: true);
      await running;
      await pumpEventQueue();
      expect(port.eligibilityReads, reads + 1);
      expect(rally.canStart, isTrue);
    });

    test('revoking closes the rally section even with one running', () async {
      port.canStart = true;
      await rally.refresh(eligibility: true);
      expect(rally.canStart, isTrue);
      port.canStart = false;
      await rally.refresh(eligibility: true);
      expect(rally.canStart, isFalse);
    });

    test('a failing question does not stop the board updating', () async {
      expect(rally.snapshot!.onlineCount, 1);
      port
        ..failEligibility = true
        ..onlineCount = 5;
      await rally.refresh(eligibility: true);
      expect(rally.snapshot!.onlineCount, 5);
      port.onlineCount = 6;
      await rally.refresh();
      expect(rally.snapshot!.onlineCount, 6);
    });

    test('rights never answered keep the first board back', () async {
      final fresh = OfficialFleetRallyController(
        port..failEligibility = true,
        countedOnline: () => true,
      );
      addTearDown(fresh.dispose);
      fresh.bind('officialFleet:8');
      await pumpEventQueue();
      expect(fresh.snapshot, isNull);
    });

    test('a failed question is asked once more by the next read', () async {
      port
        ..canStart = true
        ..failEligibility = true;
      await rally.refresh(eligibility: true);
      expect(rally.canStart, isFalse);
      port.failEligibility = false;
      await rally.refresh();
      expect(rally.canStart, isTrue);
      final reads = port.eligibilityReads;
      await rally.refresh();
      expect(port.eligibilityReads, reads);
    });
  });

  group('announcement management', () {
    late AnnouncementsFake reads;
    late _Editor port;
    late CommunityAnnouncementsController model;
    setUp(() async {
      reads = AnnouncementsFake()
        ..allowed = false
        ..revision = 0
        ..current = null;
      port = _Editor(reads);
      final outcomes = OrganizationAnnouncementOutcomesController(port);
      final session = OrganizationAnnouncementManagementSession(
        port,
        'officialFleet:7',
        outcomes: outcomes,
      );
      model = CommunityAnnouncementsController(
        reads,
        'a' * 32,
        management: session,
      );
      addTearDown(model.dispose);
      addTearDown(session.dispose);
      addTearDown(outcomes.dispose);
      addTearDown(port.close);
      addTearDown(reads.changes.close);
      await model.enter();
      await model.prepareManagementIfNeeded();
    });

    test('a refusal is remembered only until the relay says otherwise', () async {
      expect(model.showManagementActions, isFalse);
      final refused = port.editorReads;
      await model.prepareManagementIfNeeded();
      expect(port.editorReads, refused);
      port.refused = false;
      await model.recheckManagement(allowed: true);
      expect(port.editorReads, refused + 1);
      expect(model.showManagementActions, isTrue);
    });

    test('still refused means no extra read for each visit', () async {
      final refused = port.editorReads;
      await model.recheckManagement(allowed: false);
      expect(port.editorReads, refused);
      expect(model.showManagementActions, isFalse);
    });

    test('the section stays while its reads run, and goes when refused', () async {
      expect(model.managementGranted, isFalse);
      port.refused = false;
      await model.recheckManagement(allowed: true);
      expect(model.managementGranted, isTrue);
      // Opening the section reads the list and the editor again.
      final hold = model.prepareManagement();
      expect(model.showManagementActions, isFalse);
      expect(model.managementGranted, isTrue);
      await hold;
      expect(model.managementGranted, isTrue);
      expect(model.showManagementActions, isTrue);
      port.refused = true;
      await model.recheckManagement(allowed: false);
      expect(model.managementGranted, isFalse);
      expect(model.showManagementActions, isFalse);
    });

    test('a refused detail read ends the section', () async {
      reads.current = announcementRow()
        ..['author'] = announcementAuthor(hasAvatar: false)
        ..['editor'] = announcementAuthor(hasAvatar: false);
      reads.revision = 30;
      await model.refresh();
      expect(model.error, isNull);
      expect(model.page!.current, isNotNull);
      port.refused = false;
      await model.recheckManagement(allowed: true);
      expect(model.managementGranted, isTrue);
      reads.detailFailure = 'notAllowed';
      await model.detail(model.page!.current!).then<void>((_) {}, onError: (_) {});
      expect(model.managementGranted, isFalse);
    });

    test('revoking takes the actions away', () async {
      port.refused = false;
      await model.recheckManagement(allowed: true);
      expect(model.showManagementActions, isTrue);
      port.refused = true;
      await model.recheckManagement(allowed: false);
      expect(model.showManagementActions, isFalse);
    });

    test('an aligned editor is not read again', () async {
      port.refused = false;
      await model.recheckManagement(allowed: true);
      final aligned = port.editorReads;
      await model.recheckManagement(allowed: true);
      expect(port.editorReads, aligned);
    });
  });

  testWidgets('an unknown count is a dash in the compact header', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: SizedBox(
            width: 1400,
            child: OfficialFleetHoloBar(
              deck: OrganizationHoloDeck(
                name: 'Fleet',
                code: 'F',
                stats: [
                  OrganizationHoloStat('官网成员', 2),
                  OrganizationHoloStat('可见在线', null),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('null', findRichText: true), findsNothing);
    expect(find.textContaining('— ', findRichText: true), findsOneWidget);
    expect(find.textContaining('2 ', findRichText: true), findsOneWidget);
  });

  testWidgets('announcement results stay where announcements are', (
    tester,
  ) async {
    final communication = OrganizationCommunication(
      (_) => throw UnimplementedError(),
    );
    addTearDown(communication.dispose);
    for (final section in OfficialFleetWorkspaceSection.values) {
      final widget = officialFleetAnnouncementOutcomesFor(
        communication,
        section,
      );
      expect(
        widget is SizedBox,
        !const {
          OfficialFleetWorkspaceSection.broadcasts,
          OfficialFleetWorkspaceSection.manage,
        }.contains(section),
        reason: section.name,
      );
    }
  });
}
