import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_page.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'event_sharing_controller_test.dart' show Harness;
import 'local_privacy_page_test.dart' show app, viewport;

void main() {
  testWidgets('first use stages all event types and saves all scopes once', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final h = Harness();
    final drafts = PrivacyPageDrafts();
    await tester.pumpWidget(app(PrivacyDraftScope(drafts: drafts,
      child: EventSharingPage(session: h.session))));
    await tester.pumpAndSettle();
    expect(h.writes, isEmpty);
    expect(drafts.dirty, isTrue);
    final logos = tester.widgetList<CommunityLogo>(find.byType(CommunityLogo));
    expect(logos.length, 2);
    expect(logos.every((logo) => !logo.framed && logo.size == 36), isTrue);
    final ship = find.byKey(const Key('privacy-scope-event-room-field-ship'));
    await tester.ensureVisible(ship);
    await tester.tap(ship);
    await tester.pumpAndSettle();
    expect(h.writes, isEmpty);
    final save = drafts.save();
    await tester.pumpAndSettle();
    expect(await save, isTrue);
    expect(h.writes.length, 1);
    final settings = h.writes.single.payload['settings'] as Map;
    expect(settings['room'], {'enabled': true, 'selectedTypes': 43});
    for (final row in settings['communities'] as List) {
      expect(row['choice'], {'enabled': true, 'selectedTypes': 47});
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.close);
    drafts.dispose();
  });
}
