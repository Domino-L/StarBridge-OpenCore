import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/account_read_preparation.dart';
import 'package:starbridge_flutter/features/account/account_visible_reads.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

// 2026-10-21 (build 15, right after a sign-in): "Settings -> Account" showed
// the cached profile, "compatibility not read yet" and "RSI identity cannot be
// confirmed" for over a minute. Those staged reads ran only from the warm-up
// queue, which yields - and cancels them - on every click. While the page is
// open they are read now and a click does not cancel them.

final class _StagedPort implements AccountPort, AccountReadPreparationPort {
  final source = InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
  int pending = 4, reads = 0, cancels = 0;

  @override
  bool get supportsStagedReads => true;
  @override
  bool get hasPendingReadPreparation => pending > 0;
  @override
  bool get shouldRetryReadPreparation => false;
  @override
  Future<AccountPortResult?> prepareNextRead({bool retry = false}) async {
    if (pending == 0) return null;
    pending--;
    reads++;
    return source.read();
  }

  @override
  void cancelReadPreparation() => cancels++;
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
  test('an open account page reads its staged details at once', () async {
    final port = _StagedPort();
    final module = createAccountModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    await pumpEventQueue();
    expect(port.reads, 0, reason: 'no warm-up queue ran');

    final release = module.holdVisibleReads();
    await pumpEventQueue();
    expect(
      port.reads,
      4,
      reason:
          'The account page waits for the warm-up queue to read its details.',
    );
    release();
  });

  test('a click does not cancel what the open page reads', () async {
    final port = _StagedPort();
    final module = createAccountModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    await pumpEventQueue();
    final preparation = module as AccountReadPreparation;
    final before = port.cancels; // the module's own refresh cancels once

    final release = module.holdVisibleReads();
    preparation.cancelReadPreparation(); // the warm-up queue on a click
    expect(port.cancels, before);
    release();
    preparation.cancelReadPreparation();
    expect(
      port.cancels,
      before + 1,
      reason: 'without the page, clicks defer as before',
    );
  });
}
