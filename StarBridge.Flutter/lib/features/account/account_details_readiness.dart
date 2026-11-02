import 'account_module.dart';

/// Optional (2026-10-22): whether everything the account page shows after a
/// sign-in has been read or has failed: the staged details (profile, time
/// zones, game identity, compatibility) and the call sign. The login dialog
/// finishes only then. Not notified on its own; callers re-check.
abstract interface class AccountDetailsReadiness {
  bool get signedInDetailsSettled;
}

extension AccountDetailsSettled on AccountModule {
  bool get signedInDetailsSettled => switch (this) {
    final AccountDetailsReadiness readiness => readiness.signedInDetailsSettled,
    _ => projection.value.isSignedIn,
  };
}
