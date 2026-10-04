import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_shell.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'menu_organization_ships_test.dart' show FleetPort;

class SlowFleetPort extends FleetPort {
  Completer<void>? shipsGate;
  Completer<void>? mediaGate;
  Object? shipsError;
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    await mediaGate?.future;
    return super.readMedia(
      targetRef,
      kind,
      memberRef: memberRef,
      offset: offset,
      version: version,
    );
  }

  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    await shipsGate?.future;
    if (shipsError != null) throw shipsError!;
    return super.readShips(
      targetRef,
      offset: offset,
      revision: revision,
      query: query,
    );
  }
}

Future<MenuFeatureView> ready(
  MenuOrganizationsSession session,
  String tab,
) async {
  for (var i = 0; i < 100; i++) {
    final view = MenuFeatureView.parse(session.currentView);
    if (view.state == 'ready' &&
        !view.busy &&
        !view.refreshing &&
        view.organization?.tab == tab &&
        !view.organization!.bodyLoading &&
        view.organization!.sections.values.every((key) => key != null)) {
      return view;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('No ready $tab');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed first chat load is an error, never a successful empty snapshot',
    () {
      final shell = MenuOrganizationShell();
      final chrome = shell.project('one', null, null);
      shell.observe({
        'state': 'ready',
        'rows': [
          {'title': 'ship'},
        ],
        'organization': {
          ...chrome,
          'tab': 'ships',
          'query': '',
          'offset': 0,
          'rows': [{}],
          'sections': {'ships': 'a1'},
          'navigation': [],
        },
      });
      final failed = shell.failed('one', 'chat')!;
      expect((failed['organization'] as Map)['bodyError'], true);
      shell.observe(failed);
      expect(
        (shell.loading('one', 'chat')!['organization'] as Map)['bodyLoading'],
        true,
      );
    },
  );
  test(
    'section snapshots never cross search, page or organization boundaries',
    () {
      final shell = MenuOrganizationShell();
      final chrome = shell.project('one', null, null);
      shell.observe({
        'state': 'ready',
        'rows': [
          {'title': 'private'},
        ],
        'organization': {
          ...chrome,
          'tab': 'ships',
          'query': '',
          'offset': 0,
          'rows': [{}],
          'sections': {'ships': 'a1'},
          'navigation': [],
        },
      });
      expect((shell.loading('one', 'ships')!['rows'] as List).length, 1);
      expect(
        (shell.loading('one', 'ships', 'other')!['rows'] as List),
        isEmpty,
      );
      expect((shell.loading('one', 'ships', '', 20)!['rows'] as List), isEmpty);
      expect(shell.loading('two', 'ships'), isNull);
      shell.project('two', null, null);
      expect(shell.loading('two', 'ships'), isNull);
      shell.clear();
      expect(shell.loading('one', 'ships'), isNull);
    },
  );
  test(
    'transient failure retains ships but a denied read clears all snapshots',
    () async {
      final port = SlowFleetPort()..workspaceGate.complete();
      final session = MenuOrganizationsSession(port, (_) {});
      addTearDown(session.dispose);
      session.show(true);
      final chat = await ready(session, 'chat');
      session.act(chat.organization!.sections['ships']!, '');
      final ships = await ready(session, 'ships');
      port.shipsError = const CommunityFailure('unavailable');
      await session.refresh(silent: true);
      final retained = MenuFeatureView.parse(session.currentView);
      expect(retained.rows.length, ships.rows.length);
      expect(retained.organization!.bodyError, false);
      expect(retained.buttons, isEmpty);
      port.shipsError = const CommunityFailure('notAllowed');
      await session.refresh(silent: true);
      expect(MenuFeatureView.parse(session.currentView).rows, isEmpty);
      port.shipsGate = Completer<void>();
      port.shipsError = null;
      final pending = session.refresh();
      expect(MenuFeatureView.parse(session.currentView).rows, isEmpty);
      port.shipsGate!.complete();
      await pending;
    },
  );
  test('late owner portraits fill the visible page without another network refresh', () async {
    final port = SlowFleetPort()..workspaceGate.complete();
    port.mediaGate = Completer<void>();
    final session = MenuOrganizationsSession(port, (_) {});
    addTearDown(session.dispose);
    session.show(true);
    final chat = await ready(session, 'chat');
    session.act(chat.organization!.sections['ships']!, '');
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    final ships = await ready(session, 'ships');
    expect(ships.organization!.rows.first.avatar, isNull);
    final reads = port.queries.length;
    port.mediaGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final shown = MenuFeatureView.parse(session.currentView);
    expect(shown.organization!.rows.every((r) => r.avatar != null), isTrue);
    expect(port.queries.length, reads);
  });
  test('returning to chat retains loaded messages and sender portraits during revalidation', () async {
    final port = SlowFleetPort()..workspaceGate.complete();
    final session = MenuOrganizationsSession(port, (_) {});
    addTearDown(session.dispose);
    session.show(true);
    var chat = await ready(session, 'chat');
    for (var i = 0; i < 100 && chat.rows.any((r) => r.avatar == null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      chat = MenuFeatureView.parse(session.currentView);
    }
    expect(chat.rows, isNotEmpty);
    expect(chat.rows.every((r) => r.avatar != null), isTrue);
    final photos = chat.rows.map((r) => r.avatar).toList();
    session.act(chat.organization!.sections['ships']!, '');
    final ships = await ready(session, 'ships');
    port.chatGate = Completer<void>();
    addTearDown(() {
      if (!port.chatGate!.isCompleted) port.chatGate!.complete();
    });
    session.act(ships.organization!.sections['chat']!, '');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final shown = MenuFeatureView.parse(session.currentView);
    expect(shown.organization!.tab, 'chat');
    expect(shown.organization!.bodyLoading, isFalse);
    expect(shown.rows.map((r) => r.avatar), photos);
    expect(shown.buttons, isEmpty);
    expect(shown.chat!.availability, 'checking');
    port.chatGate!.complete();
    await ready(session, 'chat');
    port.changes.add(null);
    expect(MenuFeatureView.parse(session.currentView).rows, isEmpty);
  });
  for (final mode in ['refresh', 'silent', 'reopen', 'return']) {
    test('loaded ships retain body through $mode', () async {
      final port = SlowFleetPort()..workspaceGate.complete();
      final views = <MenuFeatureView>[];
      final session = MenuOrganizationsSession(
        port,
        (raw) => views.add(MenuFeatureView.parse(raw)),
      );
      addTearDown(session.dispose);
      session.show(true);
      final chat = await ready(session, 'chat');
      session.act(chat.organization!.sections['ships']!, '');
      final ships = await ready(session, 'ships');
      final count = ships.rows.length;
      if (mode == 'return') {
        session.act(ships.organization!.sections['chat']!, '');
        await ready(session, 'chat');
      }
      port.shipsGate = Completer<void>();
      views.clear();
      Future<void>? reading;
      if (mode == 'reopen') {
        session.show(false);
        session.show(true);
      } else if (mode == 'return') {
        final view = MenuFeatureView.parse(session.currentView);
        session.act(view.organization!.sections['ships']!, '');
      } else {
        reading = session.refresh(silent: mode == 'silent');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final shown = MenuFeatureView.parse(session.currentView);
      expect(shown.organization!.tab, 'ships');
      expect(shown.organization!.bodyLoading, isFalse);
      expect(shown.rows.length, count);
      expect(
        views
            .where((v) => v.organization?.tab == 'ships')
            .every(
              (v) => !v.organization!.bodyLoading && v.rows.length == count,
            ),
        isTrue,
      );
      port.shipsGate!.complete();
      await reading;
      await ready(session, 'ships');
    });
  }
}
