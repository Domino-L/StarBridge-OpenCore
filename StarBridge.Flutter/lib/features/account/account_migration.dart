import 'package:flutter/foundation.dart';

/// Where the old-account migration stands for the signed-in SCM account. The
/// Host never passes an account ID here, only states and counts.
enum AccountMigrationState {
  /// The relay migration switch is off (status 404): no entry, nothing starts.
  unavailable,

  /// No old account linked yet: the entry is the old account sign-in.
  notLinked,
  migrating,
  completed,
  failed,

  /// The relay needs an operator; retrying from the client cannot help.
  recoveryRequired,
}

/// Whether the local data owner alias (plan item 8) is written yet.
enum AccountMigrationLocalData { pending, linked, conflict }

@immutable
final class AccountMigrationView {
  const AccountMigrationView(
    this.state, {
    this.friends = 0,
    this.communities = 0,
    this.merged = 0,
    this.localData = AccountMigrationLocalData.pending,
    this.stillWorking = false,
    this.resultAvailable = true,
  });

  const AccountMigrationView.unavailable()
    : this(AccountMigrationState.unavailable);

  final AccountMigrationState state;
  final int friends;
  final int communities;
  final int merged;
  final AccountMigrationLocalData localData;

  /// Polling stopped after 30 seconds; the minute-long read takes over.
  final bool stillWorking;

  /// The counts are known, so the result can be opened again from the card.
  /// False when the old account is retired but the status is not offered.
  final bool resultAvailable;

  bool get offered => state != AccountMigrationState.unavailable;
}
