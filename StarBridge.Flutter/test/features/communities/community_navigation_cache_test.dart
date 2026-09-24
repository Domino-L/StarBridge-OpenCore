import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';
import 'package:starbridge_flutter/features/communities/communities_feature.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';

import '../friends/social_layout_test.dart' show app;
import '../friends/friends_navigation_cache_test.dart' show CountingFriends;
import 'community_workspace_test.dart' show WorkspaceTestPort, workspacePayload;

const card = CommunityCard(
  targetRef: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  organizationRef: 'organization-a',
  name: 'Organization A',
  relationship: 'member',
);

class NavigationPort extends WorkspaceTestPort implements CommunitiesPort {
  int directoryReads = 0;
  Completer<CommunityDirectory>? directoryRead;
  Completer<String>? command;
  int writes = 0;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    directoryReads++;
    return directoryRead?.future ?? CommunityDirectory(view, query, [card]);
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    writes++;
    return command?.future ?? 'accepted';
  }

  @override
  Future<void> close() => changes.close();
}

void main() {
  test(
    'idle speculation never evicts a foreground workspace at capacity',
    () async {
      final port = NavigationPort();
      final session = CommunityWorkspaceSession(capacity: 1);
      addTearDown(session.clear);
      addTearDown(port.close);
      final current = session.obtain(port, card.targetRef, card.key);
      await current.enter(card.targetRef);
      final snapshot = current.workspace;
      await session.prefetch(port, 'b' * 32, 'organization-b');
      expect(current.workspace, same(snapshot));
      expect(
        await session.prepareNext(port, 'b' * 32, 'organization-b', 'en-US'),
        false,
      );
      expect(session.obtain(port, card.targetRef, card.key), same(current));
    },
  );
  test('idle prefetch retains a second organization without replacing the current one', () async {
    final port = NavigationPort();
    final session = CommunityWorkspaceSession();
    addTearDown(session.clear);
    addTearDown(port.close);
    var reads = 0;
    port.reader = (target, query, offset) async {
      reads++;
      return CommunityWorkspace.parse(
        workspacePayload(target: target, query: query),
      );
    };
    final current = session.obtain(port, card.targetRef, card.key);
    await current.enter(card.targetRef);
    current.selectedSection = 'manage';
    await session.prefetch(port, 'b' * 32, 'organization-b');
    expect(reads, 2);
    expect(current.selectedSection, 'manage');
    final second = session.obtain(port, 'b' * 32, 'organization-b');
    expect(second.workspace, isNotNull);
    await second.enter('b' * 32);
    expect(reads, 2);
    expect(session.obtain(port, card.targetRef, card.key), same(current));
  });
  test(
    'authoritative readback resolves an uncertain join without a second write',
    () async {
      const target = CommunityCard(
        targetRef: 'before',
        organizationRef: 'new-org',
        name: 'Target',
        actions: ['join'],
      );
      const confirmed = CommunityCard(
        targetRef: 'after',
        organizationRef: 'new-org',
        name: 'Target',
        relationship: 'member',
      );
      final port = NavigationPort()
        ..command = Completer<String>()
        ..directoryRead = (Completer<CommunityDirectory>()
          ..complete(const CommunityDirectory('discover', '', [target])));
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      await module.refresh(newView: 'discover');
      final readback = Completer<CommunityDirectory>();
      port.directoryRead = readback;
      final sending = module.execute(target, 'join');
      port.command!.complete('unknown');
      await Future<void>.delayed(Duration.zero);
      expect(module.message, 'outcomeUnknown');
      readback.complete(const CommunityDirectory('discover', '', [confirmed]));
      await sending;
      expect(module.message, 'done.join');
      expect(module.joined.single.key, 'new-org');
      expect(port.writes, 1);
    },
  );
  test('uncertain join retains directory while readback is pending', () async {
    final port = NavigationPort()..command = Completer<String>();
    final module = CommunitiesModule(port);
    addTearDown(module.dispose);
    await module.refresh(newView: 'discover');
    final visible = module.directory;
    const target = CommunityCard(
      targetRef: 'target',
      name: 'Target',
      actions: ['join'],
    );
    final pendingRead = Completer<CommunityDirectory>();
    port.directoryRead = pendingRead;
    final writing = module.execute(target, 'join');
    port.command!.complete('unknown');
    await Future<void>.delayed(Duration.zero);
    expect(module.message, 'outcomeUnknown');
    expect(
      port.directoryReads,
      3,
      reason: 'Sidebar readback starts before discovery finishes',
    );
    expect(module.canExecute(target), false);
    await module.execute(target, 'join');
    expect(port.writes, 1);
    expect(
      module.directory,
      same(visible),
      reason: 'Uncertain outcome must not blank the directory',
    );
    pendingRead.complete(const CommunityDirectory('discover', '', [card]));
    await writing;
    expect(port.writes, 1);
  });
  testWidgets('signed-in home prepares discovery without navigation or hover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = NavigationPort();
    final friends = CountingFriends();
    final composition = AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
      accountPort: InMemoryAccountAdapter.forReview(
        AccountReviewState.signedIn,
      ),
      communitiesPortFactory: () => port,
      friendsPortFactory: () => friends,
    );
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(composition.communities.directory?.view, 'discover');
    expect(friends.reads, 1);
    await composition.friends.enter();
    expect(
      friends.reads,
      1,
      reason: 'Navigation consumes the prepared snapshot.',
    );
    expect(composition.communities.selected, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'workspace preparation shares membership read and prepares its logo',
    () async {
      final port = NavigationPort()
        ..directoryRead = Completer<CommunityDirectory>();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      var metadata = 0, media = 0;
      port.reader = (target, query, offset) async {
        metadata++;
        return CommunityWorkspace.parse(
          workspacePayload(target: target)..['hasLogo'] = true,
        );
      };
      port.mediaReader = (_, _) async {
        media++;
        throw const CommunityFailure('unavailable');
      };
      final sidebar = module.refreshJoined();
      final preparing = module.prefetchWorkspace();
      expect(port.directoryReads, 1);
      port.directoryRead!.complete(
        const CommunityDirectory('mine', '', [card]),
      );
      await sidebar;
      await preparing;
      expect(metadata, 1);
      expect(media, 1);
      expect(
        module.selected,
        isNull,
        reason: 'Preparation must never navigate.',
      );
      final model = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      expect(model.workspace, isNotNull);
      await model.enter(card.targetRef);
      expect(metadata, 1);
      expect(media, 1);
      await model.enter(card.targetRef);
      expect(
        media,
        1,
        reason: 'Fresh revisits must not repeatedly load media.',
      );
    },
  );

  test(
    'late speculative workspace cannot survive account invalidation',
    () async {
      final port = NavigationPort();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => pending.future;
      await module.refreshJoined();
      final preparing = module.prefetchWorkspace();
      final old = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      port.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      pending.complete(CommunityWorkspace.parse(workspacePayload()));
      await preparing;
      expect(old.workspace, isNull);
      final fresh = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      expect(fresh, isNot(same(old)));
      expect(fresh.workspace, isNull);
    },
  );
  test('pending mutation remains guarded and retires older reads', () async {
    final oldRead = Completer<CommunityDirectory>();
    final port = NavigationPort()
      ..directoryRead = oldRead
      ..command = Completer<String>();
    final module = CommunitiesModule(port);
    addTearDown(module.dispose);
    const target = CommunityCard(
      targetRef: 'target',
      name: 'Example',
      actions: ['join'],
    );
    final reading = module.refresh(newView: 'discover');
    final writing = module.execute(target, 'join');
    await module.execute(target, 'join');
    await module.openJoined(card);
    expect(module.writing, true);
    expect(module.selected, isNull);
    expect(port.writes, 1);
    oldRead.complete(const CommunityDirectory('discover', '', [target]));
    await reading;
    expect(module.directory, isNull);
    port.directoryRead = null;
    port.command!.complete('accepted');
    await writing;
    expect(module.writing, false);
    expect(module.directory?.items, [card]);
  });

  test(
    'invalidation retires a pending prefetch and denied leave is respected',
    () async {
      final pending = Completer<CommunityDirectory>();
      final port = NavigationPort()..directoryRead = pending;
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      final warming = module.prefetch();
      module.confirmWorkspaceLeave = () async => false;
      await module.openJoined(card);
      expect(module.selected, isNull);
      port.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      pending.complete(const CommunityDirectory('discover', '', [card]));
      await warming;
      expect(module.directory, isNull);
      expect(module.busy, false);
    },
  );

  testWidgets(
    'real shell can leave a cold community read for settings immediately',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = NavigationPort();
      final composition = AppComposition.forTest(
        windowChrome: InMemoryWindowChrome(),
        communitiesPortFactory: () => port,
      );
      await tester.pumpWidget(StarBridgeApp(composition: composition));
      await tester.pumpAndSettle();
      port.directoryRead = Completer<CommunityDirectory>();
      await tester.tap(find.byKey(const ValueKey('/communities')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(composition.communities.busy, true);
      await tester.tap(find.byKey(const ValueKey('/settings')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SettingsPage), findsOneWidget);
      port.directoryRead!.complete(
        const CommunityDirectory('discover', '', []),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'prefetch and entry share one pending read without selecting a page',
    () async {
      final port = NavigationPort()
        ..directoryRead = Completer<CommunityDirectory>();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      final warming = module.prefetch();
      await module.openDiscovery();
      await module.prefetch();
      expect(port.directoryReads, 1);
      await module.openJoined(card);
      await module.prefetch();
      expect(module.selected, same(card));
      port.directoryRead!.complete(
        const CommunityDirectory('discover', '', []),
      );
      await warming;
      expect(module.selected, same(card));
    },
  );

  test('cold discovery navigation completes before its network read', () async {
    final port = NavigationPort()
      ..directoryRead = Completer<CommunityDirectory>();
    final module = CommunitiesModule(port);
    addTearDown(module.dispose);
    var navigated = false;
    final navigation = module.openDiscovery().then((_) => navigated = true);
    await Future<void>.delayed(Duration.zero);
    final completedBeforeRead = navigated;
    port.directoryRead!.complete(const CommunityDirectory('discover', '', []));
    await navigation;
    expect(completedBeforeRead, true);
  });

  test(
    'pending directory read does not block joined navigation or overwrite it',
    () async {
      final port = NavigationPort()
        ..directoryRead = Completer<CommunityDirectory>();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      final reading = module.refresh(newView: 'discover');
      await module.openJoined(card);
      final selectedBeforeRead = module.selected;
      port.directoryRead!.complete(
        const CommunityDirectory('discover', '', []),
      );
      await reading;
      expect(selectedBeforeRead, same(card));
      expect(module.selected, same(card));
    },
  );

  test('new search supersedes pending directory read', () async {
    final first = Completer<CommunityDirectory>();
    final port = NavigationPort()..directoryRead = first;
    final module = CommunitiesModule(port);
    addTearDown(module.dispose);
    final reading = module.refresh(newView: 'discover');
    port.directoryRead = null;
    await module.refresh(newQuery: 'Explorer');
    first.complete(const CommunityDirectory('discover', '', []));
    await reading;
    expect(module.query, 'Explorer');
    expect(module.directory?.query, 'Explorer');
  });

  testWidgets(
    'discovery return paints cards while its slow revalidation is pending',
    (tester) async {
      var now = DateTime(2026);
      final port = NavigationPort();
      final module = CommunitiesModule(port, now: () => now);
      addTearDown(module.dispose);
      final feature = createCommunitiesFeature(module: module);
      Widget destination() => app(Builder(builder: feature.buildDestination));
      await module.refresh(newView: 'discover');
      await tester.pumpWidget(destination());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 11));
      port.directoryRead = Completer<CommunityDirectory>();
      await module.openDiscovery();
      await tester.pumpWidget(destination());
      expect(find.text('Organization A'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(module.busy, true);
      port.directoryRead!.complete(CommunityDirectory('discover', '', [card]));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'return to discovery keeps its snapshot while refreshing in background',
    () async {
      var now = DateTime(2026);
      final port = NavigationPort();
      final module = CommunitiesModule(port, now: () => now);
      addTearDown(module.dispose);
      await module.refresh(newView: 'discover', newQuery: 'Explorer');
      final previous = module.directory;
      now = now.add(const Duration(seconds: 11));
      port.directoryRead = Completer<CommunityDirectory>();
      final returning = module.openDiscovery();
      await Future<void>.delayed(Duration.zero);
      expect(module.directory, same(previous));
      expect(module.query, 'Explorer');
      port.directoryRead!.complete(previous!);
      await returning;
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 10; i++) {
        await module.openDiscovery();
      }
      expect(port.directoryReads, 2);
    },
  );
  test(
    'fresh returns deduplicate reads; stale returns and manual refresh update',
    () async {
      var now = DateTime(2026);
      final port = NavigationPort();
      final session = CommunityWorkspaceSession(now: () => now);
      addTearDown(session.clear);
      addTearDown(port.close);
      var reads = 0;
      port.reader = (target, query, offset) async {
        reads++;
        return CommunityWorkspace.parse(
          workspacePayload(target: target, query: query),
        );
      };
      final model = session.obtain(port, card.targetRef, card.key);
      await model.enter(card.targetRef);
      for (var i = 0; i < 10; i++) {
        expect(session.obtain(port, card.targetRef, card.key), same(model));
        await model.enter(card.targetRef);
      }
      expect(reads, 1);
      now = now.add(const Duration(seconds: 11));
      final previous = model.workspace;
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) {
        reads++;
        return pending.future;
      };
      final renewal = model.enter(card.targetRef);
      await model.enter(card.targetRef);
      expect(reads, 2);
      expect(model.workspace, same(previous));
      expect(model.showProgress, false);
      pending.complete(previous!);
      await renewal;
      await model.load();
      expect(
        reads,
        3,
        reason: 'Manual refresh must not reuse the freshness window.',
      );
      now = now.subtract(const Duration(days: 1));
      await model.enter(card.targetRef);
      expect(reads, 4, reason: 'Clock rollback must not retain freshness.');
    },
  );

  test(
    'account change while away clears images and rejects late replies',
    () async {
      final port = NavigationPort();
      final module = CommunitiesModule(port)..open(card);
      addTearDown(module.dispose);
      final old = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      await old.enter(card.targetRef);
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => pending.future;
      final reading = old.load(silent: true);
      port.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(module.selected, isNull);
      expect(old.workspace, isNull);
      pending.complete(CommunityWorkspace.parse(workspacePayload()));
      await reading;
      expect(old.workspace, isNull);
      final fresh = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      expect(fresh, isNot(same(old)));
      expect(fresh.workspace, isNull);
    },
  );

  test(
    'organization round trips retain separate recent state without rereads',
    () async {
      final port = NavigationPort();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.close);
      var reads = 0;
      port.reader = (target, query, offset) async {
        reads++;
        return CommunityWorkspace.parse(
          workspacePayload(target: target, query: query),
        );
      };
      final a = session.obtain(port, card.targetRef, card.key);
      await a.enter(card.targetRef);
      await a.load(search: 'crew-a');
      a.selectedSection = 'ships';
      final snapshotA = a.workspace;
      final b = session.obtain(port, 'b' * 32, 'organization-b');
      await b.enter('b' * 32);
      await b.load(search: 'crew-b');
      b.selectedSection = 'chat';
      final before = reads;
      final returned = session.obtain(port, card.targetRef, card.key);
      expect(returned, same(a));
      expect(returned.workspace, same(snapshotA));
      expect(returned.query, 'crew-a');
      expect(returned.selectedSection, 'ships');
      await returned.enter(card.targetRef);
      expect(reads, before);
      expect(session.obtain(port, 'b' * 32, 'organization-b'), same(b));
      expect(b.query, 'crew-b');
      expect(b.selectedSection, 'chat');
    },
  );

  test(
    'retained organizations cannot cross ports or unknown identity',
    () async {
      final port = NavigationPort(), otherPort = NavigationPort();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.close);
      addTearDown(otherPort.close);
      final a = session.obtain(port, card.targetRef, card.key);
      await a.enter(card.targetRef);
      final b = session.obtain(port, 'c' * 32, 'organization-b');
      expect(a.workspace, isNotNull);
      expect(b.workspace, isNull);
      final other = session.obtain(otherPort, 'c' * 32, 'organization-b');
      expect(a.workspace, isNull);
      expect(other, isNot(same(b)));
      final unknown = session.obtain(otherPort, 'c' * 32, null);
      expect(session.obtain(otherPort, 'c' * 32, null), isNot(same(unknown)));
    },
  );

  test(
    'stale failure retries; access revocation clears retained private content',
    () async {
      var now = DateTime(2026);
      final port = NavigationPort();
      final session = CommunityWorkspaceSession(now: () => now);
      addTearDown(session.clear);
      addTearDown(port.close);
      final model = session.obtain(port, card.targetRef, card.key);
      await model.enter(card.targetRef);
      final previous = model.workspace;
      now = now.add(const Duration(seconds: 11));
      var reads = 0;
      port.reader = (_, _, _) async {
        reads++;
        throw const CommunityFailure('unavailable');
      };
      await model.enter(card.targetRef);
      expect(model.workspace, same(previous));
      await model.enter(card.targetRef);
      expect(reads, 2);
      port.reader = (_, _, _) async =>
          throw const CommunityFailure('notAllowed');
      await model.enter(card.targetRef);
      expect(model.workspace, isNull);
      expect(model.displayMembers, isEmpty);
    },
  );

  test(
    'changed reference on return revalidates before using new access',
    () async {
      final port = NavigationPort();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.close);
      final model = session.obtain(port, card.targetRef, card.key);
      await model.enter(card.targetRef);
      final previous = model.workspace;
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => pending.future;
      final returned = session.obtain(port, 'c' * 32, card.key);
      final renewal = returned.enter('c' * 32);
      expect(returned, same(model));
      expect(model.renewingReference, true);
      expect(model.targetRef, card.targetRef);
      expect(model.workspace, same(previous));
      expect(model.showProgress, false);
      pending.complete(
        CommunityWorkspace.parse(workspacePayload(target: 'c' * 32)),
      );
      await renewal;
      expect(model.targetRef, 'c' * 32);
      expect(model.renewingReference, false);
    },
  );

  testWidgets(
    'return to organization immediately retains members and search without rereading',
    (tester) async {
      final port = NavigationPort();
      final module = CommunitiesModule(port)..open(card);
      addTearDown(module.dispose);
      final feature = createCommunitiesFeature(module: module);
      var reads = 0;
      port.reader = (target, query, offset) async {
        reads++;
        return CommunityWorkspace.parse(
          workspacePayload(target: target, query: query),
        );
      };
      Widget destination() => app(Builder(builder: feature.buildDestination));
      await tester.pumpWidget(destination());
      await tester.pumpAndSettle();
      final state = tester.state<CommunityWorkspaceViewState>(
        find.byType(CommunityWorkspaceView),
      );
      await state.model.load(search: 'Explorer');
      final previous = state.model.workspace;
      final readCount = reads;
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) {
        reads++;
        return pending.future;
      };
      await tester.pumpWidget(destination());
      final returned = tester.state<CommunityWorkspaceViewState>(
        find.byType(CommunityWorkspaceView),
      );
      expect(returned.model.workspace, same(previous));
      expect(returned.search.text, 'Explorer');
      expect(reads, readCount);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete(previous!);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
