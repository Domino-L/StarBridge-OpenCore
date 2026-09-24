import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_port.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'community_workspace_test.dart' show WorkspaceTestPort;
import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> transferPayload() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'memberRef': 'b' * 32,
  'editRef': 'c' * 32,
  'gameName': '',
  'callsign': '示例成员',
  'roleTitle': '成员',
  'formerOwnerRoleTitle': '副负责人',
  'canTransfer': true,
};

class TransferFake extends WorkspaceTestPort
    implements CommunityOwnershipTransferPort {
  @override
  bool ownershipTransferAvailable = true;
  int reads = 0, writes = 0;
  bool transferred = false, canTransfer = true;
  String? readError;
  CommunityOwnershipTransferOutcome outcome =
      const CommunityOwnershipTransferOutcome('accepted');
  Completer<CommunityOwnershipTransfer>? pendingRead;
  Completer<CommunityOwnershipTransferOutcome>? pendingWrite;
  final confirmations = <bool>[];
  @override
  Future<CommunityOwnershipTransfer> readOwnershipTransfer({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) async {
    reads++;
    if (pendingRead != null) return pendingRead!.future;
    if (readError != null) throw CommunityFailure(readError!);
    return CommunityOwnershipTransfer.parse(
      transferPayload()..['canTransfer'] = canTransfer,
    );
  }

  @override
  Future<CommunityOwnershipTransferOutcome> transferOwnership(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) async {
    writes++;
    confirmations.add(confirmUncertainRetry);
    if (pendingWrite != null) return pendingWrite!.future;
    if (outcome.status == 'accepted') transferred = true;
    return outcome;
  }
}

void main() {
  test(
    'missing target clears earlier confirmation and prevents transfer',
    () async {
      final port = TransferFake();
      final model = CommunityOwnershipTransferController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      expect(model.snapshot?.formerOwnerRoleTitle, '副负责人');
      port.readError = 'notFound';
      await model.load();
      await model.transfer();
      expect(model.snapshot, isNull);
      expect(model.canTransfer, isFalse);
      expect(port.writes, 0);
    },
  );
  test(
    'Bridge requires transfer capabilities and sends only scoped confirmation',
    () async {
      final host = CommunityHarness(
        capabilities: [
          'communities.ownershipTransfer',
          'communities.transferOwnership',
        ],
        responses: {
          'communities.ownershipTransfer': transferPayload(),
          'communities.transferOwnership': {
            'schemaVersion': 1,
            'status': 'accepted',
          },
        },
      );
      addTearDown(host.close);
      expect(host.adapter.ownershipTransferAvailable, isTrue);
      final member = await host.adapter.readOwnershipTransfer(
        targetRef: 'a' * 32,
        memberRef: 'b' * 32,
      );
      expect(
        (await host.adapter.transferOwnership('d' * 32, member.editRef)).status,
        'accepted',
      );
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'communities.ownershipTransfer',
        'account.getCurrent',
        'communities.transferOwnership',
      ]);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'requestId': 'd' * 32,
        'editRef': 'c' * 32,
        'confirmUncertainRetry': false,
      });
    },
  );
  test(
    'old Host does not advertise action or send unsupported transfer',
    () async {
      final host = CommunityHarness(capabilities: ['communities.commands']);
      addTearDown(host.close);
      expect(host.adapter.ownershipTransferAvailable, isFalse);
      expect(
        (await host.adapter.transferOwnership('d' * 32, 'c' * 32)).error,
        'unavailable',
      );
      expect(host.requests, isEmpty);
    },
  );
  for (final (field, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('canTransfer', 'yes'),
    ('formerOwnerRoleTitle', null),
    ('formerOwnerRoleTitle', 'x' * 513),
    ('memberRef', 'raw-account-id'),
    ('callsign', 'bad\nname'),
    ('private', 'x' * (16 * 1024)),
  ]) {
    test(
      'reject malformed transfer projection $field: ${value.runtimeType}',
      () {
        expect(
          () => CommunityOwnershipTransfer.parse(
            transferPayload()..[field] = value,
          ),
          throwsFormatException,
        );
      },
    );
  }
  test('malformed successful receipt is unknown, never confirmed', () async {
    final host = CommunityHarness(
      capabilities: ['communities.transferOwnership'],
      responses: {
        'communities.transferOwnership': {
          'schemaVersion': 2,
          'status': 'accepted',
        },
      },
    );
    addTearDown(host.close);
    expect(
      (await host.adapter.transferOwnership('d' * 32, 'c' * 32)).status,
      'unknown',
    );
  });
  test(
    'reading does not transfer, accepted command cannot be repeated',
    () async {
      final port = TransferFake();
      final model = CommunityOwnershipTransferController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      expect(port.writes, 0);
      await model.transfer();
      await model.transfer();
      expect(model.transferred, isTrue);
      expect(port.writes, 1);
    },
  );
  test(
    'unknown requires fresh read and explicit retry, not merely a new request',
    () async {
      final port = TransferFake()
        ..outcome = const CommunityOwnershipTransferOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      final model = CommunityOwnershipTransferController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      await model.transfer();
      await model.transfer(confirmUncertainRetry: true);
      expect(port.writes, 1);
      await model.load();
      await model.transfer();
      expect(port.writes, 1);
      port.outcome = const CommunityOwnershipTransferOutcome('accepted');
      await model.transfer(confirmUncertainRetry: true);
      expect(model.transferred, isTrue);
      expect(port.confirmations, [false, true]);
    },
  );
  for (final failure in [
    'conflict',
    'notAllowed',
    'refreshRequired',
    'identityUnavailable',
  ]) {
    test('failed transfer stays unconfirmed: $failure', () async {
      final port = TransferFake()
        ..outcome = CommunityOwnershipTransferOutcome(
          'rejected',
          error: failure,
        );
      final model = CommunityOwnershipTransferController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      await model.transfer();
      expect(model.transferred, isFalse);
      expect(model.canTransfer, isFalse);
      expect(model.snapshot == null, failure != 'conflict');
    });
  }
  test(
    'account change clears late read and concurrent late transfer',
    () async {
      final port = TransferFake()
        ..pendingRead = Completer<CommunityOwnershipTransfer>();
      var model = CommunityOwnershipTransferController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(port.changes.close);
      var pending = model.load();
      port.changes.add(null);
      port.pendingRead!.complete(
        CommunityOwnershipTransfer.parse(transferPayload()),
      );
      await pending;
      expect(model.snapshot, isNull);
      model.dispose();
      port.pendingRead = null;
      port.pendingWrite = Completer<CommunityOwnershipTransferOutcome>();
      model = CommunityOwnershipTransferController(port, 'a' * 32, 'b' * 32);
      addTearDown(model.dispose);
      await model.load();
      pending = model.transfer();
      await model.transfer();
      expect(port.writes, 1);
      port.changes.add(null);
      port.pendingWrite!.complete(
        const CommunityOwnershipTransferOutcome('accepted'),
      );
      await pending;
      expect(model.transferred, isFalse);
      expect(model.snapshot, isNull);
    },
  );
  test(
    'wrong target is rejected and protected member cannot be submitted',
    () async {
      final port = TransferFake()
        ..pendingRead = Completer<CommunityOwnershipTransfer>();
      final model = CommunityOwnershipTransferController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final pending = model.load();
      port.pendingRead!.complete(
        CommunityOwnershipTransfer.parse(
          transferPayload()..['memberRef'] = 'e' * 32,
        ),
      );
      await pending;
      expect(model.error, 'dataInvalid');
      expect(model.canTransfer, isFalse);
      port.pendingRead = null;
      port.canTransfer = false;
      await model.load();
      await model.transfer();
      expect(port.writes, 0);
    },
  );
}
