import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_scoped_save.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import 'local_privacy_page_test.dart' show app, viewport;
import 'official_runtime_privacy_test.dart' show OfficialPrivacyFixture;

// The relay refused this computer's main fleet choice as out of date
// (official_fleet.choice_changed). The unchanged choice must be savable once
// more as an explicit confirmation, and nothing may be saved without it.
OfficialPrivacyFixture _refused({String? error = 'official_fleet.choice_changed'}) =>
    OfficialPrivacyFixture()
      ..savedFields = 7
      ..publicationState = 'failed'
      ..publicationStatusError = error
      ..settings = OfficialPrivacyFixture().settings.copyWith(
        publicationEnabled: true,
      );

void main() {
  test('an unchanged main fleet choice can be confirmed again after a conflict', () async {
    final port = _refused();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.officialDraftFields, 7);
    expect(c.officialReconfirmRequired, isTrue);
    // Not an unsaved edit: no leave prompt, no paused refresh, no reapply.
    expect(c.officialDirty, isFalse);
    expect(c.dirty, isFalse);
    expect(c.canRetryPublication, isFalse);
    expect(c.canSaveOrganization(null), isTrue);
    expect(port.calls, isNot(contains('officialSave')),
        reason: 'reading the status never saves on the user\'s behalf');

    expect(await c.saveOrganization(null), isTrue);
    expect(port.calls, contains('officialSave'));
    expect(port.savedFields, 7, reason: 'the same choice is submitted, not a wider one');
    expect(port.lastCancelled, isFalse);
    expect(port.applies, greaterThan(0));
    expect(c.publicationView.state, 'applied');
    expect(c.officialReconfirmRequired, isFalse);
    expect(c.dirty, isFalse);
  });

  test('the sync and privacy page save also confirms the unchanged choice and applies it', () async {
    final port = _refused();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.canSave, isTrue);
    final appliesBefore = port.applies;
    await c.save();
    expect(port.calls, contains('officialSave'));
    expect(port.savedFields, 7);
    expect(port.applies, greaterThan(appliesBefore),
        reason: 'the saved confirmation must reach publication, not stay local');
    expect(c.publicationView.state, 'applied');
    expect(c.officialReconfirmRequired, isFalse);
    expect(c.dirty, isFalse);
  });

  testWidgets('the real sync and privacy page save button submits and applies the confirmation', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final port = _refused();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    final sync = createSyncPrivacyModule(InMemorySyncPrivacyAdapter.forReview());
    await sync.initialize();
    await c.refresh();
    await tester.pumpWidget(app(PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync)));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('privacy-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(port.calls, contains('officialSave'));
    expect(port.calls, contains('publication.apply'));
    expect(port.calls, isNot(contains('localSave')),
        reason: 'a reconfirmation never resaves untouched ordinary settings');
    expect(c.publicationView.state, 'applied');
    expect(c.officialReconfirmRequired, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('without the conflict an unchanged main fleet choice stays unsavable', () async {
    final port = _refused(error: null);
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.officialReconfirmRequired, isFalse);
    expect(c.officialDirty, isFalse);
    expect(c.canSaveOrganization(null), isFalse);
  });

  test('other publication errors never ask for a main fleet reconfirmation', () async {
    for (final error in [
      'privacy_publication.identity_required',
      'privacy_publication.forbidden',
      'privacy_publication.rejected',
    ]) {
      final port = _refused(error: error);
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.officialReconfirmRequired, isFalse, reason: error);
      expect(c.canSaveOrganization(null), isFalse, reason: error);
    }
  });
}
