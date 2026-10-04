import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_header.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_shell.dart';
import 'package:starbridge_flutter/features/communities/example_community_workspace.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;
import 'menu_channel_media_session_test.dart' show PhotoPort;
import 'menu_organizations_test.dart' show fixture;

void main() {
  setUpAll(loadFonts);
  test('chat first loads overview independently without opening members', () async {
    final port = PhotoPort();
    final chat = Completer<void>();
    final session = MenuOrganizationsSession(port, (raw) {
      if ((raw['organization'] as Map?)?['tab'] == 'chat' &&
          raw['state'] == 'ready' &&
          !chat.isCompleted) {
        chat.complete();
      }
    });
    addTearDown(session.dispose);
    session.show(true);
    await chat.future.timeout(const Duration(seconds: 3));
    // Slow presence must not hold up usable chat or require a member-tab visit.
    port.workspaceGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final org = session.currentView['organization'] as Map;
    expect(org['tab'], 'chat');
    expect((org['overview'] as Map)['online'], isA<int>());
    expect(port.workspaceReads, 1);
  });
  test(
    'switching section preserves shell and does not read directory again',
    () async {
      final port = PhotoPort();
      final chat = Completer<MenuFeatureView>();
      final members = Completer<MenuFeatureView>();
      final views = <MenuFeatureView>[];
      final session = MenuOrganizationsSession(port, (raw) {
        final view = MenuFeatureView.parse(raw);
        views.add(view);
        if (view.organization?.tab == 'chat' &&
            view.organization!.sections['members'] != null &&
            !chat.isCompleted) {
          chat.complete(view);
        }
        if (view.organization?.tab == 'members' &&
            !view.refreshing &&
            !members.isCompleted) {
          members.complete(view);
        }
      });
      addTearDown(session.dispose);
      session.show(true);
      final ready = await chat.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final reads = port.directoryReads;
      views.clear();
      session.act(ready.organization!.sections['members']!, '');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final stable = views.every(
        (v) => v.organization != null && v.organization!.navigation.isNotEmpty,
      );
      final rereads = port.directoryReads - reads;
      port.workspaceGate.complete();
      final memberPage = await members.future.timeout(
        const Duration(seconds: 3),
      );
      expect(
        {'shellRetained': stable, 'directoryRereads': rereads},
        {'shellRetained': true, 'directoryRereads': 0},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      session.act(
        memberPage.buttons.firstWhere((b) => b.label == '搜索成员').key,
        'pilot',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        port.directoryReads,
        reads,
        reason: 'Search also leaves the organization list intact',
      );
      await session.refresh();
      expect(
        port.directoryReads,
        greaterThan(reads),
        reason: 'Explicit refresh still revalidates membership',
      );
      port.changes.add(null);
      expect(
        MenuFeatureView.parse(session.currentView).organization,
        isNull,
        reason: 'Account invalidation clears retained chrome immediately',
      );
    },
  );
  testWidgets('organization header and tabs stay fixed while body scrolls', (
    tester,
  ) async {
    size(tester, const Size(1200, 450));
    await tester.pumpWidget(
      app(
        MenuOrganizationsPanel(
          view: MenuFeatureView.parse(fixture()),
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tab = find.byKey(const ValueKey('community-section-members'));
    final rect = tester.getRect(tab);
    await tester.drag(find.text('@Pilot_2').first, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tester.getRect(tab), rect);
  });
  testWidgets(
    'client menu tabs keep rects and shape through press selection and loading',
    (tester) async {
      size(tester, const Size(1200, 700));
      Rect? expected;
      ShapeBorder? shape;
      for (final state in [
        ('members', false),
        ('chat', false),
        ('ships', true),
        ('announcements', false),
      ]) {
        final raw = fixture(tab: state.$1);
        raw['busy'] = state.$2;
        (raw['organization'] as Map)['identity'] = 'o1';
        (raw['organization'] as Map)['overview'] = {
          'online': 2,
          'gaming': 1,
          'total': 24,
        };
        await tester.pumpWidget(
          app(
            Theme(
              data: buildMenuOverlayTheme(const Locale('zh', 'CN')),
              child: MenuOrganizationsPanel(
                view: MenuFeatureView.parse(raw),
                onAction: (_, _) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tab = find.byKey(const ValueKey('community-section-chat'));
        expected ??= tester.getRect(tab);
        shape ??= tester.widget<ChoiceChip>(tab).shape;
        expect(tester.getRect(tab), expected);
        expect(tester.widget<ChoiceChip>(tab).shape, shape);
        final gesture = await tester.startGesture(tester.getCenter(tab));
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getRect(tab), expected);
        await gesture.up();
        expect(find.byType(MenuOrganizationHeader), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  test('overview survives chat switch but never survives organization invalidation', () {
    final shell = MenuOrganizationShell();
    final card = PhotoPort().card;
    final first = shell.project(
      card.targetRef,
      exampleCommunityWorkspace(card, '', 0),
      card,
    );
    expect(
      shell.project(card.targetRef, null, card)['overview'],
      first['overview'],
    );
    shell.clear();
    final cleared = shell.project(card.targetRef, null, card);
    expect(cleared['identity'], isNot(first['identity']));
    expect((cleared['overview'] as Map).containsKey('online'), isFalse);
  });
  test('failed section retains chrome but unlocks explicit retry', () {
    final shell = MenuOrganizationShell();
    final card = PhotoPort().card;
    final data = fixture();
    data['organization'] = {
      ...data['organization'] as Map,
      ...shell.project(
        card.targetRef,
        exampleCommunityWorkspace(card, '', 0),
        card,
      ),
    };
    shell.remember(card.targetRef, data);
    final identity = (data['organization'] as Map)['identity'];
    shell.observe({
      ...data,
      'organization': {
        ...data['organization'] as Map,
        'navigation': [
          {
            'name': 'fixture',
            'summary': 'late summary',
            'key': 'a20',
            'selected': true,
          },
        ],
      },
    });
    shell.observe({
      ...data,
      'organization': {
        ...data['organization'] as Map,
        'identity': 'old-$identity',
      },
    });
    final failed = MenuFeatureView.parse(shell.failed(card.targetRef, 'ships'));
    expect(failed.state, 'ready');
    expect(failed.busy, isFalse);
    expect(failed.organization!.bodyError, isTrue);
    expect(failed.organization!.bodyLoading, isFalse);
    expect(failed.organization!.sections.values, everyElement(isNull));
    expect(failed.buttons, isEmpty);
    expect(failed.organization!.navigation.single.summary, 'late summary');
    shell.clear();
    expect(shell.failed(card.targetRef, 'ships'), isNull);
  });
}
