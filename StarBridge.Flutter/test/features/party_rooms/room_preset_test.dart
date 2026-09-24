import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_preset_port.dart';
import 'package:starbridge_flutter/features/party_rooms/example_room_chat.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_room_chat.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_room_presets.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'room_chat_test.dart' show ChatPort;
import 'bridge_party_rooms_test.dart' show Harness;
import 'room_lifecycle_widget_test.dart' show openExampleRooms;

class PresetPort extends ChatPort implements RoomPresetPort {
  final example = ExampleRoomChat();
  Completer<Map<String, Object?>>? exporting;
  String? failure;
  int imports = 0;
  @override
  bool get presetsAvailable => true;
  @override
  Future<RoomPresetCatalog> readPresets() => example.readPresets();
  @override
  Future<Map<String, Object?>> exportPreset(String id, int revision) =>
      exporting?.future ?? example.exportPreset(id, revision);
  @override
  Future<String> importPreset(String package, int revision) {
    imports++;
    return example.importPreset(package, revision);
  }

  @override
  Future<RoomChatMessage> sendPreset(
    String roomId,
    String text,
    Map<String, Object?> attachment,
  ) async {
    sends++;
    if (failure != null) throw RoomChatFailure(failure!);
    return example.sendPreset(roomId, text, attachment);
  }
}

Future<void> prepare(RoomChatModule module) async {
  final catalog = await module.presets!.readPresets();
  expect(
    await module.preparePreset(
      catalog.presets.first,
      catalog.revision,
      module.contextRevision,
    ),
    isTrue,
  );
}

