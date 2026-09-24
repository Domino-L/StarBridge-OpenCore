import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_setting.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';

import 'friend_sharing_controller_test.dart' show Harness;
import 'local_privacy_page_test.dart' show app, viewport;

void main() {
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
    await tester.tap(find.byKey(const Key('friend-sharing-ship')));
    await tester.pumpAndSettle();
    expect(drafts.value('friend-fields', 0), 55);
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
    expect(drafts.value('friend-fields', 0), 55);
    final save = drafts.save();
    await tester.pumpAndSettle();
    expect(await save, isTrue);
    expect(h.writes.single.payload['fields'], 55);
    h.readGate!.complete();
    await tester.pumpAndSettle();
    expect(drafts.dirty, isFalse);
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
      expect(drafts.dirty, saved == null);
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches.length, 6);
      final mask = saved ?? 63;
      for (var i = 0; i < 6; i++) {
        expect(switches[i].value, mask & (1 << i) != 0);
      }
      final save = drafts.save();
      await tester.pumpAndSettle();
      expect(await save, isTrue);
      expect(h.writes.length, saved == null ? 1 : 0);
      if (saved == null) expect(h.writes.single.payload['fields'], 63);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
      drafts.dispose();
    });
  }

  testWidgets('discard does not re-stage first-use defaults', (tester) async {
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
    expect(drafts.dirty, isTrue);
    drafts.discard();
    await tester.pumpAndSettle();
    expect(drafts.dirty, isFalse);
    expect(h.writes, isEmpty);
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
}
