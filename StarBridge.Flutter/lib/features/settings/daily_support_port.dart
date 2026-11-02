import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';

class DailySupportResult {
  const DailySupportResult(
    this.outcome, {
    this.entitlement,
    this.expiresAt,
    this.localDay,
  });
  final String outcome;
  final String? entitlement, localDay;
  final DateTime? expiresAt;
  factory DailySupportResult.parse(Map<String, dynamic> body) {
    final outcome = body['outcome'];
    final receipt = body['receipt'];
    if (body['schemaVersion'] != 1 ||
        !['ready', 'granted', 'thanked', 'alreadyClaimed'].contains(outcome) ||
        (receipt != null && receipt is! Map) ||
        (outcome != 'ready' && receipt == null)) {
      throw const FormatException('Unconfirmed support receipt');
    }
    final entitlement = receipt?['entitlement'];
    final expiry = receipt?['expiresAt'];
    final parsed = expiry is String ? DateTime.tryParse(expiry) : null;
    if ((entitlement != null && entitlement is! String) ||
        (entitlement != null && parsed == null) ||
        (outcome == 'granted' && entitlement == null)) {
      throw const FormatException('Unconfirmed support grant');
    }
    return DailySupportResult(
      outcome as String,
      entitlement: entitlement as String?,
      expiresAt: parsed,
      localDay: receipt?['localDay'] as String?,
    );
  }
}

abstract interface class DailySupportPort {
  Stream<void> get invalidations;
  Future<DailySupportResult> claim();
  Future<DailySupportResult> read();
}

class BridgeDailySupport implements DailySupportPort {
  BridgeDailySupport(this.session);
  final BridgeClientSession? session;
  @override
  Stream<void> get invalidations =>
      session?.events
          .where(
            (event) =>
                event.name == 'account.changed' ||
                event.name == 'bootstrap.invalidated',
          )
          .map((_) {}) ??
      const Stream<void>.empty();
  Future<DailySupportResult> _request(bool claim) async {
    final host = session;
    final name = claim ? 'account.supportClaim' : 'account.supportRead';
    if (host == null || !host.hostCapabilities.contains(name)) {
      throw StateError('Daily support unavailable');
    }
    final account = await host.request(
      'account.getCurrent',
      payload: {'schemaVersion': 1},
    );
    if (!hasRelayAccount(account)) throw StateError('Sign in required');
    final generation = host.activeGeneration;
    final response = await host.request(
      name,
      accountContext: account.accountContext,
      payload: {
        'schemaVersion': 1,
        if (claim) 'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      },
      timeout: const Duration(seconds: 20),
    );
    if (host.activeGeneration != generation) {
      throw StateError('Account changed');
    }
    return DailySupportResult.parse(response.payload);
  }

  @override
  Future<DailySupportResult> claim() => _request(true);
  @override
  Future<DailySupportResult> read() => _request(false);
}
