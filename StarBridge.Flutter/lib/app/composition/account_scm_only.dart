import 'package:flutter/foundation.dart';

import '../../features/account/account_migration_controller.dart';
import '../../features/account/account_models.dart';
import '../../features/account/account_relay_features.dart';

/// Tells features, without handing them account details, whether the signed-in
/// account cannot use the relay account features yet (see
/// [relayAccountFeaturesBlocked]). Unknown and unread compatibility states read
/// as false, so messages stay unchanged. Once the relay offers the migration
/// (the shared migration status), nothing is blocked.
final class AccountScmOnly extends ChangeNotifier
    implements ValueListenable<bool> {
  AccountScmOnly(this._account)
    : _migration = AccountMigrationController.offerChangesFor(_account),
      _value = relayAccountFeaturesBlocked(_account) {
    _account.addListener(_changed);
    _migration.addListener(_changed);
  }

  final ValueListenable<AccountProjection> _account;
  final Listenable _migration;
  bool _value;

  void _changed() {
    final next = relayAccountFeaturesBlocked(_account);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  bool get value => _value;

  @override
  void dispose() {
    _account.removeListener(_changed);
    _migration.removeListener(_changed);
    super.dispose();
  }
}
