import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../account/account_models.dart';

final class GameplayHistoryPreview {
  const GameplayHistoryPreview(
    this.id,
    this.seconds,
    this.sessions,
    this.incompleteSessions,
    this.skippedFiles,
  );
  final String id;
  final int seconds;
  final int sessions;
  final int incompleteSessions;
  final int skippedFiles;
}

final class GameplayTimeView {
  const GameplayTimeView({
    this.visible = true,
    this.busy = false,
    this.consent = 'unknown',
    this.seconds,
    this.savedSeconds,
    this.recording = false,
    this.gameState = 'unknown',
    this.showOnProfile = true,
    this.historySupported = false,
    this.historyState = 'unchecked',
    this.historicalSeconds = 0,
    this.historyImportedAt,
    this.preview,
    this.historyError,
    this.operation,
    this.error,
    this.resetState,
  });
  final bool visible;
  final bool busy;
  final String consent;
  final int? seconds;
  final int? savedSeconds;
  final bool recording;
  final String gameState;
  final bool showOnProfile;
  final bool historySupported;
  final String historyState;
  final int historicalSeconds;
  final String? historyImportedAt;
  final GameplayHistoryPreview? preview;
  final String? historyError;
  final String? operation;
  final String? error;
  final String? resetState;

  GameplayTimeView copyWith({
    bool? busy,
    bool? recording,
    String? gameState,
    String? operation,
    String? historyState,
    GameplayHistoryPreview? preview,
    bool clearPreview = false,
    String? historyError,
    bool clearHistoryError = false,
    String? error,
    String? resetState,
  }) => GameplayTimeView(
    visible: visible,
    busy: busy ?? this.busy,
    consent: consent,
    seconds: seconds,
    savedSeconds: savedSeconds,
    recording: recording ?? this.recording,
    gameState: gameState ?? this.gameState,
    showOnProfile: showOnProfile,
    historySupported: historySupported,
    historyState: historyState ?? this.historyState,
    historicalSeconds: historicalSeconds,
    historyImportedAt: historyImportedAt,
    preview: clearPreview ? null : preview ?? this.preview,
    historyError: clearHistoryError ? null : historyError ?? this.historyError,
    operation: busy == false ? null : operation ?? this.operation,
    error: error ?? this.error,
    resetState: resetState ?? this.resetState,
  );
}

/// Account changes clear the previous view immediately. Host owns sampling and IO.
final class GameplayTimeController extends ValueNotifier<GameplayTimeView> {
  GameplayTimeController(this._session, this._account)
    : super(const GameplayTimeView(visible: false)) {
    _account.addListener(_accountChanged);
    _events = _session.events.listen((event) {
      if (event.name != 'account.changed' &&
          event.name != 'bootstrap.invalidated') {
        return;
      }
      _accountKey = null;
      _accountChanged();
    });
    _accountChanged();
  }
  final BridgeClientSession _session;
  final ValueListenable<AccountProjection> _account;
  late final StreamSubscription<BridgeEnvelope> _events;
  (AccountSessionState, int)? _accountKey;
  BridgeAccountContext? _context;
  Timer? _timer;
  int _epoch = 0;
  bool _disposed = false;
  bool _inFlight = false;
  bool? _pendingConsent;
  bool? _pendingVisibility;
  static const _historyStates = {
    'unchecked',
    'available',
    'imported',
    'unavailable',
    'identityRequired',
    'overlapUnknown',
  };
  static const _historyResults = {
    ..._historyStates,
    'busy',
    'empty',
    'path',
    'limit',
    'previewExpired',
    'accountChanged',
    'cancelled',
    'recordingRequired',
  };

  void _accountChanged() {
    final account = _account.value;
    final key = (account.sessionState, account.generation);
    if (_accountKey == key) return;
    _accountKey = key;
    _epoch++;
    _context = null;
    _pendingConsent = null;
    _pendingVisibility = null;
    _inFlight = false;
    _timer?.cancel();
    value = GameplayTimeView(
      visible:
          (account.isSignedIn || account.isLegacyAccount) &&
          account.generation == _session.activeGeneration,
      historySupported: _session.hostCapabilities.contains(
        'gameplayTime.history',
      ),
      error: _session.hostCapabilities.contains('gameplayTime.local')
          ? null
          : 'unsupported',
    );
    if (value.visible && value.error == null) unawaited(_run());
  }

