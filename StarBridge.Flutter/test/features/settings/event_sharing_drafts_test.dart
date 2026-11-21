import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_page.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';

import 'event_sharing_controller_test.dart' show Harness;
import 'local_privacy_page_test.dart' show app, viewport;

void main() {
  for (final closeRoom in [true, false]) {
    testWidgets(
      closeRoom
          ? 'same-frame room off then community ship off preserves both edits'
          : 'same-frame room ship off then room on preserves both edits',
      (tester) async {
        viewport(tester, const Size(1280, 650));
        final h = Harness();
        final drafts = PrivacyPageDrafts();
        try {
          await tester.pumpWidget(
            app(
              PrivacyDraftScope(
                drafts: drafts,
                child: EventSharingPage(session: h.session),
              ),
            ),
          );
          await tester.pumpAndSettle();
          StarBridgeCheckboxTile roomMaster() =>
              tester.widget<StarBridgeCheckboxTile>(
                find.byKey(
                  const Key('privacy-scope-event-room-audience-events-enabled'),
                ),
              );
          if (closeRoom) {
            roomMaster().onChanged!(true);
            await tester.pumpAndSettle();
          }
          final scope = closeRoom ? 'A' : 'room';
          final ship = tester.widget<StarBridgeSwitch>(
            find.byKey(Key('privacy-scope-event-$scope-field-ship')),
          );
          final master = roomMaster();
          expect(master.value, closeRoom);
          expect(ship.value, isTrue);

          if (closeRoom) {
            master.onChanged!(false);
            ship.onChanged!(false);
          } else {
            ship.onChanged!(false);
            master.onChanged!(true);
          }

          final room = EventSharingChoice(
            enabled: !closeRoom,
            selectedTypes: closeRoom ? 47 : 43,
          );
          final communityA = EventSharingChoice(
            enabled: false,
            selectedTypes: closeRoom ? 43 : 47,
          );
          expect(
            drafts.value<Map<String?, EventSharingChoice>?>(
              'event-choices',
              null,
            ),
            {null: room, 'A': communityA, 'B': EventSharingChoice.unconfirmed},
          );
          expect(drafts.dirty, isTrue);
          expect(h.writes, isEmpty);

          final save = drafts.save();
          await tester.pumpAndSettle();
          expect(await save, isTrue);
          expect(drafts.dirty, isFalse);
          expect(h.writes, hasLength(1));
          final payload = h.writes.single.payload;
          expect(payload['expectedRevision'], 0);
          expect(payload['publicationEnabled'], !closeRoom);
          expect(payload['settings'], {
            'room': room.toJson(),
            'communities': [
              if (closeRoom)
                {
                  'code': 'A',
                  'joinedAt': Harness.joined,
                  'choice': communityA.toJson(),
                },
            ],
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(h.close);
          drafts.dispose();
        }
      },
    );
  }

  for (final (scope, enabled, changeType) in [
    ('room', true, false),
    ('room', false, false),
    ('A', true, false),
    ('room', true, true),
    ('room', false, true),
    ('A', false, true),
  ]) {
    testWidgets(
      'first event save for $scope (enabled=$enabled, edit type=$changeType) leaves other scopes off',
      (tester) async {
        viewport(tester, const Size(1280, 650));
        final h = Harness();
        final drafts = PrivacyPageDrafts();
        await tester.pumpWidget(
          app(
            PrivacyDraftScope(
              drafts: drafts,
              child: EventSharingPage(session: h.session),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(h.writes, isEmpty);
        expect(drafts.dirty, isFalse);
        expect(
          find.byKey(const Key('event-sharing-adopt-suggestion')),
          findsOneWidget,
        );
        final logos = tester.widgetList<CommunityLogo>(
          find.byType(CommunityLogo),
        );
        expect(logos.length, 2);
        expect(logos.every((logo) => !logo.framed && logo.size == 36), isTrue);
        final offscreen = find.byWidgetPredicate(
          (widget) =>
              widget is EventScopeEditor && widget.scopeKey == 'event-B',
        );
        expect(tester.getTopLeft(offscreen).dy, greaterThan(650));
        expect(
          tester
              .widgetList<EventScopeEditor>(find.byType(EventScopeEditor))
              .every((scope) => !scope.choice.enabled),
          isTrue,
        );
        Finder master(String scope) => find.byKey(
          Key('privacy-scope-event-$scope-audience-events-enabled'),
        );
        Finder type(String scope, String id) =>
            find.byKey(Key('privacy-scope-event-$scope-field-$id'));
        Future<void> toggle(Finder control) async {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          await tester.tap(control);
          await tester.pumpAndSettle();
        }

        void expectControls(String scope, bool enabled, int mask) {
          expect(
            tester.widget<StarBridgeCheckboxTile>(master(scope)).value,
            enabled,
          );
          for (final MapEntry(key: id, value: bit) in const {
            'presence': 1,
            'server': 2,
            'ship': 4,
            'location': 8,
            'life': 32,
          }.entries) {
            final control = tester.widget<StarBridgeSwitch>(type(scope, id));
            expect(control.value, mask & bit != 0, reason: '$scope $id');
          }
        }

        for (final key in ['room', 'A', 'B']) {
          expectControls(key, false, 47);
        }
        final mask = changeType ? 43 : 47;
        if (changeType) {
          await toggle(type(scope, 'ship'));
          expectControls(scope, false, mask);
        }
        if (enabled || !changeType) {
          await toggle(master(scope));
          expectControls(scope, true, mask);
          if (!enabled) await toggle(master(scope));
        }
        expectControls(scope, enabled, mask);
        for (final key in ['room', 'A', 'B'].where((key) => key != scope)) {
          expectControls(key, false, 47);
        }
        expect(h.writes, isEmpty);
        expect(drafts.dirty, isTrue);
        final save = drafts.save();
        await tester.pumpAndSettle();
        expect(await save, isTrue);
        expect(h.writes.length, 1);
        final payload = h.writes.single.payload;
        expect(payload['expectedRevision'], 0);
        expect(payload['publicationEnabled'], enabled);
        final settings = payload['settings'] as Map;
        expect(settings['room'], {
          'enabled': scope == 'room' && enabled,
          'selectedTypes': scope == 'room' ? mask : 47,
        });
        expect(settings['communities'], [
          if (scope == 'A')
            {
              'code': 'A',
              'joinedAt': Harness.joined,
              'choice': {'enabled': enabled, 'selectedTypes': mask},
            },
        ]);
        expectControls(scope, enabled, mask);
        if (!enabled) {
          expect(
            tester.widget<StarBridgeSwitch>(type(scope, 'ship')).onChanged,
            isNull,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.close);
        drafts.dispose();
      },
    );
  }
}
