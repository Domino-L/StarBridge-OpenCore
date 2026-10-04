import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';

import '../../features/communities/bridge_communities_test.dart'
    show CommunityHarness;
import '../../features/communities/community_workspace_test.dart'
    show workspacePayload;
import '../../features/communities/community_chat_test.dart' show chatPage;

void main() {
  test(
    'unavailable sidebar previews cannot block the selected organization',
    () async {
      final host = _SidebarBlockedHarness(
        legacy: true,
        capabilities: [
          'communities.read',
          'communities.chat',
          'communities.chatDetail',
        ],
        responses: {
          'communities.read': {
            'schemaVersion': 1,
            'view': 'mine',
            'query': '',
            'next': null,
            'items': [
              for (var i = 0; i < 20; i++)
                {
                  'targetRef': i == 0
                      ? 'a' * 32
                      : i.toRadixString(16).padLeft(32, '0'),
                  'name': 'Organization $i',
                  'description': '',
                  'relationship': 'member',
                  'joinMode': 'application',
                  'actions': [],
                  'language': '',
                  'activeTime': '',
                },
            ],
          },
          'communities.chat': {
            ...chatPage(),
            'messages': [
              for (final row in chatPage()['messages'] as List)
                {
                  ...row as Map<String, Object?>,
                  'hasAvatar': false,
                  'hasAttachment': false,
                },
            ],
          },
        },
      );
      addTearDown(host.close);
      final ready = Completer<Map<String, Object?>>();
      final session = MenuOrganizationsSession(host.adapter, (view) {
        if (view['state'] == 'ready' && !ready.isCompleted) {
          ready.complete(view);
        }
      })..show(true);
      addTearDown(session.dispose);
      final view = MenuFeatureView.parse(
        await ready.future.timeout(const Duration(seconds: 4)),
      );
      expect(view.organization!.navigation.length, 20);
      expect(view.chat!.messages.length, 2);
    },
  );
  test('unavailable directory logo cannot block an authorized chat', () async {
    final host = _PagedCommunityHarness(
      legacy: true,
      holdNames: {'communities.media'},
      capabilities: [
        'communities.read',
        'communities.media',
        'communities.chat',
        'communities.chatDetail',
      ],
      responses: {
        'communities.read': {
          'schemaVersion': 1,
          'view': 'mine',
          'query': '',
          'next': null,
          'items': [
            {
              'targetRef': 'a' * 32,
              'name': 'Test organization',
              'description': '',
              'relationship': 'member',
              'joinMode': 'application',
              'actions': [],
              'language': '中文',
              'activeTime': '',
              'memberCount': 1,
              'logoDeferred': true,
            },
          ],
        },
        'communities.chat': {
          ...chatPage(),
          'messages': [
            for (final row in chatPage()['messages'] as List)
              {
                ...row as Map<String, Object?>,
                'hasAvatar': false,
                'hasAttachment': false,
              },
          ],
        },
      },
    );
    addTearDown(host.close);
    final views = <Map<String, Object?>>[];
    final ready = Completer<void>();
    final session = MenuOrganizationsSession(host.adapter, (view) {
      views.add(view);
      if (view['state'] == 'ready' && !ready.isCompleted) ready.complete();
    })..show(true);
    addTearDown(session.dispose);
    await ready.future.timeout(const Duration(seconds: 4));
    expect(
      host.requests.where((r) => r.name == 'communities.media'),
      isNotEmpty,
    );
    expect(views.last['state'], 'ready');
    expect(MenuFeatureView.parse(views.last).chat!.messages.length, 2);
  });
  for (final blockedWorkspace in [false, true]) {
    test(
      'production bridge chat opens with workspace blocked=$blockedWorkspace',
      () async {
        final host = _PagedCommunityHarness(
          legacy: true,
          holdNames: blockedWorkspace ? {'communities.workspace'} : {},
          capabilities: [
            'communities.read',
            'communities.workspace',
            'communities.chat',
            'communities.chatDetail',
          ],
          responses: {
            'communities.read': {
              'schemaVersion': 1,
              'view': 'mine',
              'query': '',
              'next': null,
              'items': [
                {
                  'targetRef': 'a' * 32,
                  'name': 'Test organization',
                  'description': '',
                  'relationship': 'member',
                  'joinMode': 'application',
                  'actions': [],
                  'language': '中文',
                  'activeTime': '',
                  'memberCount': 1,
                },
              ],
            },
            'communities.workspace': workspacePayload(),
            'communities.chat': {
              ...chatPage(),
              'messages': [
                for (final row in chatPage()['messages'] as List)
                  {
                    ...row as Map<String, Object?>,
                    'hasAvatar': false,
                    'hasAttachment': false,
                  },
              ],
            },
          },
        );
        final views = <Map<String, Object?>>[];
        final ready = Completer<void>();
        final session = MenuOrganizationsSession(host.adapter, (view) {
          views.add(view);
          if (view['state'] != 'loading' && !ready.isCompleted) {
            ready.complete();
          }
        })..show(true);
        addTearDown(session.dispose);
        addTearDown(host.close);
        await ready.future.timeout(const Duration(seconds: 5));
        expect(views.last['state'], 'ready');
        final view = MenuFeatureView.parse(views.last);
        expect(view.state, 'ready');
        expect(view.organization!.navigation.single.name, 'Test organization');
        expect(view.chat!.messages.length, 2);
        expect(view.title, 'Test organization');
        expect(
          host.requests.where((r) => r.name == 'communities.workspace'),
          isEmpty,
        );
        for (var i = 0; i < 3; i++) {
          expect(
            session.readingView,
            isNotNull,
            reason: 'cache before reopen $i',
          );
          session.show(false);
          session.show(true);
          expect(
            views.last['state'],
            'ready',
            reason: 'Reopening must retain the authorized chat while renewing',
          );
          expect(MenuFeatureView.parse(views.last).chat!.messages.length, 2);
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      },
    );
  }
}

class _PagedCommunityHarness extends CommunityHarness {
  _PagedCommunityHarness({
    super.legacy,
    super.holdNames,
    required super.capabilities,
    required super.responses,
  });

  @override
  Future<void> reply(BridgeEnvelope request) {
    if (request.name != 'communities.chat') return super.reply(request);
    final original = responses['communities.chat']!;
    final after = request.payload['after'] as int? ?? 0;
    responses['communities.chat'] = {
      ...original,
      if (after >= 12) 'oldestSequence': 0,
      if (after >= 12) 'hasOlder': false,
      'messages': [
        for (final row in original['messages'] as List)
          if ((row as Map)['sequence'] > after) row,
      ],
    };
    final response = super.reply(request);
    responses['communities.chat'] = original;
    return response;
  }
}

class _SidebarBlockedHarness extends _PagedCommunityHarness {
  _SidebarBlockedHarness({
    super.legacy,
    required super.capabilities,
    required super.responses,
  });
  @override
  Future<void> reply(BridgeEnvelope request) {
    if (request.name == 'communities.chat' &&
        request.payload['targetRef'] != 'a' * 32) {
      return Future.value(); // Authenticated selected chat is healthy; other previews stall.
    }
    return super.reply(request);
  }
}
