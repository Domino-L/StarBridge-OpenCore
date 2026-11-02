import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_first_sharing_choice.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/official_runtime_privacy_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'local_privacy_page_test.dart' show app, viewport;
import 'official_runtime_privacy_test.dart' show OfficialPrivacyFixture;


void main() {
  test('publication account change retires official context, network failure keeps verified choice', () async {
    for (final accountChanged in [true, false]) {
      final port = OfficialPrivacyFixture()..choiceRequired = true;
      port.publicationError = accountChanged
          ? const BridgeClientException('privacy_publication.account_changed')
          : StateError('synthetic network failure');
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      expect(await model.confirmOfficialFirstChoice(15), !accountChanged);
      expect(port.savedFields, 15);
      if (accountChanged) {
        expect(model.status, LocalPrivacyStatus.signedOut);
        expect(model.officialScope, isNull);
      } else {
        expect(model.officialScope!.savedForCurrentSource, isTrue);
        expect(model.publicationView.state, 'failed');
      }
    }
  });
  for (final fields in [15, 5, 0]) {
    test('explicit first choice $fields saves only official scope', () async {
      final port = OfficialPrivacyFixture()..choiceRequired = true;
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      expect(model.officialDraftFields, 15);
      expect(port.calls, isNot(contains('officialSave')));
      expect(port.applies, 0);
      expect(model.dirty, isFalse);
      final ordinary = port.settings;
      expect(await model.confirmOfficialFirstChoice(fields), isTrue);
      expect(port.calls, isNot(contains('localSave')));
      expect(port.settings, same(ordinary));
      expect(port.savedFields, fields);
      expect(model.officialScope!.choiceRequired, isFalse);
      await model.refresh();
      expect(model.officialDraftFields, fields);
    });
  }

  test(
    'first choice cannot silently commit unrelated dirty settings',
    () async {
      final port = OfficialPrivacyFixture()..choiceRequired = true;
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      model.edit(model.draft!.copyWith(roomFields: 0));
      expect(await model.confirmOfficialFirstChoice(15), isFalse);
      expect(port.calls, isNot(contains('officialSave')));
    },
  );

  test('paused sharing stays paused after explicit choice', () async {
    final port = OfficialPrivacyFixture()..choiceRequired = true;
    port.settings = port.settings.copyWith(publicationEnabled: false);
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await model.refresh();
    expect(await model.confirmOfficialFirstChoice(15), isTrue);
    expect(port.settings.publicationEnabled, isFalse);
    expect(port.applies, 0);
  });

  test(
    'target retirement during confirmation cannot apply stale choice',
    () async {
      final port = OfficialPrivacyFixture()
        ..choiceRequired = true
        ..holdOfficialSave = Completer<void>();
      final model = LocalPrivacyController(port);
      addTearDown(model.dispose);
      await model.refresh();
      final pending = model.confirmOfficialFirstChoice(15);
      await port.saveStarted.future;
      port.scopeVersion = 2;
      port.scopeChanges.add(null);
      await Future<void>.delayed(Duration.zero);
      port.holdOfficialSave!.complete();
      expect(await pending, isFalse);
      expect(port.applies, 0);
      expect(model.officialScope, isNull);
    },
  );

  test('wire accepts explicit draft marker and rejects implicit permissive default', () {
    final body = <String, Object?>{
      'schemaVersion': 1,
      'state': 'available',
      'revision': 0,
      'sourceRef': 'officialFleet:7',
      'scopeRef': 'a' * 32,
      'contextRef': 'b' * 32,
      'cancelContextRef': null,
      'fields': 15,
      'savedFields': 0,
      'savedForCurrentSource': false,
      'canSave': true,
      'canCancel': false,
      'publicationApplied': false,
      'choiceRequired': true,
    };
    expect(OfficialRuntimePrivacySnapshot.parse(body).choiceRequired, isTrue);
    body.remove('choiceRequired');
    expect(
      () => OfficialRuntimePrivacySnapshot.parse(body),
      throwsFormatException,
    );
    body['fields'] = 0;
    expect(OfficialRuntimePrivacySnapshot.parse(body).choiceRequired, isFalse);
    body['choiceRequired'] = true;
    body['canSave'] = false;
    expect(
      () => OfficialRuntimePrivacySnapshot.parse(body),
      throwsFormatException,
    );
  });

  // User decision 2026-10-29: never-chosen members share everything with
  // their main fleet by default; a changed main fleet keeps the earlier
  // choice. Both are saved without a dialog and announced once.
  Widget page(LocalPrivacyController model) => app(
    OfficialFleetFirstSharingChoice(
      controller: model,
      sourceRef: 'officialFleet:7',
      child: const Text('fleet-content'),
    ),
  );
  final applied = find.byKey(
    const Key('official-fleet-sharing-default-applied'),
  );

  testWidgets('a member who never chose shares everything by default', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1100));
    final port = OfficialPrivacyFixture()
      ..choiceRequired = true
      ..audienceSupported = true;
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(find.text('fleet-content'), findsOneWidget);
    expect(port.savedFields, 15);
    expect(port.lastAudience?.maximumRankValue, isNull);
    expect(model.officialScope!.choiceRequired, isFalse);
    expect(applied, findsOneWidget);
    expect(find.textContaining('已按默认'), findsOneWidget);
  });

  testWidgets('a changed main fleet keeps the earlier choice and its stars', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1100));
    final port = OfficialPrivacyFixture()
      ..savedFields = 5
      ..savedScope = 1
      ..scopeVersion = 2
      ..savedAudience = 3
      ..audienceSupported = true;
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(port.savedFields, 5);
    expect(port.lastAudience?.maximumRankValue, 3);
    expect(port.savedScope, port.scopeVersion);
    expect(model.officialScope!.fleetChanged, isFalse);
    expect(find.textContaining('已沿用'), findsOneWidget);
    // Once saved, a later entry changes nothing.
    port.calls.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(port.calls, isNot(contains('officialSave')));
  });

  testWidgets('an earlier star limit this Host cannot keep is not applied', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1100));
    final port = OfficialPrivacyFixture()
      ..savedFields = 15
      ..savedScope = 1
      ..scopeVersion = 2
      ..savedAudience = 3;
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(model.officialScope!.fleetChanged, isFalse);
    expect(port.calls, isNot(contains('officialSave')));
    expect(applied, findsNothing);
  });

  testWidgets('an earlier all-off choice stays off for the new fleet', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1100));
    final port = OfficialPrivacyFixture()
      ..savedFields = 0
      ..savedScope = 1
      ..scopeVersion = 2;
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(port.calls, isNot(contains('officialSave')));
    expect(applied, findsNothing);
  });

  testWidgets('unsaved sharing edits are never committed by the default', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1100));
    final port = OfficialPrivacyFixture()..choiceRequired = true;
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await model.refresh();
    model.edit(model.draft!.copyWith(roomFields: 0));
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(port.calls, isNot(contains('officialSave')));
    expect(port.calls, isNot(contains('localSave')));
    expect(find.text('fleet-content'), findsOneWidget);
  });

  testWidgets('unsupported capability changes nothing', (tester) async {
    final port = OfficialPrivacyFixture()
      ..supported = false
      ..choiceRequired = true;
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(find.text('fleet-content'), findsOneWidget);
    expect(port.calls, isNot(contains('officialSave')));
  });

  testWidgets('a failed save leaves the page usable and tries again later', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1100));
    final port = OfficialPrivacyFixture()
      ..choiceRequired = true
      ..officialError = const BridgeClientException('privacy_local.conflict');
    final model = LocalPrivacyController(port);
    addTearDown(model.dispose);
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(find.text('fleet-content'), findsOneWidget);
    expect(applied, findsNothing);
    expect(port.savedFields, 0);
    port.officialError = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page(model));
    await tester.pumpAndSettle();
    expect(port.savedFields, 15);
    expect(applied, findsOneWidget);
  });
}
