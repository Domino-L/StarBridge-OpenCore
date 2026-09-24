import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_controller.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';

void main() {
  final id = 'a' * 32;
  late InvitationSendTestPort port;
  late CommunityInvitationSendController controller;
  var ids = 0;
  setUp(() {
    ids = 0;
    port = InvitationSendTestPort();
    controller = CommunityInvitationSendController(
      port,
      createId: () {
        ids++;
        return id;
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await port.events.close();
  });
  Future<void> start() => controller.start(
    organizationRef: 'b' * 32,
    channel: 'private',
    destinationRef: 'c' * 32,
    maxUses: 1,
  );
  CommunityInvitationOperation row(String phase) =>
      CommunityInvitationOperation(
        id,
        'private',
        phase,
        'Organization',
        'Recipient',
        DateTime.utc(2026, 9, 8),
        1,
      );

  test('opening and refreshing only read; no IDs or writes', () async {
    port.items = [row('sending')];
    await start();
    expect(port.calls, isEmpty);
    await controller.load();
    await controller.load();
    expect(port.calls, ['read', 'read']);
    expect(ids, 0);
    expect(controller.items.single.phase, 'sending');
    expect(() => controller.items.clear(), throwsUnsupportedError);
  });
  test('missing capability and failed storage never enable sending', () async {
    port.invitationSendingAvailable = false;
    await controller.load();
    await start();
    expect(port.calls, isEmpty);
    port.invitationSendingAvailable = true;
    port.readError = const CommunityFailure('localRecoveryUnavailable');
    await controller.load();
    await start();
    expect(controller.canStart, isFalse);
    expect(controller.error, 'localRecoveryUnavailable');
    expect(ids, 0);
  });
  test('double click and unknown result keep exactly one operation', () async {
    await controller.load();
    final reply = Completer<CommunityInvitationProgress>();
    port.reply = reply;
    final first = start();
    await start();
    expect(ids, 1);
    reply.complete(
      CommunityInvitationProgress(id, 'unknown', 'outcomeUnknown'),
    );
    await first;
    await controller.load();
    await start();
    expect(ids, 1);
    expect(port.calls.where((c) => c.startsWith('send:')), ['send:$id']);
    expect(controller.activeOperationId, id);
    expect(controller.progress?.status, 'unknown');
  });
  test(
    'recover defaults to check with original id, never a new send',
    () async {
      port.items = [row('sending')];
      await controller.load();
      await controller.recover(id);
      expect(port.calls, ['read', 'check:$id', 'read']);
      expect(ids, 0);
    },
  );
  test(
    'delivery retry requires explicit confirmation and sending phase',
    () async {
      port.items = [row('ready')];
      await controller.load();
      await controller.recover(
        id,
        action: InvitationRecoveryAction.retryDelivery,
        retryConfirmed: true,
      );
      port.items = [row('sending')];
      await controller.load();
      await controller.recover(
        id,
        action: InvitationRecoveryAction.retryDelivery,
      );
      await controller.recover(
        id,
        action: InvitationRecoveryAction.continueSending,
      );
      expect(port.calls, ['read', 'read']);
      await controller.recover(
        id,
        action: InvitationRecoveryAction.retryDelivery,
        retryConfirmed: true,
      );
      expect(port.calls, ['read', 'read', 'retryDelivery:$id', 'read']);
      expect(ids, 0);
    },
  );
  for (final phase in ['prepared', 'generating', 'ready']) {
    test('explicit continue resumes $phase without replacing intent', () async {
      port.items = [row(phase)];
      await controller.load();
      await controller.recover(
        id,
        action: InvitationRecoveryAction.continueSending,
      );
      expect(port.calls, ['read', 'advance:$id', 'read']);
      expect(ids, 0);
    });
  }
  test('arbitrary or foreign id never reaches recovery port', () async {
    await controller.load();
    await controller.recover('d' * 32);
    expect(port.calls, ['read']);
  });
  test('invalid source and id collision do not send', () async {
    await controller.load();
    await controller.start(
      organizationRef: 'raw-code',
      channel: 'room',
      destinationRef: 'room-ref',
      maxUses: 1,
    );
    expect(controller.error, 'dataInvalid');
    expect(ids, 0);
    port.items = [row('sent')];
    await controller.load();
    await start();
    expect(controller.error, 'dataInvalid');
    expect(port.calls.where((c) => c.startsWith('send:')), isEmpty);
  });
  test(
    'send exception stays unknown; recovery storage error is explicit',
    () async {
      await controller.load();
      port.writeError = const CommunityFailure('localRecoveryUnavailable');
      await start();
      expect(controller.progress?.status, 'unknown');
      expect(controller.progress?.error, 'localRecoveryUnavailable');
      await start();
      expect(ids, 1);
    },
  );
  test('confirmed sent survives failed list refresh; cannot resend', () async {
    await controller.load();
    port.status = 'sent';
    port.readError = const CommunityFailure('unavailable');
    await start();
    expect(controller.progress?.status, 'sent');
    expect(controller.error, 'unavailable');
    await controller.recover(
      id,
      action: InvitationRecoveryAction.retryDelivery,
      retryConfirmed: true,
    );
    await start();
    expect(port.calls.where((c) => c.startsWith('send:')).length, 1);
    expect(ids, 1);
  });
  test('wrong response identity never becomes confirmed', () async {
    await controller.load();
    port.reply = Completer()
      ..complete(CommunityInvitationProgress('d' * 32, 'sent'));
    await start();
    expect(controller.progress?.status, 'unknown');
    expect(controller.activeOperationId, id);
  });
  test(
    'account invalidation clears state and drops late send and refresh',
    () async {
      port.items = [row('ready')];
      await controller.load();
      final reply = Completer<CommunityInvitationProgress>();
      port.reply = reply;
      final pending = controller.recover(id);
      port.events.add(null);
      reply.complete(CommunityInvitationProgress(id, 'sent'));
      await pending;
      expect(controller.invalidated, isTrue);
      expect(controller.items, isEmpty);
      expect(controller.progress, isNull);
      expect(controller.activeOperationId, isNull);
      expect(port.calls, ['read', 'check:$id']);
      await controller.load();
      await start();
      expect(port.calls, ['read', 'check:$id']);
    },
  );
  test('invalidation from a listener prevents write before dispatch', () async {
    await controller.load();
    controller.addListener(() {
      if (controller.busy) port.events.add(null);
    });
    await start();
    expect(controller.invalidated, isTrue);
    expect(port.calls, ['read']);
  });
  test(
    'late read after account invalidation cannot expose old names',
    () async {
      port.readReply = Completer();
      final pending = controller.load();
      port.events.add(null);
      port.readReply!.complete([row('sent')]);
      await pending;
      expect(controller.items, isEmpty);
      expect(controller.loaded, isFalse);
    },
  );
}

final class InvitationSendTestPort implements CommunityInvitationSendPort {
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => events.stream;
  @override
  bool invitationSendingAvailable = true;
  List<CommunityInvitationOperation> items = [];
  final calls = <String>[];
  Object? readError, writeError;
  String status = 'unknown';
  Completer<CommunityInvitationProgress>? reply;
  Completer<List<CommunityInvitationOperation>>? readReply;
  @override
  Future<List<CommunityInvitationOperation>> readInvitationOutbox() async {
    calls.add('read');
    if (readError != null) throw readError!;
    return readReply?.future ?? items;
  }

  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) => _result('send', operationId);
  @override
  Future<CommunityInvitationProgress> resumeInvitation(
    String operationId, {
    String action = 'check',
  }) => _result(action, operationId);
  Future<CommunityInvitationProgress> _result(String action, String id) async {
    calls.add('$action:$id');
    if (writeError != null) throw writeError!;
    return reply?.future ?? CommunityInvitationProgress(id, status);
  }
}
