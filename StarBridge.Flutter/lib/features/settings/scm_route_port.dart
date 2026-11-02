import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';

/// Which SCM route the Host uses (user-approved preview, 2026-10-29). The Host
/// owns every address; this side only ever sees the four closed values below.
enum ScmRouteMode { auto, overseas }

enum ScmRouteActive { domestic, overseas }

/// Why this run fell back to (or was pinned to) the overseas route.
enum ScmRouteReason { domesticUnavailable, domesticLoginFailed, userOverseas }

final class ScmRouteStatus {
  const ScmRouteStatus({
    required this.mode,
    required this.active,
    required this.reason,
    required this.restartRequired,
  });

  final ScmRouteMode mode;
  final ScmRouteActive active;
  final ScmRouteReason? reason;

  /// The saved mode differs from the one this run started with.
  final bool restartRequired;
}

abstract interface class ScmRoutePort {
  Future<ScmRouteStatus> read();
  Future<ScmRouteStatus> save(ScmRouteMode mode);
}

final class BridgeScmRoute implements ScmRoutePort {
  BridgeScmRoute(this._session);
  final BridgeClientSession _session;

  static const readRequest = 'account.scmRouteRead';
  static const saveRequest = 'account.scmRouteSave';

  static bool supported(BridgeClientSession session) =>
      session.hostCapabilities.contains(readRequest) &&
      session.hostCapabilities.contains(saveRequest);

  @override
  Future<ScmRouteStatus> read() async => parse(
    (await _session.request(
      readRequest,
      payload: const {'schemaVersion': 1},
    )).payload,
  );

  @override
  Future<ScmRouteStatus> save(ScmRouteMode mode) async => parse(
    (await _session.request(
      saveRequest,
      payload: {'schemaVersion': 1, 'mode': mode.name},
    )).payload,
  );

  static ScmRouteStatus parse(Map<String, Object?> payload) {
    T? pick<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    final mode = pick(ScmRouteMode.values, payload['mode']);
    final active = pick(ScmRouteActive.values, payload['active']);
    final rawReason = payload['reason'];
    final reason = pick(ScmRouteReason.values, rawReason);
    final restart = payload['restartRequired'];
    if (payload.length != 4 ||
        !payload.containsKey('reason') ||
        mode == null ||
        active == null ||
        (rawReason != null && reason == null) ||
        restart is! bool) {
      throw const BridgeFormatException('SCM route response is incompatible.');
    }
    return ScmRouteStatus(
      mode: mode,
      active: active,
      reason: reason,
      restartRequired: restart,
    );
  }
}
