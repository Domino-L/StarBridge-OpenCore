import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_preset_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

const package =
    '{"Version":1,"Name":"Fixture","Settings":"1,0,1,1,1","Layout":"Notice,0,0,400,60"}';
const card = <String, Object?>{
  'kind': 'overlay_preset',
  'title': 'Fixture',
  'summary': 'Fixture',
  'overlayPresetPackage': package,
};
Map<String, Object?> catalogPayload() => {
  'schemaVersion': 1,
  'revision': 9,
  'presets': [
    {'id': 'preset-test', 'name': 'Fixture'},
  ],
};

class PresetFake implements CommunityPresetPort {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get communityPresetsAvailable => true;
  int imports = 0, exports = 0, reads = 0;
  int? revision;
  String? failure;
  Completer<CommunityPresetCatalog>? heldRead;
  @override
  Future<CommunityPresetCatalog> readCommunityPresets() async {
    reads++;
    return heldRead?.future ?? CommunityPresetCatalog.parse(catalogPayload());
  }

  @override
  Future<Map<String, Object?>> exportCommunityPreset(
    String id,
    int version,
  ) async {
    exports++;
    revision = version;
    if (failure != null) throw CommunityFailure(failure!);
    return card;
  }

  @override
  Future<String> importCommunityPreset(
    Map<String, Object?> attachment,
    int version,
  ) async {
    imports++;
    revision = version;
    if (failure != null) throw CommunityFailure(failure!);
    return 'Fixture';
  }
}

void main() {
  test('device preset capability works without any room capability', () async {
    final host = CommunityHarness(
      capabilities: ['overlay.presetSharing'],
      responses: {'overlay.getWorkspace': catalogPayload()},
    );
    addTearDown(host.close);
    expect(host.adapter.communityPresetsAvailable, true);
    final result = await host.adapter.readCommunityPresets();
    expect(result.revision, 9);
    expect(result.presets.single.id, 'preset-test');
    expect(() => result.presets.clear(), throwsUnsupportedError);
    expect(host.requests.last.name, 'overlay.getWorkspace');
    expect(host.requests.first.name, 'account.getCurrent');
    expect(host.requests.last.accountContext, isNull);
  });
  test(
    'generic community commands do not enable local preset operations',
    () async {
      final host = CommunityHarness();
      addTearDown(host.close);
      expect(host.adapter.communityPresetsAvailable, false);
      await expectLater(
        host.adapter.readCommunityPresets(),
        throwsA(isA<CommunityFailure>()),
      );
      expect(host.requests, isEmpty);
    },
  );
  test('export preserves actual Host package and expected revision', () async {
    final host = CommunityHarness(
      capabilities: ['overlay.presetSharing'],
      responses: {
        'overlay.updateWorkspace': {'schemaVersion': 1, 'attachment': card},
      },
    );
    addTearDown(host.close);
    final result = await host.adapter.exportCommunityPreset('preset-test', 9);
    expect(result, card);
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'action': 'exportSharedPreset',
      'presetId': 'preset-test',
      'expectedRevision': 9,
    });
  });
  test(
    'import is one additive request with no activation or permission changes',
    () async {
      final host = CommunityHarness(
        capabilities: ['overlay.presetSharing'],
        responses: {
          'overlay.updateWorkspace': {
            'schemaVersion': 1,
            'name': 'Fixture',
            'presetId': 'new-preset',
          },
        },
      );
      addTearDown(host.close);
      expect(await host.adapter.importCommunityPreset(card, 9), 'Fixture');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'action': 'importSharedPreset',
        'package': package,
        'expectedRevision': 9,
      });
      expect(host.requests.last.accountContext, isNull);
      expect(
        host.requests.where((e) => e.name == 'overlay.updateWorkspace'),
        hasLength(1),
      );
    },
  );
  test(
    'bad import response is unknown and is not automatically replayed',
    () async {
      final host = CommunityHarness(
        capabilities: ['overlay.presetSharing'],
        responses: {
          'overlay.updateWorkspace': {'schemaVersion': 1, 'name': 'Fixture'},
        },
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.importCommunityPreset(card, 9),
        throwsA(
          isA<CommunityFailure>().having(
            (e) => e.code,
            'code',
            'presetImportUnknown',
          ),
        ),
      );
      expect(
        host.requests.where((e) => e.name == 'overlay.updateWorkspace'),
        hasLength(1),
      );
    },
  );
  test(
    'account invalidation rejects late export before attaching to draft',
    () async {
      final host = CommunityHarness(
        capabilities: ['overlay.presetSharing'],
        holdNames: {'overlay.updateWorkspace'},
        responses: {
          'overlay.updateWorkspace': {'schemaVersion': 1, 'attachment': card},
        },
      );
      addTearDown(host.close);
      final pending = host.adapter.exportCommunityPreset('preset-test', 9);
      final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
      await host.readArrived.future;
      final invalidated = host.adapter.invalidations.first;
      await host.connection.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 5,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await invalidated;
      await rejected;
      await host.reply(
        host.requests.firstWhere((e) => e.name == 'overlay.updateWorkspace'),
      );
    },
  );
  test('ambiguous case keys and foreign package fields remain invalid', () {
    for (final value in [
      package.replaceFirst('"Version":1', '"Version":1,"version":1'),
      package.replaceFirst('"Version":1', '"Version":1,"entitlement":true'),
    ]) {
      expect(
        () => CommunityChatDetail.parse({
          'attachment': {...card, 'overlayPresetPackage': value},
        }),
        throwsFormatException,
      );
    }
  });
  test(
    'invalid catalog revision duplicates and oversized names are rejected',
    () {
      for (final data in [
        catalogPayload()..['revision'] = -1,
        catalogPayload()
          ..['presets'] = [
            {'id': 'x', 'name': 'x'},
            {'id': 'x', 'name': 'y'},
          ],
        catalogPayload()
          ..['presets'] = [
            {'id': 'x', 'name': 'x' * 65},
          ],
      ]) {
        expect(() => CommunityPresetCatalog.parse(data), throwsFormatException);
      }
    },
  );
}
