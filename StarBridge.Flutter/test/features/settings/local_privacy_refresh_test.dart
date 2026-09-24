import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

void main() {
  testWidgets('unchanged renewals preserve confirmation scope', (tester) async {
    final port = _Port();
    final controller = LocalPrivacyController(port)..open();
    addTearDown(controller.dispose);
    await tester.pump();
    final epoch = controller.scopeEpoch;
    await tester.pump(const Duration(seconds: 15));
    expect(port.reads, 2);
    expect(controller.scopeEpoch, epoch);
    controller.closeEditor();
  });

  testWidgets('account invalidation rejects a late background snapshot', (
    tester,
  ) async {
    final port = _Port();
    final controller = LocalPrivacyController(port)..open();
    addTearDown(controller.dispose);
    await tester.pump();
    port.pending = Completer<LocalPrivacySnapshot>();
    await tester.pump(const Duration(seconds: 15));
    controller.closeEditor();
    port.events.add(null);
    await tester.pump();
    port.pending!.complete(
      LocalPrivacySnapshot(
        revision: 99,
        settings: LocalPrivacySettings.editorDefaults,
      ),
    );
    await tester.pump();
    expect(controller.draft, isNull);
    expect(controller.revision, 0);
    expect(port.writes, 0);
  });

  testWidgets('clean editor renews settings without clearing visible content', (
    tester,
  ) async {
    final port = _Port();
    final controller = LocalPrivacyController(port)..open();
    addTearDown(controller.dispose);
    await tester.pump();
    final original = controller.draft;
    port.pending = Completer<LocalPrivacySnapshot>();
    await tester.pump(const Duration(seconds: 15));
    expect(port.reads, 2);
    expect(controller.draft, same(original));
    expect(controller.status, LocalPrivacyStatus.ready);
    expect(controller.canEdit, false);
    expect(await controller.save(), false);
    port.pending!.complete(
      LocalPrivacySnapshot(
        revision: 2,
        settings: LocalPrivacySettings.editorDefaults.copyWith(roomFields: 1),
      ),
    );
    await tester.pump();
    expect(controller.revision, 2);
    expect(controller.draft!.roomFields, 1);
    expect(port.writes, 0);
    controller.closeEditor();
  });

  testWidgets(
    'background read failure preserves content and retries automatically',
    (tester) async {
      final port = _Port();
      final controller = LocalPrivacyController(port)..open();
      addTearDown(controller.dispose);
      await tester.pump();
      final original = controller.draft;
      port.failure = const BridgeClientException('host.unavailable');
      await tester.pump(const Duration(seconds: 15));
      expect(controller.draft, same(original));
      expect(controller.canEdit, false);
      port.failure = null;
      await tester.pump(const Duration(seconds: 15));
      expect(port.reads, 3);
      expect(controller.canEdit, true);
      controller.closeEditor();
    },
  );

  testWidgets('dirty draft is never reread or automatically saved', (
    tester,
  ) async {
    final port = _Port();
    final controller = LocalPrivacyController(port)..open();
    addTearDown(controller.dispose);
    await tester.pump();
    controller.edit(controller.draft!.copyWith(roomFields: 0));
    await tester.pump(const Duration(minutes: 2));
    expect(port.reads, 1);
    expect(port.writes, 0);
    expect(controller.draft!.roomFields, 0);
    controller.closeEditor();
    controller.discard();
    await tester.pump(const Duration(minutes: 1));
    expect(port.reads, 1);
  });
}

class _Port implements LocalPrivacyPort {
  final events = StreamController<void>.broadcast();
  int reads = 0, writes = 0;
  Object? failure;
  Completer<LocalPrivacySnapshot>? pending;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<LocalPrivacySnapshot> read() async {
    reads++;
    if (failure case final error?) throw error;
    if (pending case final value?) return value.future;
    return LocalPrivacySnapshot(
      revision: 1,
      settings: LocalPrivacySettings.editorDefaults,
    );
  }

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) async {
    writes++;
    return LocalPrivacySnapshot(revision: 2, settings: settings);
  }

  @override
  Future<void> close() => events.close();
}