void main() {
  test(
    'preset Bridge uses local revision-guarded actions without account context',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session =
          BridgeClientSession(connection: pair.client, sessionGeneration: 4)
            ..acceptHostCapabilities([
              'overlay.presetSharing',
              'partyRooms.chatAttachments',
            ]);
      final requests = <BridgeEnvelope>[];
      final card = await ExampleRoomChat().exportPreset('example-preset', 1);
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        final payload = request.name == 'overlay.getWorkspace'
            ? {
                'schemaVersion': 1,
                'revision': 7,
                'presets': [
                  {'id': 'preset1', 'name': '预设'},
                ],
              }
            : request.payload['action'] == 'exportSharedPreset'
            ? {'schemaVersion': 1, 'attachment': card}
            : {'schemaVersion': 1, 'name': '预设 2', 'presetId': 'new-preset'};
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 4,
              status: 'ok',
              payload: payload,
            ),
          ),
        );
      });
      final port = BridgeRoomPresets(session);
      final catalog = await port.read();
      final exported = await port.export(
        catalog.presets.single.id,
        catalog.revision,
      );
      expect(
        await port.import(
          exported['overlayPresetPackage'] as String,
          catalog.revision,
        ),
        '预设 2',
      );
      expect(requests.map((r) => r.name), [
        'overlay.getWorkspace',
        'overlay.updateWorkspace',
        'overlay.updateWorkspace',
      ]);
      expect(requests.every((r) => r.accountContext == null), isTrue);
      expect(
        requests.skip(1).every((r) => r.payload['expectedRevision'] == 7),
        isTrue,
      );
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    },
  );
  for (final failure in ['unavailable', 'outcomeUnknown']) {
    testWidgets('attachment draft survives $failure without blind replay', (
      tester,
    ) async {
      final port = PresetPort()..failure = failure;
      final module = RoomChatModule(port)..setRoom('one');
      await tester.pump();
      await prepare(module);
      module.draft = '说明';
      final card = module.attachmentDraft;
      expect(await module.send(), isFalse);
      expect(module.attachmentDraft, same(card));
      expect(module.draft, '说明');
      if (failure == 'outcomeUnknown') {
        module.clearAttachment();
        expect(module.attachmentDraft, same(card));
        expect(await module.send(), isFalse);
        expect(port.sends, 1);
        module.acknowledgeUncertain();
      }
      port.failure = null;
      expect(await module.send(), isTrue);
      expect(module.attachmentDraft, isNull);
      expect(module.draft, isEmpty);
      module.dispose();
    });
  }
  testWidgets('room change discards late export and prevents stale import', (
    tester,
  ) async {
    final port = PresetPort()..exporting = Completer();
    final module = RoomChatModule(port)..setRoom('one');
    await tester.pump();
    final catalog = await port.readPresets(), epoch = module.contextRevision;
    final task = module.preparePreset(
      catalog.presets.first,
      catalog.revision,
      epoch,
    );
    module.setRoom('two');
    port.exporting!.complete(
      await port.example.exportPreset('example-preset', 1),
    );
    expect(await task, isFalse);
    expect(module.attachmentDraft, isNull);
    final message = await port.example.sendPreset(
      'one',
      '',
      await port.example.exportPreset('example-preset', 1),
    );
    expect(await module.importPreset(message, 1, epoch), isNull);
    expect(port.imports, 0);
    module.dispose();
    await tester.pump();
  });
  testWidgets('access loss clears attachment and disables preset actions', (
    tester,
  ) async {
    final port = PresetPort();
    final module = RoomChatModule(port)..setRoom('one');
    await tester.pump();
    await prepare(module);
    port.reading = (_, _) async => throw const RoomChatFailure('notMember');
    await module.refresh();
    expect(module.attachmentDraft, isNull);
    expect(module.presetsAvailable, isFalse);
    module.dispose();
  });
  test('older Host keeps plain chat without offering preset sharing', () async {
    final host = Harness(capabilities: ['partyRooms.chat']);
    final port = BridgeRoomChat(host.session);
    expect(port.available, isTrue);
    expect(port.presetsAvailable, isFalse);
    await expectLater(port.readPresets(), throwsA(isA<RoomChatFailure>()));
    expect(host.requests, isEmpty);
    await host.close();
  });
  test(
    'attachment send uses current account and existing room endpoint',
    () async {
      final host = Harness(
        capabilities: [
          'partyRooms.chat',
          'partyRooms.chatAttachments',
          'overlay.presetSharing',
        ],
        commandPayload: {
          'schemaVersion': 1,
          'status': 'sent',
          'message': {
            'sequence': 1,
            'messageId': 'm1',
            'senderCallsign': '呼号',
            'senderGameId': 'Handle_CN',
            'kind': 'player',
            'text': '',
            'createdAt': '2026-09-06T12:00:00Z',
          },
        },
      );
      final card = await ExampleRoomChat().exportPreset('example-preset', 1);
      await BridgeRoomChat(host.session).sendPreset('one', '', card);
      expect(host.requests.last.payload['data'], {
        'roomId': 'one',
        'text': '',
        'attachment': card,
      });
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(
        host.requests.where((r) => r.name == 'partyRooms.execute'),
        hasLength(1),
      );
      await host.close();
    },
  );
  testWidgets(
    'example UI chooses, sends, cancels and imports without replacing presets',
    (tester) async {
      final composition = await openExampleRooms(tester);
      await composition.partyRooms.selectPreviewScene('current');
      await tester.pumpAndSettle();
      final module = composition.partyRooms.chat!;
      await tester.tap(find.widgetWithText(TextButton, '分享浮层预设'));
      await tester.pumpAndSettle();
      expect(find.textContaining('未保存的调整不会发送'), findsOneWidget);
      await tester.tap(find.text('示例浮层预设'));
      await tester.pumpAndSettle();
      expect(module.attachmentDraft, isNotNull);
      expect(module.draft, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pumpAndSettle();
      expect(module.messages.last.attachment?['kind'], 'overlay_preset');
      final initial = await module.presets!.readPresets();
      final importButton = find.widgetWithText(TextButton, '导入为新预设');
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('不覆盖或切换当前预设'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        (await module.presets!.readPresets()).presets,
        hasLength(initial.presets.length),
      );
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await module.presets!.readPresets()).presets,
        hasLength(initial.presets.length + 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
