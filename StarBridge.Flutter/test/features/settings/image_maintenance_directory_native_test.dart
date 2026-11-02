import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;
import '../../design_system/interaction/interaction_batch3do_test.dart'
    show size, loadFonts;
import 'image_maintenance_retained_workspace_test.dart'
    show settings, openMaintenance, confirmClear;

/// Payloads originate in CommunityClient and the original Native diagnostics
/// dispatcher. This is an internal transport harness, not account acceptance.
class NativeDirectoryHost extends CommunityHarness implements NativeHostLease {
  NativeDirectoryHost(this.wire)
    : super(
        capabilities: [
          'communities.read',
          'communities.media',
          'diagnostics.clearImageCache',
        ],
      );
  final Map<String, dynamic> wire;
  bool purged = false;
  Completer<void>? mediaGate;
  Completer<void>? directoryGate;
  final _terminated = Completer<NativeHostTermination>();
  bool _closed = false;
  @override
  Future<NativeHostTermination> get terminated => _terminated.future;
  @override
  Future<void> reply(BridgeEnvelope request) async {
    final before = !purged;
    Map<String, Object?>? payload;
    String? error;
    switch (request.name) {
      case 'communities.read':
        expectSync(request.payload['view'], 'discover');
        payload = Map<String, Object?>.from(wire[before ? 'before' : 'after']);
        if (directoryGate case final gate?) await gate.future;
      case 'communities.media':
        final page = wire[before ? 'before' : 'after'] as Map;
        if (request.payload['targetRef'] !=
            (page['items'] as List).single['targetRef']) {
          error = wire['retiredError'] as String;
        } else {
          payload = Map<String, Object?>.from(
            wire[before ? 'beforeMedia' : 'afterMedia'],
          );
        }
        if (mediaGate case final gate?) await gate.future;
      case 'diagnostics.clearImageCache':
        purged = true;
        payload = Map<String, Object?>.from(wire['clear']);
      default:
        return super.reply(request);
    }
    await connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: request.accountContext,
        status: error == null ? 'ok' : 'error',
        error: error == null
            ? null
            : BridgeErrorBody(
                code: error,
                message: 'Retired media reference',
                retryable: false,
              ),
        payload: payload ?? const {},
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final gate in [mediaGate, directoryGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await super.close();
  }
}

void main() {
  final path =
      Platform.environment['STARBRIDGE_DIRECTORY_IMAGE_MAINTENANCE_FIXTURE'];
  final missing = path == null || !File(path).existsSync();
  Map<String, dynamic> wire() =>
      jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>;
  setUpAll(loadFonts);
  test('actual Native retired reference requires a fresh directory, preserving identity', () async {
    final host = NativeDirectoryHost(wire());
    addTearDown(host.close);
    final before = await host.adapter.read(view: 'discover', query: '');
    expect(before.items.single.logo, isNotNull);
    await host.session.request(
      'diagnostics.clearImageCache',
      payload: {'schemaVersion': 1},
    );
    await expectLater(
      host.adapter.readMedia(before.items.single.targetRef, 'logo', offset: 0),
      throwsA(
        isA<CommunityFailure>().having(
          (e) => e.code,
          'code',
          'refreshRequired',
        ),
      ),
    );
    final after = await host.adapter.read(view: 'discover', query: '');
    expect(after.items.single.targetRef, isNot(before.items.single.targetRef));
    expect(after.items.single.key, before.items.single.key);
    expect(after.items.single.logo, before.items.single.logo);
    expect(
      host.requests.any(
        (r) =>
            r.name == 'communities.workspace' ||
            r.name == 'communities.execute',
      ),
      isFalse,
    );
  }, skip: missing ? 'Requires original Native producer transcript' : false);

  for (final held in ['directory', 'media']) {
    test(
      'Native $held response started before purge keeps metadata but drops old bytes',
      () async {
        final host = NativeDirectoryHost(wire());
        addTearDown(host.close);
        final gate = Completer<void>();
        if (held == 'directory') {
          host.directoryGate = gate;
        } else {
          host.mediaGate = gate;
        }
        final reading = host.adapter.read(view: 'discover', query: '');
        final name = held == 'directory'
            ? 'communities.read'
            : 'communities.media';
        while (!host.requests.any((r) => r.name == name)) {
          await Future<void>.delayed(Duration.zero);
        }
        host.adapter.beginImageMaintenance();
        await host.session.request(
          'diagnostics.clearImageCache',
          payload: {'schemaVersion': 1},
        );
        host.adapter.endImageMaintenance();
        gate.complete();
        final result = await reading;
        expect(result.items.single.logo == null, isTrue);
        expect(result.items.single.name, 'PUBLIC');
        expect(result.items.single.tags, '探索');
        host.directoryGate = host.mediaGate = null;
        final fresh = await host.adapter.read(view: 'discover', query: '');
        expect(fresh.items.single.logo != null, isTrue);
        expect(fresh.items.single.key, result.items.single.key);
        expect(
          fresh.items.single.targetRef,
          isNot(result.items.single.targetRef),
        );
      },
      skip: missing ? 'Requires original Native producer transcript' : false,
    );
  }

  test('new directory reads during maintenance publish names without downloading images', () async {
    final host = NativeDirectoryHost(wire());
    addTearDown(host.close);
    host.adapter.beginImageMaintenance();
    final result = await host.adapter.read(view: 'discover', query: '');
    final metadata = await host.adapter.readDirectoryMetadata(
      view: 'discover',
      query: '',
    );
    expect(result.items.single.logo == null, isTrue);
    expect(metadata.items.single.name, result.items.single.name);
    expect(host.requests.where((r) => r.name == 'communities.media'), isEmpty);
    host.adapter.endImageMaintenance();
    expect(
      (await host.adapter.read(
            view: 'discover',
            query: '',
          )).items.single.logo !=
          null,
      isTrue,
    );
  }, skip: missing ? 'Requires original Native producer transcript' : false);

  testWidgets(
    'production settings purge retires directory logos and renews Native references on reentry',
    (t) async {
      size(t, const Size(1600, 1100));
      final host = NativeDirectoryHost(wire());
      final preferences = InMemoryAppPreferences();
      final app = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
        windowChrome: InMemoryWindowChrome(),
      );
      try {
        final reading = app.communities.refresh(newView: 'discover');
        await t.pump();
        await reading;
        final before = app.communities.directory!;
        expect(before.items.single.logo, isNotNull);
        await t.pumpWidget(settings(app));
        await t.pumpAndSettle();
        await openMaintenance(t);
        await confirmClear(t);
        await t.pumpAndSettle();
        expect(host.purged, isTrue);
        final cleared = app.communities.directory!;
        expect(cleared.items.single.logo == null, isTrue);
        expect(cleared.items.single.key, before.items.single.key);
        expect(
          cleared.items.single.description,
          before.items.single.description,
        );
        expect(cleared.items.single.actions, before.items.single.actions);
        expect(cleared.totalCount, before.totalCount);
        expect(app.communities.view, 'discover');
        final fresh = app.communities.refresh(reuseFresh: true);
        await t.pump();
        await fresh;
        expect(
          app.communities.directory!.items.single.logo,
          before.items.single.logo,
        );
        expect(
          app.communities.directory!.items.single.targetRef,
          isNot(before.items.single.targetRef),
        );
        expect(
          host.requests.where((r) => r.name == 'communities.read').length,
          2,
        );
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        app.dispose();
        await t.pump();
        await host.close();
        preferences.dispose();
        await t.pump(Duration.zero);
      }
    },
    skip: missing,
  );
}
