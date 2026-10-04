import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'bridge_local_privacy_test.dart' show Harness;
import 'local_privacy_page_test.dart' show ConfidencePrivacy, app, viewport;

class BackgroundPrivacyPort extends ConfidencePrivacy
    implements PrivacyPublicationPort, CommunitySharingPort {
  BackgroundPrivacyPort() {
    snapshot = LocalPrivacySnapshot(
      revision: 1,
      settings: LocalPrivacySettings.editorDefaults.copyWith(
        publicationEnabled: true,
        roomFields: 15,
        roomAllMembersCanView: true,
        hideLowConfidenceLocation: true,
      ),
    );
  }
  int reads = 0;
  Completer<LocalPrivacySnapshot>? pending;
  Completer<PrivacyPublicationView>? pendingStatus;
  final actions = <String>[];
  @override
  Future<LocalPrivacySnapshot> read() async {
    reads++;
    return pending?.future ?? snapshot;
  }

  @override
  bool get publicationSupported => true;
  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    actions.add(action);
    if (action == 'status' && pendingStatus != null) {
      return pendingStatus!.future;
    }
    return PrivacyPublicationView(
      action == 'stop' ? 'withdrawn' : 'applied',
      revision: revision ?? snapshot.revision,
    );
  }

  @override
  bool get communitySharingSupported => true;
  @override
  Future<CommunitySharingTargets> readCommunityTargets() async =>
      CommunitySharingTargets(primaryFleetCode: null, communities: []);
}

