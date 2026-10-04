import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_overview_reader.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_reads.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_community_workspace.dart';

import 'menu_channel_media_session_test.dart' show PhotoPort;

class OverviewPort extends PhotoPort {
  @override
  CommunityCard get card => CommunityCard(
    targetRef: 'a' * 32,
    organizationRef: 'org-fixture',
    name: 'Fixture',
    relationship: 'member',
    memberCount: 3,
  );
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
    await super.close();
  }
}

class RenewingOverviewPort extends OverviewPort {
  int renewal = 0;
  @override
  CommunityCard get card => CommunityCard(
    targetRef: (renewal == 0 ? 'a' : 'b') * 32,
    organizationRef: 'org-fixture',
    name: 'Fixture',
    relationship: 'member',
  );
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async {
    final snapshot = card;
    workspaceReads++;
    await workspaceGate.future;
    return exampleCommunityWorkspace(snapshot, query, offset);
  }
}

CommunitiesModule moduleFor(OverviewPort port) => CommunitiesModule(port)
  ..joined = [port.card]
  ..joinedLoaded = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'main directory reference renewal during overview is not membership loss',
    () async {
      final main = RenewingOverviewPort();
      final module = moduleFor(main);
      addTearDown(module.dispose);
      final reading = CommunityOverviewReader(module).read('org-fixture');
      await Future<void>.delayed(Duration.zero);
      main.renewal++;
      module.joined = [main.card];
      main.workspaceGate.complete();
      final result = await reading;
      expect(result, isNotNull);
      expect(result!.targetRef, main.card.targetRef);
    },
  );
  test(
    'menu first paint reuses main prefetch with zero menu workspace reads',
    () async {
      final main = OverviewPort()..workspaceGate.complete();
      final module = moduleFor(main);
      addTearDown(module.dispose);
      await module.workspaceSession.prefetch(
        main,
        main.card.targetRef,
        main.card.organizationRef!,
      );
      final menu = OverviewPort();
      final ready = Completer<Map>();
      final session = MenuOrganizationsSession(menu, (view) {
        if (view['state'] == 'ready' &&
            (view['organization'] as Map?)?['tab'] == 'chat' &&
            !ready.isCompleted) {
          ready.complete(view['organization'] as Map);
        }
      }, overview: CommunityOverviewReader(module));
      session.show(true);
      final org = await ready.future.timeout(const Duration(seconds: 3));
      expect((org['overview'] as Map)['online'], 3);
      expect(main.workspaceReads, 1);
      expect(menu.workspaceReads, 0);
      session.dispose();
      expect(main.closes, 0);
    },
  );

  test(
    'pending main prefetch and menu join one read without blocking chat',
    () async {
      final main = OverviewPort(), menu = OverviewPort();
      final module = moduleFor(main);
      addTearDown(module.dispose);
      final warming = module.workspaceSession.prefetch(
        main,
        main.card.targetRef,
        main.card.organizationRef!,
      );
      final chat = Completer<void>();
      final session = MenuOrganizationsSession(menu, (view) {
        if (view['state'] == 'ready' &&
            (view['organization'] as Map?)?['tab'] == 'chat' &&
            !chat.isCompleted) {
          chat.complete();
        }
      }, overview: CommunityOverviewReader(module));
      addTearDown(session.dispose);
      session.show(true);
      await chat.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(main.workspaceReads, 1);
      expect(menu.workspaceReads, 0);
      main.workspaceGate.complete();
      await warming;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        ((session.currentView['organization'] as Map)['overview']
            as Map)['online'],
        3,
      );
      expect(main.workspaceReads, 1);
    },
  );

  test(
    'overview fallback leaves main search section and pagination untouched',
    () async {
      final main = OverviewPort()..workspaceGate.complete();
      final module = moduleFor(main);
      addTearDown(module.dispose);
      final model = module.workspaceSession.obtain(
        main,
        main.card.targetRef,
        main.card.organizationRef,
      );
      await model.load(search: 'Example', offset: 20);
      final original = model.workspace;
      final section = model.selectedSection;
      var changes = 0;
      model.addListener(() {
        changes++;
      });
      final value = await CommunityOverviewReader(module)
          .read(main.card.organizationRef!);
      expect(value!.query, '');
      expect(value.offset, 0);
      expect(model.workspace, same(original));
      expect(model.query, 'Example');
      expect(model.selectedSection, section);
      expect(changes, 0);
      expect(main.workspaceReads, 2);
    },
  );

  test('clearing owner rejects late reads and never caches them', () async {
    final main = OverviewPort();
    final session = CommunityWorkspaceSession();
    final reading = session.reads.read(
      main,
      main.card.targetRef,
      '',
      0,
      reuseFresh: true,
    );
    final check = expectLater(reading, throwsA(isA<CommunityFailure>()));
    session.clear();
    main.workspaceGate.complete();
    await check;
    expect(session.reads.peek(main, main.card.targetRef), isNull);
  });

  test(
    'expired snapshot revalidates and different owner cannot inherit it',
    () async {
      var now = DateTime(2026);
      final reads = CommunityWorkspaceReads(() => now);
      final main = OverviewPort()..workspaceGate.complete();
      await reads.read(main, main.card.targetRef, '', 0, reuseFresh: true);
      await reads.read(main, main.card.targetRef, '', 0, reuseFresh: true);
      expect(main.workspaceReads, 1);
      expect(reads.peek(OverviewPort(), main.card.targetRef), isNull);
      now = now.add(const Duration(seconds: 11));
      expect(reads.peek(main, main.card.targetRef), isNull);
      await reads.read(main, main.card.targetRef, '', 0, reuseFresh: true);
      expect(main.workspaceReads, 2);
    },
  );
}
