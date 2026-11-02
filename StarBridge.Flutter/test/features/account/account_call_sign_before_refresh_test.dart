import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_avatar_read_preparation.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

// Build 16 night sampling (2026-10-22): startup median 25.7 s. The first read
// landed signed in at 4.0 s with a refresh already queued; the call sign read
// started only after that refresh landed (6.05 s), 2 ms after the shell's
// social reads, and waited behind an 8.4 s friends read (done 14.97 s).

final class _QueuedRefreshPort
    implements AccountPort, AccountAvatarReadPreparationPort {
  final source = InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
  final first = Completer<void>();
  final second = Completer<void>();
  int reads = 0, avatarReads = 0;

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
  Future<AccountPortResult> read() async {
    reads++;
    await (reads == 1 ? first.future : second.future);
    return source.read();
  }

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      source.execute(command);
  @override
  Future<void> close() => source.close();
}

void main() {
  test('the call sign read starts before a queued refresh lands', () async {
    final port = _QueuedRefreshPort();
    final module = createAccountModule(port);
    addTearDown(module.dispose);
    final initialized = module.initialize();
    await pumpEventQueue();
    // A second refresh is requested while the first read is still pending.
    unawaited(module.refresh());
    port.first.complete();
    await pumpEventQueue();
    expect(port.reads, 2, reason: 'The queued refresh is reading.');
    expect(
      port.avatarReads,
      1,
      reason: 'The call sign waited for the queued refresh to land.',
    );
    expect(module.presentationSettled, isTrue);
    port.second.complete();
    await initialized;
    await pumpEventQueue();
    expect(
      port.avatarReads,
      1,
      reason: 'A settled call sign is not read again.',
    );
    expect(module.projection.value.profile?.displayName, 'Startup Call Sign');
  });
}
