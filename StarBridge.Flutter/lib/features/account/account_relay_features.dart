import 'package:flutter/foundation.dart';

import 'account_migration_controller.dart';
import 'account_models.dart';

/// Whether the signed-in SCM-only account still cannot use the relay account
/// features (account playtime, account safety, Recent Players privacy, event
/// sharing, disbanding an organization).
///
/// The relay serves those features to SCM-only accounts once it offers the
/// account migration (switch on). The migration status shared through
/// [account] tells that: while it is offered nothing is blocked. Unknown and
/// unread compatibility states are never blocked, so messages stay unchanged.
bool relayAccountFeaturesBlocked(ValueListenable<AccountProjection> account) {
  final current = account.value;
  if (!current.isSignedIn ||
      !current.compatibility.relayAccountFeaturesUnavailable) {
    return false;
  }
  return AccountMigrationController.sharedFor(account)?.value.offered != true;
}
