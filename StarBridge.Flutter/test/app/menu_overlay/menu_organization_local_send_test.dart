import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_community_workspace.dart';

import 'menu_organization_renewal_test.dart' show RenewingPort;
import 'menu_organization_body_stability_test.dart' show ready;
import 'menu_comms_channels_test.dart' show channel;
import '../../features/communities/community_chat_test.dart' show chatPage;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

class LocalSendPort extends RenewingPort implements CommunityChatSendPort {
  final sends = <CommunityChatSendIntent>[];
  Completer<CommunityChatSendOutcome> reply = Completer();
  bool confirmedHistory = false;
  @override
  bool get chatSendAvailable => true;
  @override
  Future<CommunityChatSendOutcome> sendChat(CommunityChatSendIntent intent) {
    sends.add(intent);
    return reply.future;
  }

  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    if (confirmedHistory && after < 21) {
      final raw = chatPage();
      return CommunityChatPage.parse({
        ...raw,
        'targetRef': targetRef,
        'latestSequence': 21,
        'oldestSequence': 21,
        'hasOlder': false,
        'messages': [
          {
            ...(raw['messages'] as List).last as Map<String, Object?>,
            'sequence': 21,
            'messageRef': '9' * 32,
            'hasAvatar': false,
            'hasAttachment': false,
            'text': sends.last.text,
            'localRequestId': sends.last.requestId,
          },
        ],
      });
    }
    return super.readChat(targetRef, after: after, before: before);
  }
}