  Future<void> setAllowed(bool allowed) async {
    if (!_canStart || value.preview != null) return;
    _pendingConsent = allowed;
    await _run(allowed: allowed, foreground: true);
  }

  Future<void> retry() => _run(
    allowed: _pendingConsent,
    showOnProfile: _pendingConsent == null ? _pendingVisibility : null,
    retry: _pendingConsent == null && _pendingVisibility == null,
    foreground: true,
  );

  bool get _canStart =>
      !_disposed && !_inFlight && value.visible && value.error != 'unsupported';

  bool get resetSupported =>
      _session.hostCapabilities.contains('gameplayTime.reset');

  Future<void> resetTime(Future<bool> Function() confirm) async {
    if (!_canStart ||
        !resetSupported ||
        value.preview != null ||
        value.resetState == 'pending') {
      return;
    }
    final epoch = _epoch;
    _inFlight = true;
    _timer?.cancel();
    value = value.copyWith(
      busy: true,
      operation: 'reset',
      resetState: 'checking',
    );
    var submitted = false;
    try {
      final context = _context ?? await _readContext();
      if (!_current(epoch)) return;
      _context = context;
      final preview = await _historyRequest('resetPreview', {}, context);
      if (!_current(epoch)) return;
      _validateHistory(preview, context);
      final state = preview.payload['state'];
      if (state != 'ready') {
        value = value.copyWith(
          resetState: state == 'pending' ? 'pending' : 'unavailable',
        );
        return;
      }
      final id = preview.payload['previewId'];
      if (id is! String || !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(id)) {
        throw const FormatException();
      }
      value = value.copyWith(operation: 'resetConfirmation');
      if (!await confirm()) {
        if (_current(epoch)) value = value.copyWith(resetState: 'idle');
        return;
      }
      if (!_current(epoch)) return;
      value = value.copyWith(operation: 'reset');
      submitted = true;
      final response = await _historyRequest('resetConfirm', {
        'previewId': id,
      }, context);
      if (!_current(epoch)) return;
      _validateHistory(response, context);
      final outcome = response.payload['state'];
      value = value.copyWith(
        resetState:
            const {
              'completed',
              'pending',
              'conflict',
              'previewExpired',
            }.contains(outcome)
            ? outcome as String
            : 'unavailable',
      );
    } on Object {
      if (_current(epoch)) {
        value = value.copyWith(
          resetState: submitted ? 'pending' : 'unavailable',
        );
      }
    } finally {
      if (_current(epoch)) {
        _inFlight = false;
        value = value.copyWith(busy: false);
        await _run();
      }
    }
  }

  Future<void> setVisibility(bool show) async {
    if (!_canStart || !value.historySupported || value.preview != null) return;
    _pendingVisibility = show;
    await _run(showOnProfile: show, foreground: true);
  }

