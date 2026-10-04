import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';
import 'package:starbridge_flutter/features/communities/community_preset_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_inspection_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';

import 'community_chat_media_cache_test.dart' show MediaPort, message;
import '../overlay_settings/overlay_settings_ux_a_test.dart' show settings;
import '../overlay_settings/overlay_preset_transfer_test.dart' show layout;

class PreviewPort extends MediaPort
    implements CommunityPresetPort, OverlayPresetInspectionPort {
  int inspections = 0;
  bool failPreview = false;
  Completer<void>? inspectionGate;
  @override
  bool get communityPresetsAvailable => true;
  @override
  Future<CommunityPresetCatalog> readCommunityPresets() async =>
      CommunityPresetCatalog.parse({
        'schemaVersion': 1,
        'revision': 7,
        'presets': [],
      });
  @override
  Future<OverlayPresetTransfer> inspectPreset(
    String package,
    int revision,
  ) async {
    inspections++;
    expect(revision, 7);
    await inspectionGate?.future;
    if (failPreview) throw StateError('Preview unavailable');
    return OverlayPresetTransfer(
      name: 'Fixture',
      settings: settings(),
      layout: layout,
    );
  }

  @override
  Future<Map<String, Object?>> exportCommunityPreset(String id, int revision) =>
      throw UnimplementedError();
  @override
  Future<String> importCommunityPreset(
    Map<String, Object?> attachment,
    int revision,
  ) => throw UnimplementedError();
}

void main() {
  test('local Host inspection is cached with authorized attachment and invalidated together', () async {
    final port = PreviewPort();
    final cache = CommunityChatMediaCache(port, 'a' * 32);
    addTearDown(cache.dispose);
    addTearDown(port.changes.close);
    final item = message(1, attachment: true, hasAvatar: false);
    final value = await cache.load(item);
    expect(value.preview, isNotNull);
    expect((await cache.load(item)).preview, same(value.preview));
    expect(cache.peek(item)!.preview, same(value.preview));
    expect(port.inspections, 1);
    expect(port.calls, hasLength(1));
    port.changes.add(null);
    expect(cache.peek(item), isNull);
    await expectLater(cache.load(item), throwsStateError);
  });
  test('inspection failure keeps attachment readable and explicit retry can recover', () async {
    final port = PreviewPort()..failPreview = true;
    final cache = CommunityChatMediaCache(port, 'a' * 32);
    addTearDown(cache.dispose);
    addTearDown(port.changes.close);
    final item = message(1, attachment: true, hasAvatar: false);
    final value = await cache.load(item);
    expect(value.attachment, isNotNull);
    expect(value.preview, isNull);
    port.failPreview = false;
    expect((await cache.load(item, retry: true)).preview, isNotNull);
  });
  test(
    'revocation while thumbnail is being inspected rejects late completion',
    () async {
      final port = PreviewPort()..inspectionGate = Completer<void>();
      final cache = CommunityChatMediaCache(port, 'a' * 32);
      addTearDown(cache.dispose);
      addTearDown(port.changes.close);
      final item = message(1, attachment: true, hasAvatar: false);
      final pending = cache.load(item);
      final rejected = expectLater(pending, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(port.inspections, 1);
      port.changes.add(null);
      port.inspectionGate!.complete();
      await rejected;
      expect(cache.peek(item), isNull);
    },
  );
}