class TwoOrganizationsPort extends LocalSendPort {
  bool firstAuthorized = true;
  final second = CommunityCard(
    targetRef: 'b' * 32,
    organizationRef: 'c' * 32,
    relationship: 'member',
    name: 'Second authorized organization',
  );
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async =>
      CommunityDirectory(view, query, [if (firstAuthorized) card, second]);
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async => exampleCommunityWorkspace(
    targetRef == second.targetRef ? second : card,
    query,
    offset,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  testWidgets('local states fit narrow layouts in all supported locales', (
    tester,
  ) async {
    final boundary = GlobalKey();
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ]) {
      for (final width in [340.0, 420.0]) {
        for (final state in ['failed', 'unknown']) {
          size(tester, Size(width, 760));
          final raw = channel();
          raw['rows'] = <Map<String, Object?>>[];
          raw['chat'] = {
            'status': state == 'unknown' ? 'unknown' : 'rejected',
            'revision': 0,
            'messages': <Map<String, Object?>>[],
            'receipts': <String, String>{},
            'outboxVersion': 1,
            'localMessages': [
              {
                'id': 'l1',
                'text': '准备好后在集合点见。 Ready at the rendezvous.',
                'state': state,
                'time': '2026-10-03T18:00:00Z',
                if (state == 'failed') ...{'retry': 'a3', 'restore': 'a4'},
              },
            ],
          };
          await tester.pumpWidget(
            app(
              Builder(
                builder: (context) => Localizations.override(
                  context: context,
                  locale: locale,
                  child: RepaintBoundary(
                    key: boundary,
                    child: MenuChannelPanel(
                      key: ValueKey('$locale/$width/$state'),
                      view: MenuFeatureView.parse(raw),
                      active: true,
                      embeddedOrganization: true,
                      onAction: (_, _) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$locale/$width/$state',
          );
          final statusAction = find.byType(OutlinedButton).first;
          expect(statusAction.hitTestable(), findsOneWidget);
          expect(tester.getSize(statusAction).height, greaterThanOrEqualTo(44));
          if (locale == const Locale('zh', 'CN') && width == 420) {
            await capture(
              tester,
              boundary,
              'menu-organization-local-$state-420',
            );
          }
        }
      }
    }
  });

  test('expired menu send action rejects handoff without sending', () async {
    final port = LocalSendPort();
    final session = MenuOrganizationsSession(port, (_) {})..show(true);
    addTearDown(session.dispose);
    final initial = await ready(session, 'chat');
    final key = initial.buttons.singleWhere((b) => b.label == '发送消息').key;
    session.show(false);
    session.show(true);
    await ready(session, 'chat');
    session.act(key, 'Still in the editor');
    expect(port.sends, isEmpty);
    expect(MenuFeatureView.parse(session.currentView).rejectedAction, key);
    await session.refresh();
    expect(MenuFeatureView.parse(session.currentView).rejectedAction, key);
    final nextKey = MenuFeatureView.parse(session.currentView).buttons
        .singleWhere((b) => b.label == '发送消息')
        .key;
    session.show(false);
    session.act(nextKey, 'Input raced with hiding');
    session.show(true);
    final reopened = await ready(session, 'chat');
    expect(reopened.rejectedAction, nextKey);
    expect(port.sends, isEmpty);
  });

  test(
    'unknown delivery stays with its organization; revoked owner is cleared',
    () async {
      final port = TwoOrganizationsPort();
      final session = MenuOrganizationsSession(port, (_) {})..show(true);
      addTearDown(session.dispose);
      var view = await ready(session, 'chat');
      session.act(
        view.buttons.singleWhere((b) => b.label == '发送消息').key,
        'Only first organization',
      );
      port.reply.complete(const CommunityChatSendOutcome('unknown'));
      view = await ready(session, 'chat');
      final localId = view.chat!.outbox!.messages.single.id;
      session.act(view.organization!.navigation.last.key, '');
      view = await ready(session, 'chat');
      expect(view.chat!.outbox!.messages, isEmpty);
      expect(view.buttons.any((b) => b.label == '发送消息'), isTrue);
      session.act(view.organization!.navigation.first.key, '');
      view = await ready(session, 'chat');
      expect(view.chat!.outbox!.messages.single.id, localId);
      expect(view.chat!.outbox!.messages.single.state, 'unknown');
      expect(view.buttons.any((b) => b.label == '发送消息'), isFalse);
      port.firstAuthorized = false;
      await session.refresh();
      view = await ready(session, 'chat');
      expect(view.chat!.outbox!.messages, isEmpty);
      port.firstAuthorized = true;
      await session.refresh();
      view = await ready(session, 'chat');
      session.act(view.organization!.navigation.first.key, '');
      view = await ready(session, 'chat');
      expect(view.chat!.outbox!.messages, isEmpty);
      expect(port.sends, hasLength(1));
    },
  );

  test('menu owns and projects local bubble before network result', () async {
    final port = LocalSendPort();
    final session = MenuOrganizationsSession(port, (_) {})..show(true);
    addTearDown(session.dispose);
    final view = await ready(session, 'chat');
    final send = view.buttons.singleWhere((b) => b.label == '发送消息');
    session.act(send.key, 'Locally owned message');
    session.act(send.key, 'Locally owned message');
    session.act('a999', 'Next input raced with busy state');
    expect(port.sends, hasLength(1));
    expect(MenuFeatureView.parse(session.currentView).rejectedAction, 'a999');
    final chat = session.currentView['chat'] as Map;
    expect(chat['acceptedAction'], send.key);
    expect(chat['localMessages'], hasLength(1));
    final local = (chat['localMessages'] as List).single as Map;
    expect(local['text'], 'Locally owned message');
    expect(local['state'], 'sending');
    expect(local.containsKey('targetRef'), isFalse);
    expect(local.containsKey('requestId'), isFalse);
    port.reply.complete(const CommunityChatSendOutcome('unknown'));
    await ready(session, 'chat');
    expect(
      ((session.currentView['chat'] as Map)['localMessages'] as List)
          .single['state'],
      'unknown',
    );
  });

  test('invalid text never acknowledges local ownership or sends', () async {
    final port = LocalSendPort();
    final session = MenuOrganizationsSession(port, (_) {})..show(true);
    addTearDown(session.dispose);
    final view = await ready(session, 'chat');
    final key = view.buttons.singleWhere((b) => b.label == '发送消息').key;
    session.act(key, 'Invalid\u0000text');
    final rejected = MenuFeatureView.parse(session.currentView);
    expect(rejected.rejectedAction, key);
    expect(rejected.chat!.outbox!.acceptedAction, isNull);
    expect(rejected.chat!.outbox!.messages, isEmpty);
    expect(port.sends, isEmpty);
    await ready(session, 'chat');
  });

  test(
    'return to organizations does not erase unresolved local delivery',
    () async {
      final port = LocalSendPort();
      final session = MenuOrganizationsSession(port, (_) {})..show(true);
      addTearDown(session.dispose);
      var view = await ready(session, 'chat');
      session.act(
        view.buttons.singleWhere((b) => b.label == '发送消息').key,
        'Kept on return',
      );
      port.reply.complete(const CommunityChatSendOutcome('unknown'));
      view = await ready(session, 'chat');
      session.act(view.buttons.singleWhere((b) => b.label == '返回组织列表').key, '');
      view = await ready(session, 'chat');
      expect(view.chat!.outbox!.messages.single.text, 'Kept on return');
      expect(port.sends, hasLength(1));
    },
  );

  test(
    'confirmed history replaces local bubble in one coherent publication',
    () async {
      final port = LocalSendPort();
      final views = <Map<String, Object?>>[];
      final session = MenuOrganizationsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      final view = await ready(session, 'chat');
      session.act(
        view.buttons.singleWhere((b) => b.label == '发送消息').key,
        'One coherent message',
      );
      views.clear();
      port.confirmedHistory = true;
      port.reply.complete(
        const CommunityChatSendOutcome('accepted', sequence: 21),
      );
      await ready(session, 'chat');
      expect(views, isNotEmpty);
      for (final raw in views) {
        final rendered = MenuFeatureView.parse(raw);
        if (rendered.chat == null) continue;
        final copies =
            rendered.rows
                .where((r) => r.detail == 'One coherent message')
                .length +
            (rendered.chat!.outbox?.messages
                    .where((m) => m.text == 'One coherent message')
                    .length ??
                0);
        expect(
          copies,
          1,
          reason: 'No disappearing or duplicate bubble during readback',
        );
      }
      expect(
        MenuFeatureView.parse(session.currentView).chat!.outbox!.messages,
        isEmpty,
      );
    },
  );

  test(
    'rejected retry gets a new nonce; unknown never exposes replay',
    () async {
      final port = LocalSendPort();
      final session = MenuOrganizationsSession(port, (_) {})..show(true);
      addTearDown(session.dispose);
      var view = await ready(session, 'chat');
      session.act(
        view.buttons.singleWhere((b) => b.label == '发送消息').key,
        'Kept text',
      );
      port.reply.complete(
        const CommunityChatSendOutcome('rejected', error: 'rateLimited'),
      );
      view = await ready(session, 'chat');
      final local = view.chat!.outbox!.messages.single;
      expect(local.state, 'failed');
      expect(local.retry, isNotNull);
      expect(local.restore, isNotNull);
      port.reply = Completer();
      session.act(local.retry!, '');
      session.act(local.retry!, '');
      expect(port.sends, hasLength(2));
      expect(port.sends.first.requestId, isNot(port.sends.last.requestId));
      expect(port.sends.last.text, 'Kept text');
      port.reply.complete(const CommunityChatSendOutcome('unknown'));
      view = await ready(session, 'chat');
      expect(view.chat!.outbox!.messages.single.state, 'unknown');
      expect(view.chat!.outbox!.messages.single.retry, isNull);
      expect(view.chat!.outbox!.messages.single.restore, isNull);
    },
  );

  test(
    'hide and reopen keeps only local text while send is in flight',
    () async {
      final port = LocalSendPort();
      final session = MenuOrganizationsSession(port, (_) {})..show(true);
      addTearDown(session.dispose);
      final view = await ready(session, 'chat');
      session.act(
        view.buttons.singleWhere((b) => b.label == '发送消息').key,
        'Retained on reopen',
      );
      session.show(false);
      session.show(true);
      final reopened = MenuFeatureView.parse(session.currentView);
      expect(reopened.state, 'ready');
      expect(reopened.rows, isEmpty);
      expect(reopened.chat!.receipts, isEmpty);
      expect(reopened.chat!.outbox!.messages.single.text, 'Retained on reopen');
      port.reply.complete(const CommunityChatSendOutcome('unknown'));
      await ready(session, 'chat');
    },
  );

  test(
    'late result after account invalidation cannot restore local text',
    () async {
      final port = LocalSendPort();
      final views = <Map<String, Object?>>[];
      final session = MenuOrganizationsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      final view = await ready(session, 'chat');
      session.act(
        view.buttons.singleWhere((b) => b.label == '发送消息').key,
        'Retired account text',
      );
      port.changes.add(null);
      views.clear();
      port.reply.complete(
        const CommunityChatSendOutcome('accepted', sequence: 21),
      );
      await ready(session, 'chat');
      expect(views.toString(), isNot(contains('Retired account text')));
    },
  );

  test(
    'local display parser rejects invalid or replayable unknown bubbles',
    () {
      Map<String, Object?> payload() {
        final raw = channel();
        raw['chat'] = {
          ...raw['chat'] as Map,
          'outboxVersion': 1,
          'acceptedAction': 'a1',
          'localMessages': [
            {
              'id': 'l1',
              'text': 'Retained text',
              'state': 'unknown',
              'time': '2026-10-03T00:00:00Z',
            },
          ],
        };
        return raw;
      }

      expect(
        MenuFeatureView.parse(payload()).chat!.outbox!.messages,
        hasLength(1),
      );
      final replay = payload();
      (((replay['chat'] as Map)['localMessages'] as List).single
              as Map)['retry'] =
          'a9';
      expect(MenuFeatureView.parse(replay).state, 'unavailable');
      final duplicate = payload();
      final rows = (duplicate['chat'] as Map)['localMessages'] as List;
      rows.add(rows.single);
      expect(MenuFeatureView.parse(duplicate).state, 'unavailable');
    },
  );

  testWidgets(
    'write deadline retains unknown bubble and cannot unlock a duplicate send',
    (tester) async {
      final port = LocalSendPort();
      final session = MenuOrganizationsSession(port, (_) {})..show(true);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      var view = MenuFeatureView.parse(session.currentView);
      session.act(
        view.buttons.singleWhere((b) => b.label == '发送消息').key,
        'Slow result',
      );
      await tester.pump(const Duration(seconds: 16));
      view = MenuFeatureView.parse(session.currentView);
      expect(view.state, 'ready');
      expect(view.busy, isFalse);
      expect(view.chat!.status, 'unknown');
      expect(view.chat!.outbox!.messages.single.state, 'unknown');
      expect(view.chat!.outbox!.messages.single.retry, isNull);
      expect(port.sends, hasLength(1));
      port.reply.complete(const CommunityChatSendOutcome('rejected'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      view = MenuFeatureView.parse(session.currentView);
      expect(view.chat!.outbox!.messages.single.state, 'failed');
      expect(view.chat!.outbox!.messages.single.retry, isNotNull);
      session.dispose();
      await tester.pump(const Duration(seconds: 16));
    },
  );

  testWidgets(
    'matching local acceptance clears once, stale action keeps draft',
    (tester) async {
      size(tester, const Size(700, 760));
      final views = ValueNotifier<Map<String, Object?>>({});
      Map<String, Object?> state({
        String? accepted,
        String? rejected,
        int revision = 0,
      }) {
        final raw = channel(revision: revision);
        raw['rejectedAction'] = rejected;
        raw['chat'] = {
          ...raw['chat'] as Map,
          'outboxVersion': 1,
          'acceptedAction': accepted,
          'localMessages': <Map<String, Object?>>[],
        };
        return raw;
      }

      views.value = state();
      final actions = <String>[];
      await tester.pumpWidget(
        app(
          ValueListenableBuilder(
            valueListenable: views,
            builder: (_, raw, _) => MenuChannelPanel(
              view: MenuFeatureView.parse(raw),
              active: true,
              embeddedOrganization: true,
              onAction: (key, text) => actions.add(key),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('menu-channel-draft'));
      await tester.enterText(input, 'Kept until local handoff');
      await tester.pump();
      final callback = tester
          .widget<FilledButton>(find.byKey(const ValueKey('menu-channel-send')))
          .onPressed!;
      callback();
      callback();
      expect(actions.where((key) => key == 'a1'), ['a1']);
      views.value = state(accepted: 'a99', revision: 100);
      await tester.pump();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Kept until local handoff',
      );
      views.value = state(rejected: 'a1');
      await tester.pump();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Kept until local handoff',
      );
      await tester.tap(find.byKey(const ValueKey('menu-channel-send')));
      expect(actions.where((key) => key == 'a1'), ['a1', 'a1']);
      views.value = state(accepted: 'a1');
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.enterText(input, 'New draft survives repeated confirmation');
      views.value = state(accepted: 'a1', revision: 999);
      await tester.pump();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'New draft survives repeated confirmation',
      );
      await tester.pumpWidget(const SizedBox());
      views.dispose();
    },
  );

  testWidgets(
    'rejected restore cannot leave a sendable duplicate in composer',
    (tester) async {
      size(tester, const Size(700, 760));
      final raw = channel();
      raw['chat'] = {
        ...raw['chat'] as Map,
        'outboxVersion': 1,
        'localMessages': [
          {
            'id': 'l1',
            'text': 'Failed text',
            'state': 'failed',
            'time': '2026-10-03T18:00:00Z',
            'retry': 'a3',
            'restore': 'a4',
          },
        ],
      };
      final views = ValueNotifier(raw);
      final actions = <String>[];
      await tester.pumpWidget(
        app(
          ValueListenableBuilder(
            valueListenable: views,
            builder: (_, value, _) => MenuChannelPanel(
              view: MenuFeatureView.parse(value),
              active: true,
              embeddedOrganization: true,
              onAction: (key, _) => actions.add(key),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('放回输入框编辑'));
      await tester.pump();
      final input = find.byKey(const ValueKey('menu-channel-draft'));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('menu-channel-send')),
            )
            .onPressed,
        isNull,
      );
      views.value = {...raw, 'rejectedAction': 'a4'};
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(actions.where((key) => key == 'a4'), ['a4']);
      expect(find.text('Failed text'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      views.dispose();
    },
  );

  testWidgets('menu handoff clears sent text but leaves next draft editable', (
    tester,
  ) async {
    size(tester, const Size(700, 760));
    final port = LocalSendPort();
    final views = ValueNotifier<Map<String, Object?>>({'state': 'loading'});
    final session = MenuOrganizationsSession(port, (v) => views.value = v)
      ..show(true);
    await tester.pumpWidget(
      app(
        ValueListenableBuilder(
          valueListenable: views,
          builder: (_, value, _) => MenuChannelPanel(
            view: MenuFeatureView.parse(value),
            active: true,
            embeddedOrganization: true,
            onAction: session.act,
          ),
        ),
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final input = find.byKey(const ValueKey('menu-channel-draft'));
    await tester.enterText(input, 'First outgoing');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('menu-channel-send')));
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(find.text('First outgoing'), findsOneWidget);
    expect(tester.widget<TextField>(input).readOnly, isFalse);
    await tester.enterText(input, 'Next draft');
    port.reply.complete(
      const CommunityChatSendOutcome('rejected', error: 'rateLimited'),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.widget<TextField>(input).controller!.text, 'Next draft');
    expect(find.text('First outgoing'), findsOneWidget);
    expect(find.textContaining('发送过于频繁'), findsOneWidget);
    final restore = find.widgetWithText(TextButton, '放回输入框编辑');
    expect(tester.widget<TextButton>(restore).onPressed, isNull);
    await tester.enterText(input, '');
    await tester.pump();
    await tester.tap(restore);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.widget<TextField>(input).controller!.text, 'First outgoing');
    expect(
      MenuFeatureView.parse(session.currentView).chat!.outbox!.messages,
      isEmpty,
    );
    expect(port.sends, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    await tester.pump(const Duration(seconds: 16));
    views.dispose();
  });
}
