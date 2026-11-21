import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'account_migration.dart';

/// What the Host reports; never an account ID (account plan item 9).
final class AccountMigrationReading {
  const AccountMigrationReading({
    required this.available,
    required this.state,
    this.friends = 0,
    this.communities = 0,
    this.merged = 0,
    this.recoveryRequired = false,
    this.localData = AccountMigrationLocalData.pending,
    this.resultPending = false,
  });

  const AccountMigrationReading.unavailable()
    : this(available: false, state: 'none');

  final bool available;

  /// none / migrating / completed / failed, as the relay says.
  final String state;
  final int friends;
  final int communities;
  final int merged;
  final bool recoveryRequired;
  final AccountMigrationLocalData localData;

  /// Completed and its result was not shown on this computer yet.
  final bool resultPending;

  static AccountMigrationReading parse(Map<String, Object?> body) {
    int count(String name) {
      final value = body[name];
      if (value is! int || value < 0) throw const FormatException();
      return value;
    }

    final state = body['state'];
    final available = body['available'];
    if (body['schemaVersion'] != 1 ||
        available is! bool ||
        !const {'none', 'migrating', 'completed', 'failed'}.contains(state) ||
        body['recoveryRequired'] is! bool ||
        body['resultPending'] is! bool) {
      throw const FormatException();
    }
    return AccountMigrationReading(
      available: available,
      state: state as String,
      friends: count('friends'),
      communities: count('communities'),
      merged: count('merged'),
      recoveryRequired: body['recoveryRequired'] as bool,
      localData: switch (body['localData']) {
        'linked' => AccountMigrationLocalData.linked,
        'conflict' => AccountMigrationLocalData.conflict,
        'pending' => AccountMigrationLocalData.pending,
        _ => throw const FormatException(),
      },
      resultPending: body['resultPending'] as bool,
    );
  }
}

abstract interface class AccountMigrationPort {
  bool get supported;

  /// [refresh] first runs the compatibility read, which is what lets the relay
  /// migrate a linked account and lets the Host write the local owner alias.
  Future<AccountMigrationReading> read({bool refresh = false});
  Future<AccountMigrationReading> retry();

  /// Marks the result as shown on this computer.
  Future<void> acknowledge();
}

final class BridgeAccountMigration implements AccountMigrationPort {
  BridgeAccountMigration(this._session);
  final BridgeClientSession _session;

  static const capability = 'account.migration';

  @override
  bool get supported => _session.hostCapabilities.contains(capability);

  @override
  Future<AccountMigrationReading> read({bool refresh = false}) =>
      _reading('account.migration.status', {'refresh': refresh});

  @override
  Future<AccountMigrationReading> retry() =>
      _reading('account.migration.retry', const {});

  @override
  Future<void> acknowledge() async {
    if (!supported) return;
    await _send('account.migration.acknowledge', const {});
  }

  Future<AccountMigrationReading> _reading(
    String name,
    Map<String, Object?> payload,
  ) async {
    if (!supported) return const AccountMigrationReading.unavailable();
    return AccountMigrationReading.parse(await _send(name, payload));
  }

  Future<Map<String, Object?>> _send(
    String name,
    Map<String, Object?> payload,
  ) async {
    final account = await _session
        .beginRequest('account.getCurrent', payload: const {'schemaVersion': 1})
        .future;
    if (account.payload['state'] != 'signedIn' ||
        account.accountContext == null) {
      throw const AccountMigrationSignedOut();
    }
    final response = await _session
        .beginRequest(
          name,
          accountContext: account.accountContext,
          payload: {'schemaVersion': 1, ...payload},
          // A refresh runs the compatibility read and then the status read.
          timeout: const Duration(seconds: 40),
        )
        .future;
    return response.payload;
  }
}

/// Only an SCM sign-in can migrate; a legacy password session cannot.
final class AccountMigrationSignedOut implements Exception {
  const AccountMigrationSignedOut();
}
