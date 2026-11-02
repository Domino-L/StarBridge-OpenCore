import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';

const source = 'officialFleet:7';

OfficialFleetMember pilot(
  String ref, {
  String name = 'Pilot',
  bool sharingPaused = false,
}) => OfficialFleetMember(
  memberRef: ref,
  callsign: name,
  gameId: '',
  officialRankName: null,
  officialRankValue: null,
  presence: OfficialFleetMemberPresence.away,
  server: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  ship: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  location: const OfficialFleetMemberField(
    OfficialFleetMemberFieldState.unknown,
  ),
  starBridgeConnected: true,
  identityState: OfficialFleetMemberIdentityState.starBridge,
  isSelf: ref == 'self',
  sharingPaused: sharingPaused,
);

class PendingMembers
    implements OfficialFleetMembersPort, OfficialFleetMembersActivityPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final scopes = StreamController<void>.broadcast(sync: true);
  final reads = <Completer<OfficialFleetMemberDirectorySnapshot>>[];
  final queries = <OfficialFleetMemberDirectoryQuery>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Stream<void> get runtimeChanges => changes.stream;
  @override
  Stream<void> get runtimeScopeInvalidations => scopes.stream;
  @override
  void retireRuntimeActivity() {}
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery q,
  ) {
    queries.add(q);
    final c = Completer<OfficialFleetMemberDirectorySnapshot>();
    reads.add(c);
    return c.future;
  }

  void complete(int index, List<OfficialFleetMember> members) =>
      reads[index].complete(
        OfficialFleetMemberDirectorySnapshot.available(
          query: queries[index],
          members: members,
          totalCount: members.length,
          onlineCount: null,
          inGameCount: null,
          totalPages: 1,
          runtimeCapabilities: const OfficialFleetMemberRuntimeCapabilities(
            presence: true,
          ),
        ),
      );
  @override
  Future<void> close() async {
    await changes.close();
    await scopes.close();
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'local online never bypasses a paused Host row or changes other members',
    () {
      const local = OfficialFleetSelfPresence(
        key: 'presence.online',
        sharingAllowed: true,
      );
      final paused = pilot('self', sharingPaused: true);
      expect(local.project(paused), same(paused));
      expect(
        local.project(paused).publicPresence,
        OfficialFleetMemberPresence.offline,
      );
      final other = pilot('other');
      expect(local.project(other), same(other));
    },
  );
  test(
    'self follows local online/away immediately, never crosses sharing gates',
    () async {
      final port = PendingMembers();
      final module = createOfficialFleetMembersModule(port);
      final local = ValueNotifier(
        const OfficialFleetSelfPresence(
          key: 'presence.online',
          sharingAllowed: true,
        ),
      );
      module.bindSelfPresence(local, (_) => local.value);
      addTearDown(() {
        module.dispose();
        local.dispose();
      });
      final opening = module.open(source);
      port.complete(0, [pilot('self'), pilot('other')]);
      await opening;
      final other = module.projection.value.members.last;
      for (final (key, expected, allowed) in [
        ('presence.away', OfficialFleetMemberPresence.away, true),
        ('presence.online', OfficialFleetMemberPresence.online, true),
        ('presence.invisible', OfficialFleetMemberPresence.offline, true),
        ('presence.online', OfficialFleetMemberPresence.offline, false),
        ('presence.online', OfficialFleetMemberPresence.online, true),
      ]) {
        local.value = OfficialFleetSelfPresence(
          key: key,
          sharingAllowed: allowed,
        );
        expect(module.projection.value.members.first.publicPresence, expected);
        expect(module.projection.value.members.last, same(other));
      }
      expect(port.reads, hasLength(1));
    },
  );

  test(
    'pending reread cannot cross reset, scope retirement or query replacement',
    () async {
      for (final action in ['reset', 'scope', 'search']) {
        final port = PendingMembers();
        final module = createOfficialFleetMembersModule(port);
        final first = module.open(source);
        port.changes.add(null);
        Future<void>? next;
        if (action == 'reset') module.reset();
        if (action == 'scope') port.scopes.add(null);
        if (action == 'search') next = module.search('new');
        port.complete(0, [pilot('self', name: 'Retired')]);
        await first;
        if (action != 'reset') {
          port.complete(1, [pilot('self', name: 'Current')]);
          await next;
        }
        await flush();
        expect(port.reads.length, action == 'reset' ? 1 : 2);
        expect(
          module.projection.value.members.any((m) => m.callsign == 'Retired'),
          isFalse,
        );
        module.dispose();
      }
    },
  );
  test(
    'runtime refresh is silent and reuses unchanged members and selection',
    () async {
      final port = PendingMembers();
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      final opening = module.open(source);
      port.complete(0, [pilot('self'), pilot('other')]);
      await opening;
      final previous = module.projection.value.members;
      module.selectMember('other');
      port.changes.add(null);
      expect(module.projection.value.isRefreshing, isFalse);
      expect(module.projection.value.members, same(previous));
      port.complete(1, [pilot('self', name: 'Changed'), pilot('other')]);
      await flush();
      expect(module.projection.value.members.first.callsign, 'Changed');
      expect(module.projection.value.members.last, same(previous.last));
      expect(module.selectedMemberRef.value, 'other');
    },
  );

  test(
    'three changes during one read cause exactly one trailing read',
    () async {
      final port = PendingMembers();
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      final opening = module.open(source);
      for (var i = 0; i < 3; i++) {
        port.changes.add(null);
      }
      port.complete(0, [pilot('self', name: 'Old')]);
      await flush();
      expect(port.reads, hasLength(2));
      port.complete(1, [pilot('self', name: 'Latest')]);
      await opening;
      await flush();
      expect(port.reads, hasLength(2));
      expect(module.projection.value.members.single.callsign, 'Latest');
    },
  );

  test('manual refresh still announces loading', () async {
    final port = PendingMembers();
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    final opening = module.open(source);
    port.complete(0, [pilot('self')]);
    await opening;
    final refresh = module.refresh();
    expect(module.projection.value.isRefreshing, isTrue);
    port.complete(1, [pilot('self')]);
    await refresh;
  });

  // User report 2026-10-29: the list blanked on every connection-mode
  // revision. A plain revision now arrives as a runtime change (silent
  // reread, rows kept); a real scope invalidation still clears at once.
  test('a runtime change keeps rows, a scope invalidation clears them', () async {
    final port = PendingMembers();
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    final opening = module.open(source);
    port.complete(0, [pilot('self'), pilot('b', name: 'Other')]);
    await opening;
    port.changes.add(null);
    expect(module.projection.value.members, hasLength(2));
    port.complete(1, [pilot('self')]);
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.members, hasLength(1));
    port.scopes.add(null);
    expect(module.projection.value.members, isEmpty);
  });
}
