import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/official_runtime_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import 'local_privacy_page_test.dart' show app, viewport;
import 'official_runtime_privacy_test.dart' show OfficialPrivacyFixture;

// Build 71 review (11-06): after a refused main fleet choice the page showed a
// "save result unknown" stage the user never caused, "all changes saved" next to
// an enabled save button, and a sign-in warning while the account was still
// being established at startup.

OfficialPrivacyFixture _saved() => OfficialPrivacyFixture()
  ..savedFields = 7
  ..settings = OfficialPrivacyFixture().settings.copyWith(
    publicationEnabled: true,
  );

OfficialPrivacyFixture _refused() => _saved()
  ..publicationState = 'failed'
  ..publicationStatusError = 'official_fleet.choice_changed';

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  test('a background publication in flight never marks the main fleet save unknown', () async {
    final port = _saved()..holdApply = Completer<void>();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await c.refresh();
    await c.refreshOfficialRuntimePrivacy();
    final apply = c.applyPublication();
    await port.applyStarted.future;
    expect(c.publicationBusy, isTrue);
    expect(c.saving, isFalse);

    // The Host records the refusal and announces a scope change mid-apply.
    port.scopeChanges.add(null);
    await _drain();
    expect(c.officialSaveStage, OfficialPrivacySaveStage.idle,
        reason: 'no main fleet choice was submitted by this apply');

    port.holdApply!.complete();
    await apply;
    expect(c.officialSaveStage, OfficialPrivacySaveStage.idle);
  });

  test('a main fleet save in flight is still unknown when the scope changes', () async {
    final port = _saved()..holdOfficialSave = Completer<void>();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await c.refresh();
    await c.refreshOfficialRuntimePrivacy();
    c.editOfficialFields(3);
    final save = c.save();
    await port.saveStarted.future;
    expect(c.saving, isTrue);

    port.scopeChanges.add(null);
    await _drain();
    expect(c.officialSaveStage, OfficialPrivacySaveStage.unknown);

    port.holdOfficialSave!.complete();
    await save;
  });

  test('an account change during a save never carries its unknown outcome to the next account', () async {
    final port = _saved()..holdOfficialSave = Completer<void>();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await c.refresh();
    await c.refreshOfficialRuntimePrivacy();
    c.editOfficialFields(3);
    final save = c.save();
    await port.saveStarted.future;

    // Account A is replaced while its save is in flight.
    port.changes.add(null);
    await _drain();
    expect(c.officialSaveStage, OfficialPrivacySaveStage.idle);

    // Account B's settings and scope read successfully; A's stage stays gone.
    port.holdOfficialSave!.complete();
    await save;
    await c.refresh();
    await c.refreshOfficialRuntimePrivacy();
    expect(c.officialScope, isNotNull);
    expect(c.officialSaveStage, OfficialPrivacySaveStage.idle);
  });

  testWidgets('a refused choice reads as one instruction on the card and the save bar', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final port = _refused();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    final sync = createSyncPrivacyModule(InMemorySyncPrivacyAdapter.forReview());
    await sync.initialize();
    await c.refresh();
    await c.refreshOfficialRuntimePrivacy();
    expect(c.officialReconfirmRequired, isTrue);
    await tester.pumpWidget(app(PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync)));
    await tester.pumpAndSettle();

    expect(find.text('主舰队共享范围需要重新确认，点“保存更改”即可。'), findsOneWidget);
    expect(find.text('没有未保存的更改'), findsNothing);
    expect(find.text('需要重新确认：点“保存更改”即可恢复。'), findsOneWidget);
    expect(find.text('当前范围选择已保存；实际共享以服务器确认为准。'), findsNothing);
    expect(find.byKey(const Key('privacy-official-save-stage')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an account still settling at startup shows a wait, then loads by itself', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final port = _saved()..accountNotReadyReads = 1;
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    c.open();
    await tester.pumpAndSettle();
    expect(c.status, LocalPrivacyStatus.signedOut);
    expect(c.hasReadOnce, isFalse);
    expect(find.text('正在确认账号，确认后会自动读取。'), findsOneWidget);
    expect(find.text('请先确认账号登录状态，再重新读取隐私设置。'), findsNothing);

    // The periodic read recovers without the user pressing anything.
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(c.status, LocalPrivacyStatus.ready);
    expect(c.hasReadOnce, isTrue);
    expect(find.text('正在确认账号，确认后会自动读取。'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a genuinely signed-out first launch shows the sign-in prompt after the wait', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final port = _saved()..accountNotReadyReads = 1000;
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    c.open();
    await tester.pumpAndSettle();
    expect(find.text('正在确认账号，确认后会自动读取。'), findsOneWidget);

    await tester.pump(const Duration(seconds: 46));
    await tester.pump();
    expect(find.text('请先确认账号登录状态，再重新读取隐私设置。'), findsOneWidget,
        reason: 'the startup wait is bounded');
    expect(find.text('正在确认账号，确认后会自动读取。'), findsNothing);
    final readsAfterLimit = port.calls.where((call) => call == 'localRead').length;
    await tester.pump(const Duration(seconds: 16));
    expect(port.calls.where((call) => call == 'localRead').length, greaterThan(readsAfterLimit),
        reason: 'reads keep retrying so a late sign-in still recovers');

    port.accountNotReadyReads = 0;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(c.status, LocalPrivacyStatus.ready);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving the page during the startup wait stops its timer', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final port = _saved()..accountNotReadyReads = 1000;
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    c.open();
    await tester.pumpAndSettle();
    expect(find.text('正在确认账号，确认后会自动读取。'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));

    await tester.pumpWidget(const SizedBox.shrink());
    var notified = 0;
    c.addListener(() => notified++);
    await tester.pump(const Duration(seconds: 46));
    expect(notified, 0, reason: 'a closed page leaves no wait timer behind');
  });

  testWidgets('after a successful read an account error keeps the sign-in warning', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final port = _saved();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.hasReadOnce, isTrue);
    port.accountNotReadyReads = 1;
    await c.refresh();
    expect(c.status, LocalPrivacyStatus.signedOut);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('请先确认账号登录状态，再重新读取隐私设置。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the save bar shows the unloaded status before scope settings load', (tester) async {
    viewport(tester, const Size(1280, 1000));
    final port = _saved()..accountNotReadyReads = 1;
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    final sync = createSyncPrivacyModule(InMemorySyncPrivacyAdapter.forReview());
    await sync.initialize();
    await c.refresh();
    expect(c.draft, isNull);
    await tester.pumpWidget(app(PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync)));
    await tester.pump();
    expect(find.text('隐私设置还没读出来，读出来以后才能修改。'), findsOneWidget);
    expect(find.text('没有未保存的更改'), findsNothing);
    // Let the bounded startup wait run out before the tree is torn down.
    await tester.pump(const Duration(seconds: 46));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
