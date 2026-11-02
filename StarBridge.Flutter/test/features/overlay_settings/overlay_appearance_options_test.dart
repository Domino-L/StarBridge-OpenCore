import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_appearance_center.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'overlay_settings_ux_a_test.dart' show settings;
import 'overlay_appearance_configuration_test.dart' show fixture;
import 'overlay_appearance_bitmap_test.dart' show tinyPng;
import '../friends/social_layout_test.dart' show app, size, loadFonts;

final _choice = _options(1);
OverlayAppearanceOptions _options(int value) =>
    const OverlayAppearanceOptions.empty().withProfile('fixture-profile', {
      'version': 1,
      'values': {
        'items': [
          {'module': 'Members', 'slot': 'upper', 'variant': value},
        ],
      },
    });

void main() {
  setUpAll(() async {
    if (Platform.environment['STARBRIDGE_APPEARANCE_CENTER_CAPTURE'] != null) {
      await loadFonts();
    }
  });
  test(
    'immutable detached values, canonical equality and profile isolation',
    () {
      final input = _choice.toMap();
      final parsed = OverlayAppearanceOptions.fromMap(input);
      (input['profiles'] as Map).clear();
      expect(parsed, _choice);
      final profile = parsed.profile('fixture-profile')!;
      (profile['values'] as Map).clear();
      expect(parsed, _choice);
      final copy = parsed.withProfile('other-profile', {
        'values': {'enabled': false},
        'version': 2,
      });
      expect(
        copy.profile('fixture-profile'),
        parsed.profile('fixture-profile'),
      );
      expect(parsed.profile('other-profile'), isNull);
      expect(copy.withProfile('other-profile', null), parsed);
      expect(
        parsed.withProfile('fixture-profile', null),
        const OverlayAppearanceOptions.empty(),
      );
      expect(
        OverlayAppearanceOptions.fromMap({
          'profiles': {
            'fixture-profile': {
              'values': parsed.profile('fixture-profile')!['values'],
              'version': 1,
            },
          },
          'schemaVersion': 1,
        }),
        parsed,
      );
      expect(parsed.hashCode, _choice.hashCode);
    },
  );

  test('bounded strict envelope rejects unsafe or malformed values', () {
    final invalid = <Map<String, Object?>>[
      {},
      {'schemaVersion': 2, 'profiles': {}},
      {'schemaVersion': 1.0, 'profiles': {}},
      {'schemaVersion': 1, 'profiles': {}, 'extra': true},
      {'schemaVersion': 1, 'profiles': []},
      {
        'schemaVersion': 1,
        'profiles': {
          'a': {'version': 0, 'values': {}},
        },
      },
      {
        'schemaVersion': 1,
        'profiles': {
          'a': {'version': 1.0, 'values': {}},
        },
      },
      {
        'schemaVersion': 1,
        'profiles': {
          'a': {'version': 1001, 'values': {}},
        },
      },
      {
        'schemaVersion': 1,
        'profiles': {
          'a': {'version': 1, 'values': []},
        },
      },
      {
        'schemaVersion': 1,
        'profiles': {
          'a': {'version': 1, 'values': {}, 'extra': 0},
        },
      },
      for (final key in [
        '__proto__',
        'prototype',
        'constructor',
        '',
        'path/to',
        'a' * 65,
      ])
        {
          'schemaVersion': 1,
          'profiles': {
            key: {'version': 1, 'values': {}},
          },
        },
      {
        'schemaVersion': 1,
        'profiles': {
          for (var i = 0; i < 9; i++) 'p$i': {'version': 1, 'values': {}},
        },
      },
      for (final value in [
        double.nan,
        double.infinity,
        'a' * 257,
        Object(),
        DateTime(2026),
      ])
        {
          'schemaVersion': 1,
          'profiles': {
            'a': {
              'version': 1,
              'values': {'value': value},
            },
          },
        },
      {
        'schemaVersion': 1,
        'profiles': {
          'a': {
            'version': 1,
            'values': {'items': List.filled(1024, 0)},
          },
        },
      },
      {
        'schemaVersion': 1,
        'profiles': {
          'a': {
            'version': 1,
            'values': {'items': List.filled(100, 'a' * 256)},
          },
        },
      },
    ];
    for (final value in invalid) {
      expect(
        () => OverlayAppearanceOptions.fromMap(value),
        throwsFormatException,
      );
    }
    Object deep = 1;
    for (var i = 0; i < 8; i++) {
      deep = [deep];
    }
    expect(
      () => const OverlayAppearanceOptions.empty().withProfile('a', {
        'version': 1,
        'values': {'deep': deep},
      }),
      throwsFormatException,
    );
  });

  test(
    'option edits save on their own; undo and redo save too and keep history',
    () async {
      final port = _Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      expect(module.projection.value.appearanceOptions, _choice);
      final next = _options(2);
      module.updateAppearanceOptions(next);
      expect(module.projection.value.dirty, isTrue, reason: 'pending write');
      await pumpEventQueue();
      expect(port.writes.single.appearanceOptions, next);
      expect(module.projection.value.dirty, isFalse);
      expect(module.projection.value.snapshot!.appearanceOptions, next);
      module.undo();
      await pumpEventQueue();
      expect(module.projection.value.appearanceOptions, _choice);
      expect(port.writes.last.appearanceOptions, _choice);
      module.redo();
      await pumpEventQueue();
      expect(module.projection.value.appearanceOptions, next);
      expect(port.writes.last.appearanceOptions, next);
      expect(module.canUndo, isTrue, reason: 'history survives saves');
      await module.openRuntime('zh');
      expect(port.draft!.appearanceOptions, next);
      expect(port.draft!.toMap()['appearanceOptions'], next.toMap());
      await module.retryRuntime('en');
      expect(port.draft!.appearanceOptions, next);
      module.updateAppearanceOptions(next);
      expect(module.projection.value.dirty, isFalse, reason: 'no-op edit');
    },
  );

  test('a failed save keeps the edit and history until a retry saves it', () async {
    final port = _Port();
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    port.failWrites = true;
    module.updateAppearanceOptions(_options(2));
    await pumpEventQueue();
    expect(port.writes.single.appearanceOptions, _options(2));
    expect(module.projection.value.failure, OverlaySettingsFailure.writeFailed);
    expect(module.projection.value.dirty, isTrue);
    expect(module.projection.value.appearanceOptions, _options(2));
    expect(module.canUndo, isTrue);
    port.failWrites = false;
    expect(await module.save(), isTrue);
    expect(module.projection.value.dirty, isFalse);
    expect(module.projection.value.failure, isNull);
    expect(module.projection.value.snapshot!.appearanceOptions, _options(2));
    module.undo();
    await pumpEventQueue();
    expect(port.writes.last.appearanceOptions, _choice);
  });

  test('plan actions save pending edits first; history lasts until the plan changes', () async {
    final port = _Port();
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    module.updateAppearanceOptions(_options(2));
    await module.renamePreset('p', 'Renamed');
    expect(port.writes.map((w) => w.kind), [
      OverlayWorkspaceMutationKind.saveActive,
      OverlayWorkspaceMutationKind.renamePreset,
    ]);
    expect(module.projection.value.appearanceOptions, _options(2));
    expect(module.projection.value.dirty, isFalse);
    module.undo();
    await pumpEventQueue();
    expect(module.projection.value.appearanceOptions, _choice);
    module.redo();
    await pumpEventQueue();
    expect(
      port.writes.last.toPayload(2)['appearanceOptions'],
      _options(2).toMap(),
    );
    module.updateAppearanceOptions(const OverlayAppearanceOptions.empty());
    await pumpEventQueue();
    expect(
      port.writes.last.appearanceOptions,
      const OverlayAppearanceOptions.empty(),
    );
    port.snapshot = _snapshot(revision: 10, options: _options(3));
    await module.activatePreset('p');
    expect(module.projection.value.appearanceOptions, _options(3));
    expect(module.canUndo, isFalse);
    port.snapshot = _snapshot(
      revision: 11,
      options: const OverlayAppearanceOptions.empty(),
    );
    await module.resetPreset('p');
    expect(
      module.projection.value.appearanceOptions,
      const OverlayAppearanceOptions.empty(),
    );
  });

  test(
    'edits save while the HUD is closed; an open HUD also gets live drafts',
    () async {
      final port = _Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      module.updateAppearanceOptions(_options(2));
      await pumpEventQueue();
      expect(port.draft, isNull, reason: 'no live draft while closed');
      expect(port.writes.single.appearanceOptions, _options(2));
      await module.openRuntime('en');
      module.updateAppearanceOptions(_options(3));
      await pumpEventQueue();
      expect(port.draft!.appearanceOptions, _options(3));
      expect(port.writes.last.appearanceOptions, _options(3));
      await module.closeRuntime('en');
      expect(port.draft, isNull);
    },
  );

  test('legacy Host remains compatible; corrupt and unsupported configs cannot be edited', () async {
    for (final state in [
      (false, 'ready', 'ready'),
      (true, 'corrupt', 'corrupt'),
      (true, 'ready', 'corrupt'),
    ]) {
      final port = _Port()
        ..snapshot = _snapshot(
          enabled: state.$1,
          storage: state.$2,
          presetStorage: state.$3,
        );
      final module = OverlayWorkspaceModule(port);
      await module.initialize();
      module.updateAppearanceOptions(_options(2));
      expect(module.canUndo, isFalse);
      expect(module.projection.value.dirty, isFalse);
      if (!state.$1) {
        module.updateSetting('showNotice', true);
        await module.openRuntime('zh');
        expect(port.draft!.toMap().containsKey('appearanceOptions'), isFalse);
        await module.save();
        expect(
          port.writes.single.toPayload(1).containsKey('appearanceOptions'),
          isFalse,
        );
      }
      module.dispose();
    }
  });

  test('Bridge parses active and per-preset options, legacy absence and invalid contracts', () async {
    final body = _body();
    final enabled = await _read(body);
    expect(enabled.appearanceOptionsEnabled, isTrue);
    expect(enabled.appearanceOptions, _choice);
    expect(enabled.presets.single.appearanceOptions, _choice);
    final legacy = _body()
      ..remove('appearanceOptions')
      ..remove('appearanceOptionsEnabled');
    ((legacy['presets'] as List).single as Map).remove('appearanceOptions');
    final old = await _read(legacy);
    expect(old.availability, OverlayWorkspaceAvailability.available);
    expect(old.appearanceOptionsEnabled, isFalse);
    expect(old.appearanceOptions, const OverlayAppearanceOptions.empty());
    final missingPreset = _body();
    ((missingPreset['presets'] as List).single as Map).remove(
      'appearanceOptions',
    );
    final malformedPreset = _body();
    ((malformedPreset['presets'] as List).single as Map)['appearanceOptions'] =
        {'schemaVersion': 2, 'profiles': {}};
    for (final invalid in [
      _body()..remove('appearanceOptions'),
      missingPreset,
      malformedPreset,
      {...body, 'appearanceOptionsEnabled': null},
      {...body, 'appearanceOptionsEnabled': 'true'},
      {...body, 'appearanceOptions': null},
      {...body, 'appearanceOptions': _options(3).toMap()},
      {
        ...body,
        'appearanceOptions': {'schemaVersion': 2, 'profiles': {}},
      },
    ]) {
      final result = await _read(invalid);
      expect(result.availability, OverlayWorkspaceAvailability.unavailable);
      expect(result.failure, OverlaySettingsFailure.invalidResponse);
    }
  });

  test('optional installed forms do not grant authority or break older workspace responses', () async {
    final ordinary = await _read(_body());
    expect(ordinary.appearanceConfigurations, isEmpty);
    final metadata = await _read({
      ..._body(),
      'appearanceConfigurations': [fixture()],
    });
    expect(metadata.appearanceConfigurations.single.profileId, 'fixture');
    expect(
      metadata.appearances.map((a) => a.id),
      ordinary.appearances.map((a) => a.id),
    );
    expect(metadata.appearanceOptions, ordinary.appearanceOptions);
    expect(
      () => metadata.appearanceConfigurations.clear(),
      throwsUnsupportedError,
    );
    for (final malformed in [
      'not a form',
      [fixture()..['execute'] = 'launch'],
      [fixture(), fixture()],
      List.generate(9, (_) => fixture()),
    ]) {
      final result = await _read({
        ..._body(),
        'appearanceConfigurations': malformed,
      });
      expect(result.availability, OverlayWorkspaceAvailability.available);
      expect(result.appearanceConfigurations, isEmpty);
      expect(result.appearanceOptions, ordinary.appearanceOptions);
    }
  });

  test(
    'live preview capability is optional, bounded and cannot grant use',
    () async {
      expect((await _read(_body())).livePreviewAppearanceIds, isEmpty);
      final allowed = await _read({
        ..._body(),
        'livePreviewAppearanceIds': ['Default'],
      });
      expect(allowed.livePreviewAppearanceIds, {'Default'});
      expect(
        () => allowed.livePreviewAppearanceIds.clear(),
        throwsUnsupportedError,
      );
      for (final malformed in [
        true,
        ['Unknown'],
        ['Default', 'Default'],
        [1],
        List.generate(9, (_) => 'Default'),
      ]) {
        final result = await _read({
          ..._body(),
          'livePreviewAppearanceIds': malformed,
        });
        expect(result.availability, OverlayWorkspaceAvailability.available);
        expect(result.livePreviewAppearanceIds, isEmpty);
        expect(result.appearanceOptions, _choice);
      }
    },
  );

  test('live preview crosses real Bridge with only presentation options and an owned session', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    )..acceptHostCapabilities(['overlay.appearancePreview']);
    final requests = <BridgeEnvelope>[];
    var invalidReply = false;
    final sub = pair.host.incoming.listen((request) {
      requests.add(request);
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 1,
            status: 'ok',
            payload: request.name.endsWith('.open')
                ? {
                    'schemaVersion': 1,
                    'sessionId': invalidReply
                        ? 'invalid'
                        : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  }
                : {'schemaVersion': 1, 'closed': true},
          ),
        ),
      );
    });
    try {
      final port = BridgeOverlayWorkspaceAdapter(session);
      final id = await port.openAppearancePreview(
        'Default',
        _choice,
        reduceMotion: true,
      );
      await port.closeAppearancePreview(id);
      expect(requests.map((r) => r.name), [
        'overlay.appearancePreview.open',
        'overlay.appearancePreview.close',
      ]);
      expect(requests.first.payload, {
        'schemaVersion': 1,
        'appearanceId': 'Default',
        'appearanceOptions': _choice.toMap(),
        'reduceMotion': true,
      });
      expect(requests.last.payload, {'schemaVersion': 1, 'sessionId': id});
      expect(requests.every((r) => r.accountContext == null), isTrue);
      invalidReply = true;
      await expectLater(
        port.openAppearancePreview('Default', _choice),
        throwsFormatException,
      );
      session.acceptHostCapabilities([]);
      final before = requests.length;
      await expectLater(
        port.openAppearancePreview('Default', _choice),
        throwsStateError,
      );
      expect(requests.length, before);
    } finally {
      await sub.cancel();
      await session.close();
    }
  });

  test('real Bridge requests carry draft and saved options without account context', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    )..acceptHostCapabilities(['overlay.workspace', 'overlay.runtime']);
    final requests = <BridgeEnvelope>[];
    var body = _body();
    var open = false;
    final sub = pair.host.incoming.listen((request) {
      requests.add(request);
      Map<String, Object?> result;
      if (request.name.startsWith('overlay.runtime.')) {
        if (request.name == 'overlay.runtime.open') open = true;
        if (request.name == 'overlay.runtime.close') open = false;
        result = {
          'schemaVersion': 1,
          'windowState': open ? 'open' : 'closed',
          'isVisible': open,
          'appliedRevision': body['revision'],
          'hotkeyState': 'registered',
          'followGameState': 'manual',
          'requestedSkin': 'Default',
          'effectiveSkin': 'Default',
          'usedFallbackSkin': false,
          'retryable': false,
        };
      } else {
        if (request.name == 'overlay.updateWorkspace') {
          body = _body()
            ..['revision'] = 2
            ..['appearanceOptions'] = request.payload['appearanceOptions'];
          ((body['presets'] as List).single as Map)['appearanceOptions'] =
              request.payload['appearanceOptions'];
        }
        result = body;
      }
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 1,
            status: 'ok',
            payload: result,
          ),
        ),
      );
    });
    final module = OverlayWorkspaceModule(
      BridgeOverlayWorkspaceAdapter(session),
    );
    try {
      await module.initialize();
      module.updateAppearanceOptions(_options(2));
      expect(await module.save(), isTrue);
      expect(await module.openRuntime('zh'), isTrue);
      final draft = requests.last.payload['workspace'] as Map;
      expect(draft['appearanceOptions'], _options(2).toMap());
      final saved = requests.singleWhere(
        (r) => r.name == 'overlay.updateWorkspace',
      );
      expect(saved.payload['appearanceOptions'], _options(2).toMap());
      expect(saved.payload['expectedRevision'], 1);
      expect(module.projection.value.appearanceOptions, _options(2));
      expect(module.projection.value.dirty, isFalse);
      expect(module.projection.value.snapshot!.revision, 2);
      expect(requests.every((r) => r.accountContext == null), isTrue);
    } finally {
      module.dispose();
      await sub.cancel();
      await session.close();
    }
  });

  test(
    'option edits never make an unreleased or locked appearance usable',
    () async {
      final port = _Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      module.updateAppearanceOptions(
        _choice.withProfile('unreleased', {'version': 1, 'values': {}}),
      );
      module.updateSetting('skin', 'Unreleased');
      expect(module.projection.value.settings!['skin'], 'Default');
      expect(
        module.projection.value.failure,
        OverlaySettingsFailure.invalidValue,
      );
    },
  );
  testWidgets(
    'appearance-center controls use existing draft undo and save owner',
    (tester) async {
      size(tester, const Size(1280, 900));
      final configuration = OverlayAppearanceConfiguration.fromMap(fixture());
      final port = _Port()
        ..snapshot = _snapshot(configurations: [configuration]);
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<OverlayWorkspaceProjection>(
            valueListenable: module.projection,
            builder: (context, value, child) =>
                OverlayWorkspaceAppearanceCenter(
                  projection: value,
                  module: module,
                  onBack: () {},
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.byKey(const Key('appearance-config-slot-slot0'));
      await tester.ensureVisible(control);
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Variant 0').last);
      await tester.pumpAndSettle();
      expect(module.projection.value.dirty, isFalse, reason: 'saved already');
      expect(port.writes, hasLength(1));
      expect(
        configuration.read(
          module.projection.value.appearanceOptions,
        )!['slot0']!['kind'],
        0,
      );
      module.undo();
      await tester.pumpAndSettle();
      expect(module.projection.value.appearanceOptions, _choice);
      module.redo();
      await tester.pumpAndSettle();
      final edited = module.projection.value.appearanceOptions;
      expect(
        edited.profile('fixture-profile'),
        _choice.profile('fixture-profile'),
      );
      expect(port.writes.last.appearanceOptions, edited);
      expect(module.projection.value.dirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'installed described candidate can be configured but never applied',
    (tester) async {
      size(tester, const Size(1280, 900));
      final installed =
          Platform.environment['STARBRIDGE_APPEARANCE_CONFIGURATION_FIXTURE'];
      final generated = (await tester.runAsync(tinyPng))!;
      final source = installed == null
          ? (fixture()
              ..['appearanceId'] = 'HajiCitizen'
              ..['preview'] = {
                'format': 'png',
                'width': 2,
                'height': 2,
                'data': base64Encode(generated),
              })
          : (jsonDecode(File(installed).readAsStringSync()) as Map)
                .cast<String, Object?>();
      final configuration = OverlayAppearanceConfiguration.fromMap(source);
      final poster = configuration.preview!.bytes;
      final port = _Port()
        ..snapshot = _snapshot(
          configurations: [configuration],
          livePreviewIds: const {'HajiCitizen'},
          extraAppearances: [
            _appearance('HajiCitizen', released: false, name: '哈基公民'),
          ],
        );
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: app(
            ValueListenableBuilder<OverlayWorkspaceProjection>(
              valueListenable: module.projection,
              builder: (context, value, child) =>
                  OverlayWorkspaceAppearanceCenter(
                    projection: value,
                    module: module,
                    onBack: () {},
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('overlay-appearance-card-HajiCitizen'));
      expect(card, findsOneWidget);
      await tester.runAsync(() async {
        await precacheImage(MemoryImage(poster), captureKey.currentContext!);
      });
      await tester.pumpAndSettle();
      final thumbnail = tester.widget<Image>(
        find.byKey(const Key('overlay-native-preview-HajiCitizen')),
      );
      expect((thumbnail.image as MemoryImage).bytes, poster);
      expect(thumbnail.filterQuality, FilterQuality.none);
      expect(
        find.byKey(const Key('overlay-preview-browse-HajiCitizen')),
        findsNothing,
      );
      await tester.ensureVisible(card);
      final capture =
          Platform.environment['STARBRIDGE_APPEARANCE_CENTER_CAPTURE'];
      if (capture != null) {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (captureKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(capture).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(card);
      await tester.pumpAndSettle();
      final apply = find.byKey(
        const Key('overlay-appearance-apply-HajiCitizen'),
      );
      await tester.ensureVisible(apply);
      expect(tester.widget<StarBridgeActionButton>(apply).onActivate, isNull);
      final live = find.byKey(
        const Key('overlay-appearance-live-preview-HajiCitizen'),
      );
      // This fixture implements only the retired carrier port. The common
      // live-preview entry is covered with its actual port in the entry tests.
      expect(live, findsNothing);
      expect(port.previewOptions, isNull);
      expect(port.closedPreviewIds, isEmpty);
      final control = find.byKey(
        Key('appearance-config-slot-${configuration.slots.first.id}'),
      );
      await tester.ensureVisible(control);
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(configuration.slots.first.choices.first.label.zhCN).last,
      );
      await tester.pumpAndSettle();
      expect(port.writes.single.settings!['skin'], 'Default');
      expect(module.projection.value.settings!['skin'], 'Default');
      module.updateSetting('skin', 'HajiCitizen');
      await tester.pumpAndSettle();
      expect(module.projection.value.settings!['skin'], 'Default');
      expect(port.writes, hasLength(1), reason: 'never applied or saved');
      expect(tester.takeException(), isNull);
    },
  );
}

OverlayWorkspaceAppearance _appearance(
  String id, {
  bool released = true,
  String? name,
}) => OverlayWorkspaceAppearance(
  id: id,
  displayNameZh: name ?? id,
  displayNameEn: id,
  summaryZh: '',
  summaryEn: '',
  traitsZh: const ['Fixture'],
  traitsEn: const ['Fixture'],
  previewSurface: '#081722',
  previewPrimary: '#29AFFF',
  previewSecondary: '#69CCFF',
  locksTheme: false,
  supportsBloom: false,
  startupTransition: 'BridgeTerminal',
  requiresEntitlement: false,
  isReleased: released,
  isAvailable: released,
  isPreviewAvailable: true,
);

const _hotkey = OverlayWorkspaceHotkey(
  binding: 'Alt+O',
  enabled: true,
  runtimeState: 'registered',
);
OverlayWorkspaceSnapshot _snapshot({
  int revision = 1,
  bool enabled = true,
  String storage = 'ready',
  String? presetStorage,
  OverlayAppearanceOptions? options,
  List<OverlayAppearanceConfiguration> configurations = const [],
  List<OverlayWorkspaceAppearance> extraAppearances = const [],
  Set<String> livePreviewIds = const {},
}) {
  final value = options ?? _choice;
  return OverlayWorkspaceSnapshot.available(
    revision: revision,
    storageState: storage,
    activePresetId: 'p',
    renderMode: 'DirectComposition',
    settings: settings({'skin': 'Default', 'requestedSkin': 'Default'}),
    hotkey: _hotkey,
    layout: const [],
    appearances: [
      _appearance('Default'),
      _appearance('Unreleased', released: false),
      ...extraAppearances,
    ],
    appearanceOptionsEnabled: enabled,
    appearanceOptions: value,
    appearanceConfigurations: configurations,
    livePreviewAppearanceIds: livePreviewIds,
    presets: [
      OverlayWorkspacePreset(
        id: 'p',
        name: 'Fixture',
        isActive: true,
        storageState: presetStorage ?? storage,
        settings: settings(),
        layout: const [],
        appearanceOptions: value,
      ),
    ],
  );
}

final class _Port
    implements OverlayWorkspacePort, OverlayAppearancePreviewPort {
  OverlayAppearanceOptions? previewOptions;
  final closedPreviewIds = <String>[];
  @override
  Future<String> openAppearancePreview(
    String id,
    OverlayAppearanceOptions options, {
    bool reduceMotion = false,
  }) async {
    previewOptions = options;
    return 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  }

  @override
  Future<void> closeAppearancePreview(String id) async {
    closedPreviewIds.add(id);
  }

  OverlayWorkspaceSnapshot snapshot = _snapshot();
  final writes = <OverlayWorkspaceMutation>[];
  OverlayWorkspaceRuntimeDraft? draft;
  bool failWrites = false;
  bool open = false;
  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    writes.add(mutation);
    if (failWrites) {
      return const OverlayWorkspaceWriteResult.failed(
        OverlaySettingsFailure.writeFailed,
      );
    }
    if (mutation.kind == OverlayWorkspaceMutationKind.saveActive) {
      snapshot = _snapshot(
        revision: expectedRevision + 1,
        options: mutation.appearanceOptions ?? snapshot.appearanceOptions,
      );
    }
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    this.draft = draft;
    if (action == OverlayRuntimeAction.open ||
        action == OverlayRuntimeAction.retry) {
      open = true;
    }
    if (action == OverlayRuntimeAction.close) open = false;
    return OverlayRuntimeSnapshot(
      windowState: open ? 'open' : 'closed',
      isVisible: open,
      appliedRevision: snapshot.revision!,
      hotkeyState: 'registered',
      followGameState: 'manual',
      requestedSkin: 'Default',
      effectiveSkin: 'Default',
      usedFallbackSkin: false,
    );
  }

  @override
  Future<void> close() async {}
}

Map<String, Object?> _body() {
  final layout = [
    {
      'key': 'Members',
      'x': 0,
      'y': 0,
      'width': 0.3,
      'height': 0.2,
      'horizontalAnchor': 'Left',
      'verticalAnchor': 'Top',
      'isLocked': false,
      'textOpacity': 1.0,
      'backgroundOpacity': 1.0,
    },
  ];
  return {
    'schemaVersion': 1,
    'revision': 1,
    'storageState': 'ready',
    'activePresetId': 'p',
    'renderMode': 'DirectComposition',
    'settings': settings().toMap(),
    'appearanceOptionsEnabled': true,
    'appearanceOptions': _choice.toMap(),
    'hotkey': {
      'binding': 'Alt+O',
      'enabled': true,
      'runtimeState': 'registered',
    },
    'layout': layout,
    'appearances': [
      {
        'id': 'Default',
        'displayNameZh': 'Fixture',
        'displayNameEn': 'Fixture',
        'summaryZh': '',
        'summaryEn': '',
        'traitsZh': ['Fixture'],
        'traitsEn': ['Fixture'],
        'previewSurface': '#081722',
        'previewPrimary': '#29AFFF',
        'previewSecondary': '#69CCFF',
        'locksTheme': false,
        'supportsBloom': false,
        'startupTransition': 'BridgeTerminal',
        'requiresEntitlement': false,
        'isReleased': true,
        'isAvailable': true,
      },
    ],
    'presets': [
      {
        'id': 'p',
        'name': 'Fixture',
        'isActive': true,
        'storageState': 'ready',
        'settings': settings().toMap(),
        'layout': layout,
        'appearanceOptions': _choice.toMap(),
      },
    ],
  };
}

Future<OverlayWorkspaceSnapshot> _read(Map<String, Object?> body) async {
  final pair = InMemoryBridgeConnection.createPair();
  final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 1,
  )..acceptHostCapabilities(['overlay.workspace']);
  final sub = pair.host.incoming.listen((request) {
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 1,
          status: 'ok',
          payload: body,
        ),
      ),
    );
  });
  try {
    return await BridgeOverlayWorkspaceAdapter(session).read();
  } finally {
    await sub.cancel();
    await session.close();
  }
}
