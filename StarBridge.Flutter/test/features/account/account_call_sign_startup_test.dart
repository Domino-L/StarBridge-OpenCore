import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_avatar_read_preparation.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

// Build 12 night sampling (2026-10-21): startup median 20 s. The first-content
// gate waited for the call sign, whose read only started after the whole
// warm-up queue (read began at 15.8 s and took 0.2 s), because the account was
// still busy at the queue's first turn. The read must start when the account
// read lands, without the warm-up queue.

final class _CallSignPort
    implements AccountPort, AccountAvatarReadPreparationPort {
  final source = InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
  int avatarReads = 0;

  @override
  bool get supportsAvatarReadPreparation => true;
  @override
  Future<AccountAvatarReadResult?> prepareAvatarRead({
    bool retry = false,
  }) async {
    avatarReads++;
    final snapshot = await source.read();
    final route = snapshot.snapshot!.route!;
    return AccountAvatarReadResult(
      BridgeAccountContext(
        environment: route.environment,
        authority: route.authority,
        subject: route.subject,
      ),
      snapshot.snapshot!.generation,
      callSign: 'Startup Call Sign',
      hasPresentation: true,
    );
  }

  @override
  void cancelAvatarReadPreparation() {}
  @override
  Stream<AccountInvalidation> get invalidations => source.invalidations;
  @override
  Future<AccountPortResult> read() => source.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      source.execute(command);
  @override
  Future<void> close() => source.close();
}

void main() {
  test(
    'the call sign read starts when the account read lands, not after warm-up',
    () async {
      final port = _CallSignPort();
      final module = createAccountModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      await pumpEventQueue();
      // No warm-up queue ran (prepareNextRead was never called).
      expect(port.avatarReads, 1);
      expect(module.presentationSettled, isTrue);
      expect(module.projection.value.profile?.displayName, 'Startup Call Sign');
    },
  );

  test('a settled call sign is not read again by a later refresh', () async {
    final port = _CallSignPort();
    final module = createAccountModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    await pumpEventQueue();
    await module.refresh();
    await pumpEventQueue();
    expect(port.avatarReads, 1);
  });
}