void main() {
  testWidgets(
    'three healthy periodic reads keep all privacy controls editable',
    (tester) async {
      viewport(tester, const Size(1440, 2000));
      final port = BackgroundPrivacyPort();
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: controller)));
      await tester.pumpAndSettle();
      void expectEditable() {
        expect(
          tester
              .widget<Switch>(find.byKey(const Key('privacy-publication')))
              .onChanged,
          isNotNull,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('privacy-location-confidence')),
              )
              .onChanged,
          isNotNull,
        );
        final room = find.byKey(const Key('privacy-scope-room'));
        final fields = tester.widgetList<Switch>(
          find.descendant(of: room, matching: find.byType(Switch)),
        );
        expect(fields, hasLength(4));
        expect(fields.every((field) => field.onChanged != null), true);
        expect(
          tester
              .widget<Checkbox>(
                find.descendant(of: room, matching: find.byType(Checkbox)),
              )
              .onChanged,
          isNotNull,
        );
      }

      expectEditable();
      for (var tick = 1; tick <= 3; tick++) {
        port.pending = Completer<LocalPrivacySnapshot>();
        await tester.pump(const Duration(seconds: 15));
        expect(port.reads, tick + 1);
        expectEditable();
        expect(controller.publicationView.state, 'applied');
        expect(port.writes, 0);
        port.pending!.complete(port.snapshot);
        await tester.pumpAndSettle();
        expectEditable();
      }
      expect(port.actions.every((action) => action == 'status'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('editing during read survives; explicit save waits for renewed authority once', () async {
    final port = BackgroundPrivacyPort();
    final controller = LocalPrivacyController(port);
    addTearDown(controller.dispose);
    await controller.refresh();
    port.pending = Completer<LocalPrivacySnapshot>();
    final reading = controller.refresh(silently: true);
    controller.edit(controller.draft!.copyWith(roomFields: 0));
    expect(controller.draft!.roomFields, 0);
    expect(controller.canSave, true);
    final saving = controller.save(refreshStatus: false);
    expect(controller.saving, true);
    expect(await controller.save(refreshStatus: false), false);
    expect(port.writes, 0);
    port.pending!.complete(port.snapshot);
    await reading;
    expect(await saving, true);
    expect(controller.draft!.roomFields, 0);
    expect(port.writes, 1);
    expect(controller.dirty, false);
    expect(controller.saving, false);
  });

  testWidgets('a real control edit survives the delayed periodic reply', (
    tester,
  ) async {
    viewport(tester, const Size(1440, 2000));
    final port = BackgroundPrivacyPort();
    final controller = LocalPrivacyController(port);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: controller)));
    await tester.pumpAndSettle();
    port.pending = Completer<LocalPrivacySnapshot>();
    await tester.pump(const Duration(seconds: 15));
    await tester.tap(find.byKey(const Key('privacy-location-confidence')));
    await tester.pump();
    expect(controller.draft!.hideLowConfidenceLocation, false);
    port.pending!.complete(port.snapshot);
    await tester.pumpAndSettle();
    expect(controller.draft!.hideLowConfidenceLocation, false);
    expect(controller.dirty, true);
    expect(port.writes, 0);
    expect(port.actions.every((action) => action == 'status'), true);
    await tester.pumpWidget(const SizedBox());
  });

  for (final queueSave in [false, true]) {
    test(
      'changed revision preserves in-flight draft and refuses stale save: $queueSave',
      () async {
        final port = BackgroundPrivacyPort();
        final controller = LocalPrivacyController(port);
        addTearDown(controller.dispose);
        await controller.refresh();
        port.pending = Completer<LocalPrivacySnapshot>();
        final reading = controller.refresh(silently: true);
        controller.edit(controller.draft!.copyWith(roomFields: 0));
        final saving = queueSave ? controller.save(refreshStatus: false) : null;
        port.pending!.complete(
          LocalPrivacySnapshot(
            revision: 2,
            settings: port.snapshot.settings!.copyWith(roomFields: 1),
          ),
        );
        await reading;
        if (saving != null) expect(await saving, false);
        expect(controller.draft!.roomFields, 0);
        expect(controller.needsReload, true);
        expect(controller.errorKey, 'privacy.local.conflict');
        expect(controller.canSave, false);
        expect(controller.saving, false);
        expect(port.writes, 0);
      },
    );
  }

  test(
    'failed background read keeps new draft but closes save authority',
    () async {
      final port = BackgroundPrivacyPort();
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      port.pending = Completer<LocalPrivacySnapshot>();
      final reading = controller.refresh(silently: true);
      controller.edit(controller.draft!.copyWith(roomFields: 0));
      port.pending!.completeError(
        const BridgeClientException('host.unavailable'),
      );
      await reading;
      expect(controller.draft!.roomFields, 0);
      expect(controller.needsReload, true);
      expect(controller.canSave, false);
      expect(await controller.save(refreshStatus: false), false);
      expect(port.writes, 0);
    },
  );

  test(
    'account invalidation wakes queued save before late read returns',
    () async {
      final port = BackgroundPrivacyPort();
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      port.pending = Completer<LocalPrivacySnapshot>();
      final reading = controller.refresh(silently: true);
      controller.edit(controller.draft!.copyWith(roomFields: 0));
      bool? saved;
      final saving = controller
          .save(refreshStatus: false)
          .then((value) => saved = value);
      port.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(saved, false);
      expect(controller.draft, isNull);
      expect(controller.saving, false);
      port.pending!.complete(port.snapshot);
      await reading;
      await saving;
      expect(controller.draft, isNull);
      expect(port.writes, 0);
    },
  );

  test('failed read cancels a queued save without publishing', () async {
    final port = BackgroundPrivacyPort();
    final controller = LocalPrivacyController(port);
    addTearDown(controller.dispose);
    await controller.refresh();
    port.pending = Completer<LocalPrivacySnapshot>();
    final reading = controller.refresh(silently: true);
    controller.edit(controller.draft!.copyWith(roomFields: 0));
    final saving = controller.save();
    port.pending!.completeError(
      const BridgeClientException('host.unavailable'),
    );
    await reading;
    expect(await saving, false);
    expect(controller.draft!.roomFields, 0);
    expect(controller.saving, false);
    expect(controller.needsReload, true);
    expect(port.writes, 0);
    expect(port.actions.every((action) => action == 'status'), true);
  });

  test(
    'disposal releases a queued save without using the late reply',
    () async {
      final port = BackgroundPrivacyPort();
      final controller = LocalPrivacyController(port);
      await controller.refresh();
      port.pending = Completer<LocalPrivacySnapshot>();
      final reading = controller.refresh(silently: true);
      controller.edit(controller.draft!.copyWith(roomFields: 0));
      final saving = controller.save(refreshStatus: false);
      controller.dispose();
      expect(await saving, false);
      port.pending!.complete(port.snapshot);
      await reading;
      expect(port.writes, 0);
    },
  );

  test(
    'status query keeps editing live and explicit write waits behind it',
    () async {
      final port = BackgroundPrivacyPort();
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      port.pendingStatus = Completer<PrivacyPublicationView>();
      final status = controller.refreshPublication();
      expect(controller.canEdit, true);
      expect(controller.publicationBusy, false);
      controller.edit(controller.draft!.copyWith(roomFields: 0));
      final saving = controller.save(refreshStatus: false);
      expect(port.writes, 0);
      port.pendingStatus!.complete(
        const PrivacyPublicationView('applied', revision: 1),
      );
      await status;
      expect(await saving, true);
      expect(port.writes, 1);
      expect(controller.draft!.roomFields, 0);
    },
  );

  test(
    'explicit apply queues behind status and still protects controls',
    () async {
      final port = BackgroundPrivacyPort();
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      port.pendingStatus = Completer<PrivacyPublicationView>();
      final status = controller.refreshPublication();
      final applying = controller.applyPublication();
      expect(controller.publicationBusy, true);
      expect(controller.canEdit, false);
      expect(port.actions.where((action) => action == 'apply'), isEmpty);
      port.pendingStatus!.complete(
        const PrivacyPublicationView('applied', revision: 1),
      );
      await status;
      await applying;
      expect(port.actions.where((action) => action == 'apply'), hasLength(1));
      expect(controller.publicationBusy, false);
      expect(controller.canEdit, true);
    },
  );

  test(
    'real Bridge queues save until background read restores revision grant',
    () async {
      final host = Harness();
      final controller = LocalPrivacyController(host.adapter);
      addTearDown(() async {
        controller.dispose();
        await host.close();
      });
      await controller.refresh();
      host.connection.holdRead = Completer<void>();
      final reading = controller.refresh(silently: true);
      await host.connection.readStarted.future;
      controller.edit(controller.draft!.copyWith(roomFields: 0));
      expect(controller.canSave, true);
      final saving = controller.save(refreshStatus: false);
      expect(host.connection.saves, isEmpty);
      host.connection.holdRead!.complete();
      await reading;
      expect(await saving, true);
      expect(host.connection.saves, hasLength(1));
      expect(controller.draft!.roomFields, 0);
      expect(controller.errorKey, isNull);
    },
  );

  testWidgets('selected field switches relinquish active color while saving', (
    tester,
  ) async {
    viewport(tester, const Size(1440, 2000));
    final port = BackgroundPrivacyPort();
    final controller = LocalPrivacyController(port);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: controller)));
    await tester.pumpAndSettle();
    controller.edit(
      controller.draft!.copyWith(hideLowConfidenceLocation: false),
    );
    port.pendingSave = Completer<LocalPrivacySnapshot>();
    final saving = controller.save(refreshStatus: false);
    await tester.pump();
    final fields = tester.widgetList<Switch>(
      find.descendant(
        of: find.byKey(const Key('privacy-scope-room')),
        matching: find.byType(Switch),
      ),
    );
    expect(fields, hasLength(4));
    expect(fields.every((field) => field.onChanged == null), true);
    expect(fields.every((field) => field.activeTrackColor == null), true);
    port.pendingSave!.complete(
      LocalPrivacySnapshot(revision: 2, settings: controller.draft),
    );
    expect(await saving, true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
