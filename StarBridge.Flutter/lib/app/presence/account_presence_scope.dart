import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../features/account/account_models.dart';
import 'connected_manual_presence.dart';

/// Shares the existing account's visibility with avatar and tray consumers.
class AccountPresenceScope extends InheritedWidget {
  const AccountPresenceScope({
    required this.account,
    required this.connection,
    required super.child,
    super.key,
  });
  final ValueListenable<AccountProjection> account;
  final ConnectedManualPresence? connection;
  static AccountPresenceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountPresenceScope>();
  @override
  bool updateShouldNotify(AccountPresenceScope oldWidget) =>
      oldWidget.account != account || oldWidget.connection != connection;
}
