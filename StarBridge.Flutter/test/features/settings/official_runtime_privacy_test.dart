import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/official_runtime_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'local_privacy_page_test.dart' show app, viewport;

void main() {
  test(
    'read does not inherit legacy Fleet or community choices or consent',
    () async {
      final port = OfficialPrivacyFixture();
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      expect(model.officialDraftFields, 0);
      expect(model.dirty, isFalse);
      expect(port.calls, ['localRead', 'publication.status', 'scopeRead']);
      expect(port.applies, 0);
    },
  );

  test(
    'ordinary save then official choice renews common lease before one Apply',
    () async {
      final port = OfficialPrivacyFixture();
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      port.calls.clear();
      model.edit(model.draft!.copyWith(roomFields: 1));
      model.editOfficialFields(15);
      expect(await model.save(), isTrue);
      expect(port.calls, [
        'localSave',
        'officialSave',
        'localRead',
        'scopeRead',
        'publication.apply',
      ]);
      expect(model.revision, 3);
      expect(model.officialSaveStage, OfficialPrivacySaveStage.applied);
      expect(model.dirty, isFalse);
      expect(port.settings.roomFields, 1);
      expect(port.applies, 1);
    },
  );

  test('only official edits do not rewrite ordinary settings', () async {
    final port = OfficialPrivacyFixture();
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await model.refresh();
    port.calls.clear();
    model.editOfficialFields(1);
    expect(await model.save(), isTrue);
    expect(port.calls, [
      'officialSave',
      'localRead',
      'scopeRead',
      'publication.apply',
    ]);
    expect(model.revision, 2);
  });

  test('accepted official save plus failed lease read remains local saved, not reapplied', () async {
    final port = OfficialPrivacyFixture();
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await model.refresh();
    model.editOfficialFields(1);
    port.failReadAfterSave = true;
    expect(await model.save(), isFalse);
    expect(model.officialSaveStage, OfficialPrivacySaveStage.localSaved);
    expect(model.needsReload, isTrue);
    expect(port.applies, 0);
    port.failReadAfterSave = false;
    await model.refresh();
    expect(port.calls.where((s) => s == 'officialSave'), hasLength(1));
    expect(port.applies, 0);
  });

  test(
    'ordinary commit then known official rejection exposes partial save',
    () async {
      final port = OfficialPrivacyFixture()
        ..officialError = const BridgeClientException('privacy_local.conflict');
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      model.edit(model.draft!.copyWith(roomFields: 1));
      model.editOfficialFields(1);
      expect(await model.save(), isFalse);
      expect(model.officialSaveStage, OfficialPrivacySaveStage.partial);
      expect(port.settings.roomFields, 1);
      expect(port.savedFields, 0);
      expect(port.applies, 0);
    },
  );

  test(
    'unknown official save is fenced and background reads never replay it',
    () async {
      final port = OfficialPrivacyFixture()
        ..officialError = const BridgeClientException('bridge.timeout');
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      model.editOfficialFields(1);
      expect(await model.save(), isFalse);
      expect(model.officialSaveStage, OfficialPrivacySaveStage.unknown);
      expect(model.canSave, isFalse);
      await model.refresh();
      expect(port.calls.where((s) => s == 'officialSave'), hasLength(1));
      expect(port.applies, 0);
    },
  );

  test(
    'new opaque scope clears positive draft and retains exact old cancellation',
    () async {
      final port = OfficialPrivacyFixture()..savedFields = 15;
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      model.editOfficialFields(1);
      port.scopeVersion = 2;
      await model.refreshOfficialRuntimePrivacy();
      expect(model.officialDraftFields, 0);
      expect(model.officialScope!.savedForCurrentSource, isFalse);
      expect(model.canCancelOfficial, isTrue);
      model.chooseCancelSavedOfficialScope();
      expect(await model.save(), isTrue);
      expect(port.lastCancelled, isTrue);
      expect(port.savedFields, 0);
    },
  );

  test('same scope refresh preserves a new draft without writing it', () async {
    final port = OfficialPrivacyFixture();
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await model.refresh();
    model.editOfficialFields(1);
    await model.refreshOfficialRuntimePrivacy();
    expect(model.officialDraftFields, 1);
    expect(model.officialDirty, isTrue);
    expect(port.calls.where((s) => s.endsWith('Save')), isEmpty);
  });

  test(
    'source retirement during save cannot Apply late local result',
    () async {
      final port = OfficialPrivacyFixture()
        ..holdOfficialSave = Completer<void>();
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      model.editOfficialFields(1);
      final pending = model.save();
      await port.saveStarted.future;
      port.scopeVersion = 2;
      port.scopeChanges.add(null);
      await Future<void>.delayed(Duration.zero);
      port.holdOfficialSave!.complete();
      expect(await pending, isFalse);
      expect(port.applies, 0);
      expect(model.officialDraftFields, isNull);
    },
  );

  test(
    'unsupported Host retains the existing disabled card behavior',
    () async {
      final port = OfficialPrivacyFixture()..supported = false;
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      expect(port.calls, isNot(contains('scopeRead')));
      model.editOfficialFields(15);
      expect(model.officialDirty, isFalse);
    },
  );

  test('source retirement during pending Apply keeps unknown and rejects late success', () async {
    final port = OfficialPrivacyFixture()..holdApply = Completer<void>();
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await model.refresh();
    model.editOfficialFields(1);
    final pending = model.save();
    await port.applyStarted.future;
    expect(model.publicationBusy, isTrue);
    port.scopeVersion = 2;
    port.scopeChanges.add(null);
    await Future<void>.delayed(Duration.zero);
    port.holdApply!.complete();
    expect(await pending, isFalse);
    expect(model.officialSaveStage, OfficialPrivacySaveStage.unknown);
    expect(model.officialScope, isNull);
    expect(port.applies, 1);
    await model.refresh();
    expect(model.officialDraftFields, 0);
    expect(port.applies, 1);
  });

  testWidgets(
    'same settings card edits fields and existing save action commits',
    (tester) async {
      viewport(tester, const Size(1280, 1000));
      final port = OfficialPrivacyFixture();
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: model)));
      await tester.pumpAndSettle();
      final field = find.byKey(
        const Key('privacy-scope-official-fleet-field-presence'),
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(model.officialDraftFields, 1);
      await tester.tap(find.byKey(const Key('privacy-save')));
      await tester.pumpAndSettle();
      expect(port.savedFields, 1);
      expect(port.applies, 1);
      expect(
        find.byKey(const Key('privacy-official-save-stage')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class OfficialPrivacyFixture
    implements
        LocalPrivacyPort,
        PrivacyPublicationPort,
        OfficialRuntimePrivacyPort {
  final changes = StreamController<void>.broadcast();
  final scopeChanges = StreamController<void>.broadcast();
  final calls = <String>[];
  var settings = LocalPrivacySettings.editorDefaults.copyWith(communities: []);
  int revision = 1,
      savedFields = 0,
      savedScope = 1,
      scopeVersion = 1,
      applies = 0;
  bool supported = true, lastCancelled = false, failReadAfterSave = false;
  bool choiceRequired = false;
  bool audienceSupported = false;
  int? savedAudience;
  OfficialFleetAudience? lastAudience;
  String sourceRef = 'officialFleet:7';
  int failLocalReads = 0;
  Object? officialError;
  Object? publicationError;
  Completer<void>? holdOfficialSave;
  Completer<void>? holdApply;
  final saveStarted = Completer<void>();
  final applyStarted = Completer<void>();
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get publicationSupported => true;
  @override
  bool get officialRuntimePrivacySupported => supported;
  @override
  Stream<void> get officialRuntimePrivacyInvalidations => scopeChanges.stream;
  LocalPrivacySnapshot get snapshot => LocalPrivacySnapshot(
    revision: revision,
    settings: settings,
    savedAt: DateTime.utc(2026),
  );
  @override
  Future<LocalPrivacySnapshot> read() async {
    calls.add('localRead');
    if (failLocalReads > 0) {
      failLocalReads--;
      throw StateError('synthetic initial local read failure');
    }
    if (failReadAfterSave && savedFields != 0) {
      throw StateError('synthetic read failure');
    }
    return snapshot;
  }

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings next) async {
    calls.add('localSave');
    settings = next;
    revision++;
    return snapshot;
  }

  @override
  Future<OfficialRuntimePrivacySnapshot> readOfficialRuntimePrivacy() async {
    calls.add('scopeRead');
    return OfficialRuntimePrivacySnapshot(
      state: 'available',
      revision: revision,
      fields: choiceRequired
          ? 15
          : savedScope == scopeVersion
          ? savedFields
          : 0,
      savedFields: savedFields,
      savedForCurrentSource: !choiceRequired && savedScope == scopeVersion,
      choiceRequired: choiceRequired,
      canSave: true,
      canCancel: savedFields != 0,
      sourceRef: sourceRef,
      scopeRef: '$scopeVersion'.padLeft(32, '0'),
      contextRef: 'a' * 32,
      cancelContextRef: 'b' * 32,
      maximumRankValue: savedAudience,
      audienceRankSupported: audienceSupported,
    );
  }

  @override
  Future<OfficialRuntimePrivacySaveReceipt> saveOfficialRuntimePrivacy({
    required OfficialRuntimePrivacySnapshot scope,
    required int expectedRevision,
    required int fields,
    required bool cancelSavedScope,
    OfficialFleetAudience? audience,
  }) async {
    calls.add('officialSave');
    expect(expectedRevision, revision);
    if (!saveStarted.isCompleted) saveStarted.complete();
    if (holdOfficialSave != null) await holdOfficialSave!.future;
    if (officialError != null) throw officialError!;
    lastCancelled = cancelSavedScope;
    lastAudience = audience;
    choiceRequired = false;
    savedFields = fields;
    if (audience != null) savedAudience = audience.maximumRankValue;
    // Like the Host: sharing nothing keeps no audience.
    if (fields == 0) savedAudience = null;
    if (cancelSavedScope) savedAudience = null;
    if (!cancelSavedScope) savedScope = scopeVersion;
    return OfficialRuntimePrivacySaveReceipt(++revision, fields, savedAudience);
  }

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    calls.add('publication.$action');
    if (action == 'apply' || action == 'applyPreservingPause') {
      if (publicationError != null) throw publicationError!;
      expect(revision, this.revision);
      applies++;
      if (!applyStarted.isCompleted) applyStarted.complete();
      if (holdApply != null) await holdApply!.future;
      return PrivacyPublicationView('applied', revision: revision);
    }
    return const PrivacyPublicationView('inactive');
  }

  @override
  Future<void> close() async {
    await changes.close();
    await scopeChanges.close();
  }
}