  Future<void> _run({
    bool? allowed,
    bool? showOnProfile,
    bool retry = false,
    bool foreground = false,
  }) async {
    if (!_canStart || value.preview != null) {
      return;
    }
    _timer?.cancel();
    final epoch = _epoch;
    _inFlight = true;
    value = value.copyWith(
      busy: true,
      operation: foreground || value.seconds == null ? 'stats' : null,
    );
    try {
      final context = _context ?? await _readContext();
      if (!_current(epoch)) return;
      _context = context;
      if (value.resetState == 'pending' && resetSupported) {
        final reset = await _historyRequest('resetStatus', {}, context);
        if (!_current(epoch)) return;
        _validateHistory(reset, context);
        if (reset.payload['state'] == 'idle') {
          value = value.copyWith(resetState: 'idle');
        }
      }
      final response = await _session.request(
        allowed != null
            ? 'gameplayTime.setConsent'
            : showOnProfile != null
            ? 'gameplayTime.setVisibility'
            : retry
            ? 'gameplayTime.retry'
            : 'gameplayTime.read',
        accountContext: context,
        payload: {
          'schemaVersion': 1,
          'allowed': ?allowed,
          'showOnProfile': ?showOnProfile,
        },
        timeout: const Duration(seconds: 10),
      );
      if (!_current(epoch)) return;
      final body = response.payload;
      final seconds = body['seconds'];
      final saved = body['savedSeconds'];
      final consent = body['consent'];
      final shown = body['showOnProfile'] ?? true;
      final history = body['historyState'] ?? 'unchecked';
      final historical = body['historicalSeconds'] ?? 0;
      if (response.sessionGeneration != _account.value.generation ||
          response.accountContext?.environment != context.environment ||
          response.accountContext?.authority != context.authority ||
          response.accountContext?.subject != context.subject ||
          body['schemaVersion'] != 1 ||
          !const ['unknown', 'allowed', 'declined'].contains(consent) ||
          seconds != null && (seconds is! int || seconds < 0) ||
          saved != null && (saved is! int || saved < 0) ||
          (seconds == null) != (saved == null) ||
          seconds is int && saved is int && saved > seconds ||
          body['recording'] == true &&
              (consent != 'allowed' || body['error'] != null) ||
          body['recording'] is! bool ||
          !const [
            'unknown',
            'running',
            'notRunning',
          ].contains(body['gameState']) ||
          body['error'] != null && body['error'] is! String ||
          shown is! bool ||
          !_historyStates.contains(history) ||
          historical is! int ||
          historical < 0 ||
          body['historyImportedAt'] != null &&
              body['historyImportedAt'] is! String) {
        throw const FormatException('Invalid local gameplay time response');
      }
      // A valid command response reports the Host's pending decision too. Storage
      // failures are recovered with retry; only a lost response resends consent.
      if (allowed != null ||
          _pendingConsent != null &&
              body['error'] == null &&
              consent == (_pendingConsent! ? 'allowed' : 'declined')) {
        _pendingConsent = null;
      }
      if (showOnProfile != null ||
          _pendingVisibility == shown && body['error'] == null) {
        _pendingVisibility = null;
      }
      value = GameplayTimeView(
        consent: consent as String,
        seconds: seconds as int?,
        savedSeconds: saved as int?,
        recording: body['recording'] as bool,
        gameState: body['gameState'] as String,
        showOnProfile: shown,
        historySupported: value.historySupported,
        historyState: history as String,
        historicalSeconds: historical,
        historyImportedAt: body['historyImportedAt'] as String?,
        historyError: value.historyError,
        resetState: value.resetState,
        error: _pendingConsent == false && body['error'] == null
            ? 'stopUnconfirmed'
            : _pendingVisibility != null && body['error'] == null
            ? 'visibilityUnconfirmed'
            : body['error'] as String?,
      );
    } on Object {
      if (_current(epoch)) {
        value = value.copyWith(
          recording: false,
          gameState: 'unknown',
          error: _pendingConsent == false
              ? 'stopUnconfirmed'
              : _pendingVisibility != null
              ? 'visibilityUnconfirmed'
              : 'unavailable',
        );
      }
    } finally {
      if (_current(epoch)) {
        _inFlight = false;
        value = value.copyWith(busy: false);
        _schedule();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_disposed &&
        value.visible &&
        value.error != 'unsupported' &&
        value.preview == null) {
      _timer = Timer(const Duration(seconds: 5), () => unawaited(_run()));
    }
  }

  /// A picker result, preview and confirmation all belong to this account epoch.
  Future<void> importHistory(Future<String?> Function() pickLog) async {
    if (!_canStart ||
        !value.historySupported ||
        value.historyState == 'imported' ||
        value.preview != null) {
      return;
    }
    final epoch = _epoch;
    _inFlight = true;
    _timer?.cancel();
    value = value.copyWith(
      busy: true,
      operation: 'checking',
      clearHistoryError: true,
    );
    try {
      final context = _context ?? await _readContext();
      if (!_current(epoch)) return;
      _context = context;
      final response = await _historyRequest('historyStatus', {}, context);
      if (!_current(epoch)) return;
      final state = _historyResult(response, context);
      _setHistoryResult(state);
      if (state != 'available') return;
      value = value.copyWith(operation: 'choosing');
      final path = await pickLog();
      if (!_current(epoch) || path == null) return;
      value = value.copyWith(operation: 'previewing');
      final preview = await _historyRequest('historyPreview', {
        'path': path,
      }, context);
      if (!_current(epoch)) return;
      _validateHistory(preview, context);
      final body = preview.payload;
      if (body['state'] != 'preview') {
        _setHistoryResult(_historyResult(preview, context));
        return;
      }
      if (body['previewId'] is! String ||
          (body['previewId'] as String).isEmpty ||
          ![
            'seconds',
            'sessions',
            'incompleteSessions',
            'skippedFiles',
          ].every((key) => body[key] is int && (body[key] as int) >= 0)) {
        throw const FormatException('Invalid history preview');
      }
      value = value.copyWith(
        preview: GameplayHistoryPreview(
          body['previewId'] as String,
          body['seconds'] as int,
          body['sessions'] as int,
          body['incompleteSessions'] as int,
          body['skippedFiles'] as int,
        ),
      );
    } on Object {
      if (_current(epoch)) value = value.copyWith(historyError: 'unavailable');
    } finally {
      _finishHistory(epoch);
    }
  }

  Future<void> confirmHistory(GameplayHistoryPreview preview) async {
    if (!_canStart || !identical(preview, value.preview)) return;
    final epoch = _epoch;
    _inFlight = true;
    value = value.copyWith(
      busy: true,
      operation: 'confirming',
      clearHistoryError: true,
    );
    try {
      final context = _context!;
      final response = await _historyRequest('historyConfirm', {
        'previewId': preview.id,
      }, context);
      if (!_current(epoch)) return;
      final state = _historyResult(response, context);
      if (state == 'imported') {
        value = value.copyWith(
          historyState: 'imported',
          clearPreview: true,
          clearHistoryError: true,
        );
      } else if (state == 'busy' || state == 'unavailable') {
        value = value.copyWith(historyError: state);
      } else {
        _setHistoryResult(state);
        value = value.copyWith(clearPreview: true);
      }
    } on Object {
      // Only an explicit retry resends this exact id after an uncertain result.
      if (_current(epoch)) {
        value = value.copyWith(historyError: 'confirmUncertain');
      }
    } finally {
      _finishHistory(epoch);
    }
    if (_current(epoch) && value.historyState == 'imported') {
      await _run(foreground: true);
    }
  }

  void cancelPreview(GameplayHistoryPreview preview) {
    if (_disposed || value.busy || !identical(value.preview, preview)) return;
    value = value.copyWith(clearPreview: true, clearHistoryError: true);
    _schedule();
  }

  void _finishHistory(int epoch) {
    if (!_current(epoch)) return;
    _inFlight = false;
    value = value.copyWith(busy: false);
    _schedule();
  }

  Future<BridgeEnvelope> _historyRequest(
    String name,
    Map<String, Object?> body,
    BridgeAccountContext context,
  ) => _session.request(
    'gameplayTime.$name',
    accountContext: context,
    payload: {'schemaVersion': 1, ...body},
    timeout: const Duration(seconds: 65),
  );

  void _validateHistory(BridgeEnvelope response, BridgeAccountContext context) {
    if (response.sessionGeneration != _account.value.generation ||
        response.accountContext?.environment != context.environment ||
        response.accountContext?.authority != context.authority ||
        response.accountContext?.subject != context.subject ||
        response.payload['schemaVersion'] != 1) {
      throw const FormatException();
    }
  }

  String _historyResult(BridgeEnvelope response, BridgeAccountContext context) {
    _validateHistory(response, context);
    final state = response.payload['state'];
    if (!_historyResults.contains(state)) throw const FormatException();
    return state as String;
  }

  void _setHistoryResult(String state) {
    value = _historyStates.contains(state)
        ? value.copyWith(historyState: state, clearHistoryError: true)
        : value.copyWith(historyError: state);
  }

  bool _current(int epoch) =>
      !_disposed &&
      epoch == _epoch &&
      (_account.value.isSignedIn || _account.value.isLegacyAccount) &&
      _account.value.generation == _session.activeGeneration;

  Future<BridgeAccountContext> _readContext() async {
    final response = await _session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 10),
    );
    if (response.payload['schemaVersion'] != 1 ||
        !const {
          'signedIn',
          'legacySignedIn',
          'legacyUnavailable',
        }.contains(response.payload['state']) ||
        response.sessionGeneration != _account.value.generation ||
        response.accountContext == null) {
      throw const FormatException();
    }
    return response.accountContext!;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _account.removeListener(_accountChanged);
    unawaited(_events.cancel());
    super.dispose();
  }
}
