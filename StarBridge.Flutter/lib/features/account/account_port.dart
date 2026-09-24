import 'account_models.dart';

abstract interface class AccountPort {
  Stream<AccountInvalidation> get invalidations;

  Future<AccountPortResult> read();

  Future<AccountPortResult> execute(AccountPortCommand command);

  Future<void> close();
}

final class AccountInvalidation {
  const AccountInvalidation({required this.generation});

  final int generation;
}

sealed class AccountPortCommand {
  const AccountPortCommand();
}

final class BeginAccountLogin extends AccountPortCommand {
  const BeginAccountLogin();
}

final class CancelAccountLogin extends AccountPortCommand {
  const CancelAccountLogin();
}

final class LogoutAccount extends AccountPortCommand {
  const LogoutAccount();
}

final class ClearAccountProfileCache extends AccountPortCommand {
  const ClearAccountProfileCache();
}

final class LinkLegacyAccount extends AccountPortCommand {
  const LinkLegacyAccount({this.credential});

  final LegacyAccountCredential? credential;
}

final class CreateCompatibilityIdentity extends AccountPortCommand {
  const CreateCompatibilityIdentity();
}

final class CancelCompatibilityOperation extends AccountPortCommand {
  const CancelCompatibilityOperation();
}

final class LegacyAccountCredential {
  const LegacyAccountCredential({
    required this.accountName,
    required this.password,
  });

  final String accountName;
  final String password;
}

final class SaveAccountPreferences extends AccountPortCommand {
  const SaveAccountPreferences({required this.patch});

  final AccountPreferencePatch patch;
}

final class AccountPreferencePatch {
  const AccountPreferencePatch({
    required this.localeSpecified,
    required this.timeZoneSpecified,
    this.locale,
    this.timeZone,
  });

  final bool localeSpecified;
  final String? locale;
  final bool timeZoneSpecified;
  final String? timeZone;

  bool get isEmpty => !localeSpecified && !timeZoneSpecified;
}

final class AccountPortResult {
  const AccountPortResult({required this.outcome, this.snapshot, this.failure});

  const AccountPortResult.completed(AccountHostSnapshot snapshot)
    : this(outcome: AccountActionOutcome.completed, snapshot: snapshot);

  const AccountPortResult.cancelled(AccountHostSnapshot snapshot)
    : this(outcome: AccountActionOutcome.cancelled, snapshot: snapshot);

  const AccountPortResult.failed(AccountFailure failure)
    : this(outcome: AccountActionOutcome.failed, failure: failure);

  final AccountActionOutcome outcome;
  final AccountHostSnapshot? snapshot;
  final AccountFailure? failure;
}
