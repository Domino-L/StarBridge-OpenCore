import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'menu_comms_session_test.dart' show Port, peer, page;

import 'package:starbridge_flutter/app/menu_overlay/menu_chat_archive.dart';

class Archive implements MenuChatArchive {
  int clears = 0;
  @override
  Future<void> clear(String kind, String reference) async {
    clears++;
  }

  @override
  Future<List<Map<String, Object?>>> load(
    String kind,
    String reference,
  ) async => [
    {
      'name': 'A',
      'text': 'saved across restart',
      'time': DateTime.utc(2026).toIso8601String(),
      'self': false,
      'attachment': false,
    },
  ];
}

void main() {
  testWidgets(
    'persisted display loads before remote reply and cannot send or acknowledge',
    (tester) async {
      final port = Port(),
          archive = Archive(),
          views = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, views.add, archive: archive)
        ..show(true);
      port.directories.single.complete([peer('A')]);
      await tester.pump();
      session.act(
        'select',
        MenuCommsView.parse(jsonEncode(views.last)).rows.single.key,
      );
      await tester.pump();
      final cached = MenuCommsView.parse(jsonEncode(views.last));
      expect(cached.messages.single.text, 'saved across restart');
      expect(cached.canSend, false);
      expect(cached.receipts, isEmpty);
      expect(cached.archiveAvailable, true);
      session.act('clearLocal', '');
      await tester.pump();
      expect(archive.clears, 1);
      expect(port.sends + port.receipts, 0);
      session.dispose();
      await tester.pump(const Duration(seconds: 13));
    },
  );
  testWidgets('return to read conversation shows history before network reply', (
    tester,
  ) async {
    final port = Port(), views = <Map<String, Object?>>[];
    final session = MenuCommsSession(port, views.add)..show(true);
    port.directories.single.complete([peer('A'), peer('B')]);
    await tester.pump();
    final rows = MenuCommsView.parse(jsonEncode(views.last)).rows;
    session.act('select', rows.first.key);
    port.histories.last.reply.complete(page('secret-A', text: 'cached A'));
    await tester.pump();
    session.act('select', rows.last.key);
    // Selecting a different conversation must remain possible during its read.
    session.act('select', rows.first.key);
    final restored = MenuCommsView.parse(jsonEncode(views.last));
    expect(restored.state, 'ready');
    expect(restored.messages.single.text, 'cached A');
    expect(restored.busy, isFalse);
    expect(
      restored.canSend,
      isFalse,
      reason: 'cached content is not an authorization grant',
    );
    port.events.add(null);
    expect(
      views.last['state'],
      'loading',
      reason: 'account invalidation clears cached text',
    );
    session.dispose();
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets(
    'organization refresh retains conversation directory and does not lock it',
    (tester) async {
      final views = <Map<String, Object?>>[];
      final session = MenuOrganizationsSession(
        ExampleCommunities(),
        views.add,
        chatOnly: true,
      )..show(true);
      await tester.pump();
      final before = views.last;
      session.act('refresh', '');
      expect(views.last['state'], 'ready');
      expect(
        (views.last['channels'] as List).map((r) => r['title']),
        (before['channels'] as List).map((r) => r['title']),
      );
      expect(views.last['busy'], isNot(true));
      final rows = before['channels'] as List;
      session.act((rows.first['buttons'] as List).first['key'] as String, '');
      await tester.pump();
      expect((views.last['organization'] as Map)['tab'], 'chat');
      session.dispose();
      await tester.pump(const Duration(seconds: 16));
    },
  );
}
