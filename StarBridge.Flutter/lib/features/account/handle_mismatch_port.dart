import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';

enum HandleCheckState {
  bound,
  unknown,
  observationRequired,
  consistent,
  ready,
  outcomeUnknown,
}

final class HandleCheckResult {
  const HandleCheckResult(
    this.state,
    this.expectedHandle,
    this.detectedHandle, {
    this.confirmationId,
  });
  final HandleCheckState state;
  final String? expectedHandle, detectedHandle;
  final String? confirmationId;
}

final class HandleNotificationReceipt {
  const HandleNotificationReceipt(
    this.generation,
    this.expectedHandle,
    this.detectedHandle,
  );
  final int generation;
  final String expectedHandle, detectedHandle;
  (int, String, String) get key =>
      (generation, expectedHandle.toLowerCase(), detectedHandle.toLowerCase());
}

/// Detection remains usable with older, read-only Hosts.
abstract interface class HandleMismatchPort {
  Future<HandleCheckResult> check(int generation);
  Future<HandleNotificationReceipt?> notifyBackground(int generation);
}

abstract interface class LegacyHandleChangePort {
  Future<void> confirm(int generation, String confirmationId);
  Future<void> cancel(int generation, String confirmationId);
}

final class BridgeHandleMismatchPort
    implements HandleMismatchPort, LegacyHandleChangePort {
  BridgeHandleMismatchPort(this.session);
  final BridgeClientSession session;

  Future<BridgeEnvelope> _request(
    String name,
    int generation, {
    String? confirmationId,
  }) async {
    if (!session.hostCapabilities.contains(name) ||
        generation != session.activeGeneration) {
      throw const FormatException('Identity check unavailable.');
    }
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (generation != session.activeGeneration ||
        account.sessionGeneration != generation ||
        account.payload['schemaVersion'] is! int ||
        account.payload['schemaVersion'] != 1 ||
        !const {
          'signedIn',
          'legacySignedIn',
        }.contains(account.payload['state']) ||
        account.accountContext == null) {
      throw const FormatException('Identity account changed.');
    }
    final response = await session.request(
      name,
      accountContext: account.accountContext,
      payload: {
        'schemaVersion': 1,
        'confirmationId': ?confirmationId,
      },
      timeout: const Duration(seconds: 75),
    );
    if (generation != session.activeGeneration ||
        response.sessionGeneration != generation ||
        response.accountContext?.environment !=
            account.accountContext!.environment ||
        response.accountContext?.authority !=
            account.accountContext!.authority ||
        response.accountContext?.subject != account.accountContext!.subject ||
        response.payload['schemaVersion'] is! int ||
        response.payload['schemaVersion'] != 1) {
      throw const FormatException('Identity response is not current.');
    }
    return response;
  }

  @override
  Future<HandleCheckResult> check(int generation) async {
    final response = await _request(
      'gameIdentity.prepareHandleChange',
      generation,
    );
    final body = response.payload;
    final state = switch (body['state']) {
      'bound' => HandleCheckState.bound,
      'unknown' => HandleCheckState.unknown,
      'observationRequired' => HandleCheckState.observationRequired,
      'consistent' => HandleCheckState.consistent,
      'ready' => HandleCheckState.ready,
      'outcomeUnknown' => HandleCheckState.outcomeUnknown,
      _ => throw const FormatException('Unsupported identity resolution.'),
    };
    final binding = body['scmBindingState'];
    if (!const {'bound', 'unknown'}.contains(binding) ||
        (state == HandleCheckState.bound && binding != 'bound') ||
        (state == HandleCheckState.unknown && binding != 'unknown')) {
      throw const FormatException('Unverified account binding.');
    }
    String? handle(String key) {
      final value = body[key];
      if (value == null) return null;
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > 128 ||
          value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw const FormatException('Invalid identity handle.');
      }
      return value.trim();
    }

    final id = body['confirmationId'];
    if (body['outcome'] != null ||
        (state == HandleCheckState.ready
            ? body['mode'] != 'legacyCompatibility' ||
                  binding != 'unknown' ||
                  id is! String ||
                  !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
                  !session.hostCapabilities.contains(
                    'gameIdentity.confirmHandleChange',
                  ) ||
                  !session.hostCapabilities.contains(
                    'gameIdentity.cancelHandleChange',
                  )
            : id != null)) {
      throw const FormatException('Unsupported confirmation contract.');
    }
    final expected = handle('expectedHandle'),
        detected = handle('detectedHandle');
    if ((state == HandleCheckState.ready ||
            state == HandleCheckState.bound ||
            state == HandleCheckState.unknown) &&
        (expected == null ||
            detected == null ||
            expected.toLowerCase() == detected.toLowerCase())) {
      throw const FormatException('Incomplete mismatch check.');
    }
    return HandleCheckResult(
      state,
      expected,
      detected,
      confirmationId: id as String?,
    );
  }

  @override
  Future<void> confirm(int generation, String confirmationId) async {
    final response = await _request(
      'gameIdentity.confirmHandleChange',
      generation,
      confirmationId: confirmationId,
    );
    if (response.payload['outcome'] != 'confirmed') {
      throw const FormatException('Unconfirmed identity change.');
    }
  }

  @override
  Future<void> cancel(int generation, String confirmationId) async {
    await _request(
      'gameIdentity.cancelHandleChange',
      generation,
      confirmationId: confirmationId,
    );
  }

  @override
  Future<HandleNotificationReceipt?> notifyBackground(int generation) async {
    try {
      final response = await _request(
        'gameIdentity.notifyMismatch',
        generation,
      );
      if (response.payload['submitted'] is! bool ||
          response.payload['reason'] is! String ||
          response.payload['submitted'] != true) {
        return null;
      }
      final expected = response.payload['authoritativeHandle'];
      final detected = response.payload['detectedHandle'];
      bool valid(Object? value) =>
          value is String &&
          value.trim().isNotEmpty &&
          value.length <= 128 &&
          !value.contains(RegExp(r'[\x00-\x1f\x7f]'));
      if (!valid(expected) || !valid(detected)) return null;
      final oldHandle = (expected as String).trim(),
          newHandle = (detected as String).trim();
      if (oldHandle.toLowerCase() == newHandle.toLowerCase()) return null;
      return HandleNotificationReceipt(generation, oldHandle, newHandle);
    } catch (_) {
      return null;
    }
  }
}
