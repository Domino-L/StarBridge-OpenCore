import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_port.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_port.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_ownership_transfer_test.dart' show transferPayload;

Map<String, Object?> exitPayload() =>
    transferPayload()..['leaveAfterTransfer'] = true;

class ExitFake implements CommunityOwnershipExitPort {
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool ownershipExitAvailable = true;
  int reads = 0, writes = 0;
  String? readError;
  bool protected = false;
  Completer<CommunityOwnershipExit>? pendingRead;
  Completer<CommunityOwnershipTransferOutcome>? pendingWrite;
  CommunityOwnershipTransferOutcome outcome =
      const CommunityOwnershipTransferOutcome('accepted');
  final confirmations = <bool>[];
  @override
  Future<CommunityOwnershipExit> readOwnershipExit({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) async {
    reads++;
    if (pendingRead != null) return pendingRead!.future;
    if (readError != null) throw CommunityFailure(readError!);
    return CommunityOwnershipExit.parse(
      exitPayload()..['canTransfer'] = !protected,
    );
  }

  @override
  Future<CommunityOwnershipTransferOutcome> leaveWithSuccessor(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) async {
    writes++;
    expect(requestId, matches(RegExp(r'^[a-f0-9]{32}$')));
    confirmations.add(confirmUncertainRetry);
    return pendingWrite?.future ?? outcome;
  }
}

void main() {
  test('retaining and departing projections are not interchangeable', () {
    expect(
      () => CommunityOwnershipExit.parse(transferPayload()),
      throwsFormatException,
    );
    expect(
      () => CommunityOwnershipTransfer.parse(exitPayload()),
      throwsFormatException,
    );
    expect(
      CommunityOwnershipTransfer.parse(transferPayload()).leaveAfterTransfer,
      isFalse,
    );
    expect(
      CommunityOwnershipExit.parse(exitPayload()).successor.leaveAfterTransfer,
      isTrue,
    );
    expect(
      () => CommunityOwnershipExit.example(
        CommunityOwnershipTransfer.parse(transferPayload()),
      ),
      throwsFormatException,
    );
  });
  for (final value in <Object?>[false, null, 'true', 1]) {
    test('exit projection rejects invalid purpose $value', () {
      expect(
        () => CommunityOwnershipExit.parse(
          exitPayload()..['leaveAfterTransfer'] = value,
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'Bridge routes one scoped exit command through its own capabilities',
    () async {
      final host = CommunityHarness(
        capabilities: [
          'communities.ownershipExit',
          'communities.leaveWithSuccessor',
        ],
        responses: {
          'communities.ownershipExit': exitPayload(),
          'communities.leaveWithSuccessor': {
            'schemaVersion': 1,
            'status': 'accepted',
          },
        },
      );
      addTearDown(host.close);
      expect(host.adapter.ownershipExitAvailable, isTrue);
      expect(host.adapter.ownershipTransferAvailable, isFalse);
      final preview = await host.adapter.readOwnershipExit(
        targetRef: 'a' * 32,
        memberRef: 'b' * 32,
      );
      expect(
        (await host.adapter.leaveWithSuccessor(
          'd' * 32,
          preview.editRef,
        )).status,
        'accepted',
      );
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'communities.ownershipExit',
        'account.getCurrent',
        'communities.leaveWithSuccessor',
      ]);
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'requestId': 'd' * 32,
        'editRef': 'c' * 32,
        'confirmUncertainRetry': false,
      });
      expect(host.requests.last.accountContext?.subject, 'test-subject');
    },
  );
  test('older Host does not expose or receive departure commands', () async {
    final host = CommunityHarness(
      capabilities: [
        'communities.ownershipTransfer',
        'communities.transferOwnership',
      ],
    );
    addTearDown(host.close);
    expect(host.adapter.ownershipExitAvailable, isFalse);
    expect(
      (await host.adapter.leaveWithSuccessor('d' * 32, 'c' * 32)).error,
      'unavailable',
    );
    expect(host.requests, isEmpty);
    final model = CommunityOwnershipExitController(
      host.adapter,
      'a' * 32,
      'b' * 32,
    );
    addTearDown(model.dispose);
    await model.load();
    await model.leave();
    expect(model.canLeave, isFalse);
    expect(host.requests, isEmpty);
  });
  test('malformed accepted exit receipt is unknown', () async {
    final host = CommunityHarness(
      capabilities: ['communities.leaveWithSuccessor'],
      responses: {
        'communities.leaveWithSuccessor': {
          'schemaVersion': 1,
          'status': 'accepted',
          'error': 'notAllowed',
        },
      },
    );
    addTearDown(host.close);
    expect(
      (await host.adapter.leaveWithSuccessor('d' * 32, 'c' * 32)).status,
      'unknown',
    );
  });
  test(
    'loading confirmation is read only and accepted departure cannot repeat',
    () async {
      final port = ExitFake();
      final model = CommunityOwnershipExitController(port, 'a' * 32, 'b' * 32);
      addTearDown(port.changes.close);
      addTearDown(model.dispose);
      await model.load();
      expect(port.writes, 0);
      await model.leave();
      await model.leave();
      expect(port.writes, 1);
      expect(model.left, isTrue);
    },
  );
  test('unknown exit requires fresh read and explicit retry', () async {
    final port = ExitFake()
      ..outcome = const CommunityOwnershipTransferOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    final model = CommunityOwnershipExitController(port, 'a' * 32, 'b' * 32);
    addTearDown(port.changes.close);
    addTearDown(model.dispose);
    await model.load();
    await model.leave();
    await model.leave(confirmUncertainRetry: true);
    expect(port.writes, 1);
    await model.load();
    await model.leave();
    expect(port.writes, 1);
    port.outcome = const CommunityOwnershipTransferOutcome('accepted');
    await model.leave(confirmUncertainRetry: true);
    expect(model.left, isTrue);
    expect(port.confirmations, [false, true]);
  });
  for (final failure in [
    'notFound',
    'notAllowed',
    'identityUnavailable',
    'refreshRequired',
  ]) {
    test(
      'lost authority removes pending exit confirmation: $failure',
      () async {
        final port = ExitFake();
        final model = CommunityOwnershipExitController(
          port,
          'a' * 32,
          'b' * 32,
        );
        addTearDown(port.changes.close);
        addTearDown(model.dispose);
        await model.load();
        port.readError = failure;
        await model.load();
        await model.leave();
        expect(model.snapshot, isNull);
        expect(port.writes, 0);
      },
    );
  }
  test('account change rejects late read and late exit success', () async {
    final port = ExitFake()..pendingRead = Completer<CommunityOwnershipExit>();
    var model = CommunityOwnershipExitController(port, 'a' * 32, 'b' * 32);
    addTearDown(port.changes.close);
    var pending = model.load();
    port.changes.add(null);
    port.pendingRead!.complete(CommunityOwnershipExit.parse(exitPayload()));
    await pending;
    expect(model.snapshot, isNull);
    model.dispose();
    port.pendingRead = null;
    port.pendingWrite = Completer<CommunityOwnershipTransferOutcome>();
    model = CommunityOwnershipExitController(port, 'a' * 32, 'b' * 32);
    addTearDown(model.dispose);
    await model.load();
    pending = model.leave();
    await model.leave();
    expect(port.writes, 1);
    port.changes.add(null);
    port.pendingWrite!.complete(
      const CommunityOwnershipTransferOutcome('accepted'),
    );
    await pending;
    expect(model.left, isFalse);
    expect(model.snapshot, isNull);
  });
  test('wrong candidate and protected candidate never submit', () async {
    final port = ExitFake()..pendingRead = Completer<CommunityOwnershipExit>();
    final model = CommunityOwnershipExitController(port, 'a' * 32, 'b' * 32);
    addTearDown(port.changes.close);
    addTearDown(model.dispose);
    final pending = model.load();
    port.pendingRead!.complete(
      CommunityOwnershipExit.parse(exitPayload()..['memberRef'] = 'e' * 32),
    );
    await pending;
    expect(model.error, 'dataInvalid');
    expect(model.canLeave, isFalse);
    port.pendingRead = null;
    port.protected = true;
    await model.load();
    await model.leave();
    expect(port.writes, 0);
  });
}
