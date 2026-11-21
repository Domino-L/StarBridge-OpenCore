import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_setting.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';

import 'friend_sharing_controller_test.dart' show Harness;
import 'local_privacy_page_test.dart' show app, viewport;

Future<void> _adoptSuggestion(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('friend-sharing-adopt-suggestion')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('privacy-sharing-suggestion-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('same-frame friend presence and ship edits save both fields', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final h = Harness();
    final drafts = PrivacyPageDrafts();
    try {
      await tester.pumpWidget(
        app(
          PrivacyDraftScope(
            drafts: drafts,
            child: FriendSharingSetting(session: h.session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final presence = tester.widget<SwitchListTile>(
        find.byKey(const Key('friend-sharing-presence')),
      );
      final ship = tester.widget<SwitchListTile>(
        find.byKey(const Key('friend-sharing-ship')),
      );
      expect(presence.value, isFalse);
      expect(ship.value, isFalse);

      presence.onChanged!(true);
      ship.onChanged!(true);

      expect(drafts.value('friend-fields', 0), 9);
      expect(drafts.dirty, isTrue);
      expect(h.writes, isEmpty);

      final save = drafts.save();
      await tester.pumpAndSettle();
      expect(await save, isTrue);
      expect(drafts.dirty, isFalse);
      expect(h.writes, hasLength(1));
      final payload = h.writes.single.payload;
      expect(payload['expectedRevision'], 0);
      expect(payload['fields'], 9);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
      drafts.dispose();
    }
  });

  testWidgets(
    'first-use save retry recognizes confirmed readback without replay',
    (tester) async {
      viewport(tester, const Size(1280, 1000));
      final h = Harness()..loseWriteReceipt = true;
      final drafts = PrivacyPageDrafts();
      await tester.pumpWidget(
        app(
          PrivacyDraftScope(
            drafts: drafts,
            child: FriendSharingSetting(session: h.session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(drafts.dirty, isFalse);
      await _adoptSuggestion(tester);
      expect(drafts.dirty, isTrue);
      final first = drafts.save();
      await tester.pumpAndSettle();
      expect(await first, isFalse);
      expect(drafts.failed, isTrue);
      expect(
        h.snapshot['fields'],
        63,
      ); // Server saved; only the receipt was lost.
      h.loseWriteReceipt = false;
      final retry = drafts.save();
      await tester.pumpAndSettle();
      expect(await retry, isTrue);
      expect(drafts.failed, isFalse);
      expect(drafts.dirty, isFalse);
      expect(h.writes, hasLength(1)); // Readback, never a duplicate write.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
      drafts.dispose();
    },
  );
  testWidgets('periodic refresh preserves editable drafts without loading UI', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final h = Harness();
    final drafts = PrivacyPageDrafts();
    await tester.pumpWidget(
      app(
        PrivacyDraftScope(
          drafts: drafts,
          child: FriendSharingSetting(session: h.session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.byKey(const Key('friend-sharing-presence')),
            matching: find.byType(StarBridgeSwitch),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(drafts.value('friend-fields', 0), 1);
    h.readGate = Completer<void>();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .every((tile) => tile.onChanged != null),
      isTrue,
    );
    expect(drafts.value('friend-fields', 0), 1);
    final save = drafts.save();
    await tester.pumpAndSettle();
    expect(await save, isTrue);
    expect(h.writes.single.payload['fields'], 1);
    h.readGate!.complete();
    await tester.pumpAndSettle();
    expect(drafts.dirty, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('friend-sharing-presence')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('friend-sharing-ship')))
          .value,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.close);
    drafts.dispose();
  });
  for (final saved in <int?>[null, 0, 55]) {
    testWidgets('friend defaults preserve saved mask $saved', (tester) async {
      viewport(tester, const Size(1280, 1000));
      final h = Harness();
      if (saved != null) {
        h.snapshot = {
          'schemaVersion': 1,
          'revision': 1,
          'operationId': '0' * 32,
          'appliedAt': '2026-01-01T00:00:00Z',
          'fields': saved,
        };
      }
      final drafts = PrivacyPageDrafts();
      await tester.pumpWidget(
        app(
          PrivacyDraftScope(
            drafts: drafts,
            child: FriendSharingSetting(session: h.session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.writes, isEmpty);
      expect(drafts.dirty, isFalse);
      expect(
        find.byKey(const Key('friend-sharing-adopt-suggestion')),
        saved == null ? findsOneWidget : findsNothing,
      );
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      // Saved settings keep m101's coupled presence control.
      expect(switches.length, saved == null ? 6 : 5);
      final mask = saved ?? 0;
      for (var i = 0; i < switches.length; i++) {
        expect(switches[i].value, mask & (1 << i) != 0);
      }
      final save = drafts.save();
      await tester.pumpAndSettle();
      expect(await save, isTrue);
      expect(h.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
      drafts.dispose();
    });
  }

  testWidgets('discard restores actual friend settings before first save', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final h = Harness();
    final drafts = PrivacyPageDrafts();
    await tester.pumpWidget(
      app(
        PrivacyDraftScope(
          drafts: drafts,
          child: FriendSharingSetting(session: h.session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final adopt = find.byKey(const Key('friend-sharing-adopt-suggestion'));
    await _adoptSuggestion(tester);
    expect(drafts.dirty, isTrue);
    drafts.discard();
    await tester.pumpAndSettle();
    expect(drafts.dirty, isFalse);
    expect(h.writes, isEmpty);
    expect(adopt, findsOneWidget);
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .every((item) => !item.value),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.close);
    drafts.dispose();
  });
  testWidgets(
    'first-use retry drops only the stale friend draft after readback',
    (tester) async {
      viewport(tester, const Size(1280, 1000));
      final h = Harness()..fail = true;
      final drafts = PrivacyPageDrafts();
      await tester.pumpWidget(
        app(
          PrivacyDraftScope(
            drafts: drafts,
            child: FriendSharingSetting(session: h.session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _adoptSuggestion(tester);
      final first = drafts.save();
      await tester.pumpAndSettle();
      expect(await first, isFalse);
      h.snapshot = {
        'schemaVersion': 1,
        'revision': 1,
        'operationId': '0' * 32,
        'appliedAt': '2026-01-01T00:00:00Z',
        'fields': 0,
      };
      h.fail = false;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      final retry = drafts.save();
      await tester.pumpAndSettle();
      expect(await retry, isFalse);
      expect(drafts.saveConflicted, isTrue);
      expect(drafts.failed, isFalse);
      expect(drafts.dirty, isFalse);
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((tile) => !tile.value && tile.onChanged != null),
        isTrue,
      );
      expect(h.writes, hasLength(1));
      expect(
        h.snapshot['fields'],
        0,
      ); // Never turn an explicit OFF into default ON.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
      drafts.dispose();
    },
  );

  for (final (revision, fields) in [(2, 0), (1, 0), (2, 32)]) {
    testWidgets(
      'formal friend poll drops a stale draft (revision=$revision, fields=$fields)',
      (tester) async {
        viewport(tester, const Size(1280, 1000));
        final h = Harness();
        final drafts = PrivacyPageDrafts();
        const draftKey = 'friend-fields';
        const otherKey = 'other-card';
        var otherCommits = 0;
        Finder field(String name) => find.byKey(Key('friend-sharing-$name'));
        SwitchListTile ship() => tester.widget<SwitchListTile>(field('ship'));

        Future<bool> save() async {
          final result = drafts.save();
          await tester.pumpAndSettle();
          return result;
        }

        try {
          await tester.pumpWidget(
            app(
              PrivacyDraftScope(
                drafts: drafts,
                child: FriendSharingSetting(session: h.session),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(field('lastOnline'));
          await tester.pumpAndSettle();
          expect(await save(), isTrue);
          expect(h.writes.single.payload['expectedRevision'], 0);
          expect(h.writes.single.payload['fields'], 32);
          expect(
            find.byKey(const Key('friend-sharing-lastOnline')),
            findsNothing,
          );

          await tester.tap(field('ship'));
          await tester.pumpAndSettle();
          expect(ship().value, isTrue);
          expect(drafts.value(draftKey, 0), 40);
          expect(h.writes, hasLength(1));
          drafts.edit(otherKey, false, true, (_) async {
            otherCommits++;
            return true;
          });

          h.snapshot = {...h.snapshot, 'revision': revision, 'fields': fields};
          await tester.pump(const Duration(seconds: 15));
          await tester.pumpAndSettle();
          expect(drafts.value<int?>(draftKey, null), isNull);
          expect(drafts.value(otherKey, false), isTrue);
          expect(otherCommits, 0);
          expect(ship().value, isFalse);
          expect(ship().onChanged, isNotNull);
          expect(find.text('这张卡片的设置已在别处更新。请查看最新设置后重新编辑。'), findsOneWidget);

          // Applying OFF again to the latest card must not restore the old mask.
          ship().onChanged!(false);
          await tester.pumpAndSettle();
          expect(drafts.value<int?>(draftKey, null), isNull);
          expect(await save(), isTrue);
          expect(otherCommits, 1);
          expect(h.writes, hasLength(1));
          expect(h.snapshot['fields'], fields);

          await tester.tap(field('ship'));
          await tester.pumpAndSettle();
          expect(h.writes, hasLength(1));
          expect(await save(), isTrue);
          expect(h.writes, hasLength(2));
          expect(h.writes.last.payload['expectedRevision'], revision);
          expect(h.writes.last.payload['fields'], fields | 8);
          expect(drafts.dirty, isFalse);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(h.close);
          drafts.dispose();
        }
      },
    );
  }

  testWidgets(
    'formal friend exact readback acknowledges a draft without writing',
    (tester) async {
      viewport(tester, const Size(1280, 1000));
      final h = Harness()
        ..snapshot = {
          'schemaVersion': 1,
          'revision': 1,
          'operationId': '0' * 32,
          'appliedAt': '2026-01-01T00:00:00Z',
          'fields': 32,
        };
      final drafts = PrivacyPageDrafts();
      final ship = find.byKey(const Key('friend-sharing-ship'));
      try {
        await tester.pumpWidget(
          app(
            PrivacyDraftScope(
              drafts: drafts,
              child: FriendSharingSetting(session: h.session),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(ship);
        await tester.pumpAndSettle();
        expect(drafts.value('friend-fields', 0), 40);

        h.snapshot = {...h.snapshot, 'revision': 2, 'fields': 40};
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        final control = tester.widget<SwitchListTile>(ship);
        expect(control.value, isTrue);
        expect(control.onChanged, isNotNull);
        expect(drafts.conflict('friend-fields'), isNull);
        expect(h.writes, isEmpty);
        final retry = drafts.save();
        await tester.pumpAndSettle();
        expect(await retry, isTrue);
        expect(drafts.dirty, isFalse);
        expect(h.writes, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.close);
        drafts.dispose();
      }
    },
  );
}
