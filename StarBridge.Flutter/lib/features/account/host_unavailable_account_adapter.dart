import 'account_models.dart';
import 'account_port.dart';

final class HostUnavailableAccountAdapter implements AccountPort {
  static const _signedOut = AccountHostSnapshot.signedOut(generation: 0);
  static const _failure = AccountFailure(
    code: 'bridge.disconnected',
    messageKey: 'account.error.hostUnavailable',
    retryable: true,
  );

  @override
  Stream<AccountInvalidation> get invalidations => const Stream.empty();

  @override
  Future<AccountPortResult> read() async {
    return AccountPortResult.completed(_signedOut);
  }

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) async {
    return const AccountPortResult.failed(_failure);
  }

  @override
  Future<void> close() async {}
}
