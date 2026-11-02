/// Runtime observations only. No saved choice, human acceptance or setup-ready
/// flag is derived from a registration, input count, HWND or frame commit.
abstract interface class NativeOverlayObservationPort {
  Stream<void> get invalidations;
  Future<NativeOverlayObservation?> read();
}

final class NativeOverlayObservation {
  const NativeOverlayObservation({
    required this.generation,
    required this.runtimeId,
    required this.appliedRevision,
    required this.windowState,
    required this.nativeWindowVisible,
    required this.firstFrameCommitted,
    required this.hotkey,
    required this.preview,
  });
  final int generation, appliedRevision;
  final String runtimeId, windowState;
  final bool nativeWindowVisible, firstFrameCommitted;
  final NativeHotkeyObservation hotkey;
  final NativePreviewObservation preview;

  /// A later admitted input is not a successful toggle or physical-key test.
  /// Never reuse a baseline across Native instances, Host generations or chords.
  bool acceptedHotkeyInputSince(NativeOverlayObservation baseline) =>
      generation == baseline.generation &&
      runtimeId == baseline.runtimeId &&
      hotkey.configurationRevision == baseline.hotkey.configurationRevision &&
      hotkey.binding == baseline.hotkey.binding &&
      hotkey.acceptedInputCount > baseline.hotkey.acceptedInputCount;
}

final class NativeHotkeyObservation {
  const NativeHotkeyObservation({
    required this.state,
    required this.binding,
    required this.configurationRevision,
    required this.acceptedInputCount,
    required this.lastOutcome,
  });
  final String state;
  final String? binding, lastOutcome;
  final int configurationRevision, acceptedInputCount;
}

final class NativePreviewObservation {
  const NativePreviewObservation({
    required this.sessionId,
    required this.appliedRevision,
    required this.nativeWindowVisible,
    required this.firstFrameCommitted,
  });
  final String? sessionId;
  final int? appliedRevision;
  final bool nativeWindowVisible, firstFrameCommitted;
}

abstract final class NativeOverlayObservationWire {
  static NativeOverlayObservation parse(
    Map<String, Object?> raw,
    int generation,
  ) {
    _shape(raw, const {
      'schemaVersion',
      'runtimeId',
      'appliedRevision',
      'windowState',
      'nativeWindowVisible',
      'firstFrameCommitted',
      'hotkey',
      'preview',
    });
    if (raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != 1 ||
        !_number(generation) ||
        !_id(raw['runtimeId']) ||
        !_number(raw['appliedRevision']) ||
        !_window(raw['windowState']) ||
        raw['nativeWindowVisible'] is! bool ||
        raw['firstFrameCommitted'] is! bool) {
      _bad();
    }
    final h = _map(raw['hotkey']);
    final p = _map(raw['preview']);
    _shape(h, const {
      'state',
      'binding',
      'configurationRevision',
      'acceptedInputCount',
      'lastOutcome',
    });
    _shape(p, const {
      'sessionId',
      'appliedRevision',
      'nativeWindowVisible',
      'firstFrameCommitted',
    });
    final binding = h['binding'];
    final count = h['acceptedInputCount'];
    if (!const {
          'unavailable',
          'disabled',
          'invalid',
          'registered',
          'gameCompatibleOnly',
          'desktopOnly',
          'conflict',
          'failed',
        }.contains(h['state']) ||
        binding != null &&
            (binding is! String ||
                binding.length > 128 ||
                RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(binding)) ||
        !_number(h['configurationRevision']) ||
        !_number(count) ||
        (count == 0 ? h['lastOutcome'] != null : !_window(h['lastOutcome'])) ||
        p['nativeWindowVisible'] is! bool ||
        p['firstFrameCommitted'] is! bool ||
        (p['sessionId'] == null
            ? p['appliedRevision'] != null ||
                  p['nativeWindowVisible'] != false ||
                  p['firstFrameCommitted'] != false
            : !_id(p['sessionId']) || !_number(p['appliedRevision']))) {
      _bad();
    }
    return NativeOverlayObservation(
      generation: generation,
      runtimeId: raw['runtimeId'] as String,
      appliedRevision: raw['appliedRevision'] as int,
      windowState: raw['windowState'] as String,
      nativeWindowVisible: raw['nativeWindowVisible'] as bool,
      firstFrameCommitted: raw['firstFrameCommitted'] as bool,
      hotkey: NativeHotkeyObservation(
        state: h['state'] as String,
        binding: binding as String?,
        configurationRevision: h['configurationRevision'] as int,
        acceptedInputCount: count as int,
        lastOutcome: h['lastOutcome'] as String?,
      ),
      preview: NativePreviewObservation(
        sessionId: p['sessionId'] as String?,
        appliedRevision: p['appliedRevision'] as int?,
        nativeWindowVisible: p['nativeWindowVisible'] as bool,
        firstFrameCommitted: p['firstFrameCommitted'] as bool,
      ),
    );
  }

  static bool _number(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991;
  static bool _id(Object? value) =>
      value is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(value);
  static bool _window(Object? value) => const {
    'open',
    'closed',
    'opening',
    'suppressed',
    'failed',
    'unavailable',
  }.contains(value);
  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : _bad();
  static void _shape(Map<String, Object?> raw, Set<String> fields) {
    if (raw.length != fields.length ||
        raw.keys.toSet().difference(fields).isNotEmpty) {
      _bad();
    }
  }

  static Never _bad() =>
      throw const FormatException('Invalid native overlay observation.');
}
