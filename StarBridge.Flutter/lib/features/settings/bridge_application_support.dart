import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'application_support_models.dart';
import 'application_support_port.dart';

final class BridgeApplicationSupport implements ApplicationSupportPort {
  BridgeApplicationSupport(this._session);

  final BridgeClientSession _session;

  @override
  Future<ApplicationSupportSnapshot> inspect() async {
    try {
      final response = await _session.request(
        'diagnostics.getSafeSummary',
        payload: const {'schemaVersion': 1},
      );
      return _parse(response.payload);
    } on Object catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> openDataDirectory() async {
    try {
      final response = await _session.request(
        'diagnostics.openDataDirectory',
        payload: const {'schemaVersion': 1},
      );
      if (response.payload['schemaVersion'] != 1 ||
          response.payload['opened'] != true ||
          response.payload.length != 2) {
        throw const BridgeFormatException(
          'Open data directory response is incompatible.',
        );
      }
    } on Object catch (error) {
      throw _mapError(error);
    }
  }

  static ApplicationSupportSnapshot _parse(Map<String, Object?> payload) {
    if (payload['schemaVersion'] != 1) {
      throw const BridgeFormatException(
        'Application support schema version is incompatible.',
      );
    }
    final checksValue = payload['checks'];
    if (checksValue is! Map) {
      throw const BridgeFormatException(
        'Application support checks are missing.',
      );
    }
    final checks = checksValue.cast<String, Object?>();
    final dataDirectory = _basic(checks, 'dataDirectory');
    final gameLog = _basic(checks, 'gameLog');
    final startupValue = _requiredMap(checks, 'startup');
    final installationValue = _requiredMap(checks, 'installation');
    final snapshot = ApplicationSupportSnapshot(
      hasIssues: _requiredBool(payload, 'hasIssues'),
      hasUnavailableChecks: _requiredBool(payload, 'hasUnavailableChecks'),
      dataDirectory: dataDirectory,
      gameLog: gameLog,
      connection: checks['connection'] == null ? null : _basic(checks, 'connection'),
      startup: ApplicationStartupCheck(
        state: _state(startupValue),
        detail: _requiredString(startupValue, 'detail'),
        registered: _requiredBool(startupValue, 'registered'),
        targetExists: _optionalBool(startupValue, 'targetExists'),
        targetsCurrentExecutable: _optionalBool(
          startupValue,
          'targetsCurrentExecutable',
        ),
      ),
      installation: ApplicationInstallationCheck(
        state: _state(installationValue),
        detail: _requiredString(installationValue, 'detail'),
        mode: _requiredString(installationValue, 'mode'),
        currentInstallations: _requiredCount(
          installationValue,
          'currentInstallations',
        ),
        otherInstallations: _requiredCount(
          installationValue,
          'otherInstallations',
        ),
        orphanedRegistrations: _requiredCount(
          installationValue,
          'orphanedRegistrations',
        ),
        scanWarnings: _requiredCount(installationValue, 'scanWarnings'),
      ),
    );
    final projectedIssues = snapshot.checks.any(
      (check) => check.state == ApplicationSupportCheckState.actionRequired,
    );
    final projectedUnavailable = snapshot.checks.any(
      (check) => check.state == ApplicationSupportCheckState.unavailable,
    );
    if (snapshot.hasIssues != projectedIssues ||
        snapshot.hasUnavailableChecks != projectedUnavailable) {
      throw const BridgeFormatException(
        'Application support summary does not match its checks.',
      );
    }
    return snapshot;
  }

  static ApplicationSupportCheck _basic(
    Map<String, Object?> checks,
    String name,
  ) {
    final value = _requiredMap(checks, name);
    return ApplicationSupportCheck(
      state: _state(value),
      detail: _requiredString(value, 'detail'),
    );
  }

  static ApplicationSupportCheckState _state(Map<String, Object?> value) =>
      switch (_requiredString(value, 'state')) {
        'healthy' => ApplicationSupportCheckState.healthy,
        'actionRequired' => ApplicationSupportCheckState.actionRequired,
        'unavailable' => ApplicationSupportCheckState.unavailable,
        _ => throw const BridgeFormatException(
          'Application support check state is unsupported.',
        ),
      };

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value is! Map) {
      throw BridgeFormatException('$key must be an object.');
    }
    return value.cast<String, Object?>();
  }

  static String _requiredString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! String || value.trim().isEmpty) {
      throw BridgeFormatException('$key must be a non-empty string.');
    }
    return value.trim();
  }

  static bool _requiredBool(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! bool) {
      throw BridgeFormatException('$key must be a boolean.');
    }
    return value;
  }

  static bool? _optionalBool(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value == null) return null;
    if (value is! bool) {
      throw BridgeFormatException('$key must be a boolean or null.');
    }
    return value;
  }

  static int _requiredCount(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! int || value < 0) {
      throw BridgeFormatException('$key must be a non-negative integer.');
    }
    return value;
  }

  static ApplicationSupportException _mapError(Object error) {
    if (error is BridgeTimeoutException) {
      return const ApplicationSupportException(
        ApplicationSupportFailure.timeout,
        retryable: true,
      );
    }
    if (error is BridgeDisconnectedException ||
        error is BridgeStaleGenerationException) {
      return const ApplicationSupportException(
        ApplicationSupportFailure.hostUnavailable,
        retryable: true,
      );
    }
    if (error is BridgeFormatException) {
      return const ApplicationSupportException(
        ApplicationSupportFailure.invalidResponse,
      );
    }
    if (error is BridgeClientException &&
        (error.code == 'diagnostics.inspection_failed' ||
            error.code == 'diagnostics.open_failed')) {
      return ApplicationSupportException(
        ApplicationSupportFailure.inspectionFailed,
        retryable: error.retryable,
      );
    }
    return const ApplicationSupportException(
      ApplicationSupportFailure.inspectionFailed,
      retryable: true,
    );
  }

  @override
  Future<void> close() async {}
}
