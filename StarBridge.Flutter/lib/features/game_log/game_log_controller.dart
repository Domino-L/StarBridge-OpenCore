import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../account/account_models.dart';

class GameLogView {
  const GameLogView({
    this.visible = false,
    this.busy = false,
    this.state = 'notSelected',
    this.path,
    this.handle,
    this.expectedHandle,
    this.match = 'unknown',
    this.enabled = false,
    this.channel = 'LIVE',
    this.selection = 'automatic',
    this.channels = const ['LIVE', 'PTU'],
    this.verifiedChannels = const [],
    this.sessionState = 'unavailable',
    this.serverState = 'unknown',
    this.serverRegion,
    this.serverShard,
    this.locationState = 'unknown',
    this.locationEnglishName,
    this.locationNameZhHans,
    this.locationNameZhHant,
    this.shipState = 'unknown',
    this.shipKey,
    this.shipEnglishName,
    this.shipNameZhHans,
    this.shipNameZhHant,
    this.error,
    this.observedAt,
  });
  final bool visible, busy, enabled;
  final DateTime? observedAt;
  final String state, match, channel, selection, sessionState;
  final String serverState, locationState, shipState;
  final List<String> channels;
  final List<String> verifiedChannels;
  final String? path, handle, expectedHandle, serverRegion, serverShard;
  final String? locationEnglishName, locationNameZhHans, locationNameZhHant;
  final String? shipKey, shipEnglishName, shipNameZhHans, shipNameZhHant, error;

  String? get confirmedVersion =>
      state == 'identified' &&
          match == 'match' &&
          verifiedChannels.contains(channel)
      ? channel
      : null;

  String? shipDisplayName(String languageCode, String? countryCode) {
    if (languageCode == 'zh') {
      if (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO') {
        return shipNameZhHant ?? shipNameZhHans ?? shipEnglishName;
      }
      return shipNameZhHans ?? shipNameZhHant ?? shipEnglishName;
    }
    return shipEnglishName ?? shipNameZhHans ?? shipNameZhHant;
  }

  String? locationDisplayName(String languageCode, String? countryCode) {
    if (languageCode == 'zh') {
      if (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO') {
        return locationNameZhHant ?? locationNameZhHans ?? locationEnglishName;
      }
      return locationNameZhHans ?? locationNameZhHant ?? locationEnglishName;
    }
    return locationEnglishName ?? locationNameZhHans ?? locationNameZhHant;
  }
}

/// Owns only presentation and account-scoped commands. Host owns all file access.
class GameLogController extends ValueNotifier<GameLogView> {
  GameLogController(this.session, this.account, {this.onIdentityChanged})
    : super(const GameLogView()) {
    account.addListener(_accountChanged);
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _key = null;
        _accountChanged();
      }
    });
    _accountChanged();
  }
  final BridgeClientSession session;
  final ValueListenable<AccountProjection> account;
  final VoidCallback? onIdentityChanged;
  late final StreamSubscription<BridgeEnvelope> _events;
  (AccountSessionState, int)? _key;
  BridgeAccountContext? _context;
  Timer? _timer;
  int _epoch = 0;
  bool _disposed = false, _busy = false;
  String? _identity;
  bool get _hasLocalAccount =>
      account.value.sessionState == AccountSessionState.signedIn ||
      account.value.sessionState == AccountSessionState.legacySignedIn;
  static const states = {
    'notSelected',
    'stopped',
    'notRunning',
    'unknown',
    'waiting',
    'reading',
    'identified',
    'ambiguous',
    'unreadable',
    'differentInstallation',
    'notFound',
    'multipleLogs',
    'otherVersion',
  };

  void _accountChanged() {
    final projection = account.value;
    final key = (projection.sessionState, projection.generation);
    if (_key == key) return;
    _key = key;
    _epoch++;
    _context = null;
    _identity = null;
    _busy = false;
    _timer?.cancel();
    value = GameLogView(
      visible:
          _hasLocalAccount && projection.generation == session.activeGeneration,
      error: session.hostCapabilities.contains('gameLog.local')
          ? null
          : 'unsupported',
    );
    if (value.visible && value.error == null) unawaited(run());
  }

  bool _current(int epoch) =>
      !_disposed &&
      epoch == _epoch &&
      _hasLocalAccount &&
      account.value.generation == session.activeGeneration;
  Future<void> pick(Future<String?> Function() picker) =>
      _pick(picker, command: 'select');

  Future<void> addVersion(Future<String?> Function() picker) =>
      _pick(picker, command: 'addVersion');

  Future<void> _pick(
    Future<String?> Function() picker, {
    required String command,
  }) async {
    if (_busy || !value.visible) return;
    _timer?.cancel();
    final epoch = _epoch;
    _busy = true;
    _displayBusy();
    try {
      final path = await picker();
      if (!_current(epoch)) return;
      _busy = false;
      if (path != null) {
        await run(command: command, path: path);
        return;
      }
      await run();
    } on Object {
      if (_current(epoch)) value = _error('picker');
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _schedule();
      }
    }
  }

  GameLogView _error(String error) => GameLogView(
    observedAt: value.observedAt,
    visible: value.visible,
    path: value.path,
    state: value.state,
    enabled: value.enabled,
    channel: value.channel,
    selection: value.selection,
    channels: value.channels,
    verifiedChannels: value.verifiedChannels,
    sessionState: value.sessionState,
    serverState: value.serverState,
    serverRegion: value.serverRegion,
    serverShard: value.serverShard,
    locationState: value.locationState,
    locationEnglishName: value.locationEnglishName,
    locationNameZhHans: value.locationNameZhHans,
    locationNameZhHant: value.locationNameZhHant,
    shipState: value.shipState,
    shipKey: value.shipKey,
    shipEnglishName: value.shipEnglishName,
    shipNameZhHans: value.shipNameZhHans,
    shipNameZhHant: value.shipNameZhHant,
    error: error,
  );
  void _displayBusy() => value = GameLogView(
    observedAt: value.observedAt,
    visible: value.visible,
    busy: true,
    state: value.state,
    path: value.path,
    handle: value.handle,
    expectedHandle: value.expectedHandle,
    match: value.match,
    enabled: value.enabled,
    channel: value.channel,
    selection: value.selection,
    channels: value.channels,
    verifiedChannels: value.verifiedChannels,
    sessionState: value.sessionState,
    serverState: value.serverState,
    serverRegion: value.serverRegion,
    serverShard: value.serverShard,
    locationState: value.locationState,
    locationEnglishName: value.locationEnglishName,
    locationNameZhHans: value.locationNameZhHans,
    locationNameZhHant: value.locationNameZhHant,
    shipState: value.shipState,
    shipKey: value.shipKey,
    shipEnglishName: value.shipEnglishName,
    shipNameZhHans: value.shipNameZhHans,
    shipNameZhHant: value.shipNameZhHant,
  );

  Future<void> run({
    String command = 'read',
    String? path,
    String? channel,
  }) async {
    if (_disposed || _busy || !value.visible || value.error == 'unsupported') {
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _timer?.cancel();
    if (command != 'read' || _context == null) _displayBusy();
    try {
      var context = _context;
      if (context == null) {
        final current = await session.request(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
          timeout: const Duration(seconds: 10),
        );
        if (!_current(epoch)) return;
        if (current.payload['schemaVersion'] != 1 ||
            current.payload['state'] != account.value.sessionState.name ||
            current.sessionGeneration != account.value.generation ||
            current.accountContext == null) {
          throw const FormatException();
        }
        _context = context = current.accountContext!;
      }
      final response = await session.request(
        'gameLog.$command',
        accountContext: context,
        payload: {'schemaVersion': 1, 'path': ?path, 'channel': ?channel},
        timeout: const Duration(seconds: 10),
      );
      if (!_current(epoch)) return;
      final body = response.payload;
      final localSession = body['session'];
      final server = localSession is Map<String, dynamic>
          ? localSession['server']
          : null;
      final location = localSession is Map<String, dynamic>
          ? localSession['location']
          : null;
      final locationNames = location is Map<String, dynamic>
          ? location['names']
          : null;
      final ship = localSession is Map<String, dynamic>
          ? localSession['ship']
          : null;
      final shipNames = ship is Map<String, dynamic> ? ship['names'] : null;
      if (response.sessionGeneration != account.value.generation ||
          response.accountContext?.environment != context.environment ||
          response.accountContext?.authority != context.authority ||
          response.accountContext?.subject != context.subject ||
          body['schemaVersion'] != 1 ||
          !states.contains(body['state']) ||
          body['enabled'] is! bool ||
          body['channel'] is! String ||
          !RegExp(r'^[A-Z0-9_-]{2,32}$').hasMatch(body['channel'] as String) ||
          !const {'automatic', 'manual'}.contains(body['selection']) ||
          body['channels'] is! List ||
          (body['channels'] as List).isEmpty ||
          (body['channels'] as List).length > 16 ||
          !(body['channels'] as List).every(
            (item) =>
                item is String && RegExp(r'^[A-Z0-9_-]{2,32}$').hasMatch(item),
          ) ||
          body['verifiedChannels'] is! List ||
          (body['verifiedChannels'] as List).length > 16 ||
          !(body['verifiedChannels'] as List).every(
            (item) =>
                item is String &&
                RegExp(r'^[A-Z0-9_-]{2,32}$').hasMatch(item) &&
                (body['channels'] as List).contains(item),
          ) ||
          !const {'unknown', 'match', 'mismatch'}.contains(body['match']) ||
          localSession is! Map<String, dynamic> ||
          localSession['schemaVersion'] != 1 ||
          !const {'ready', 'unavailable'}.contains(localSession['state']) ||
          server is! Map<String, dynamic> ||
          !const {
            'unknown',
            'connected',
            'notConnected',
          }.contains(server['state']) ||
          server['region'] != null &&
              !const {'US', 'EU', 'AU', 'ASIA'}.contains(server['region']) ||
          server['shard'] != null &&
              (server['shard'] is! String ||
                  (server['shard'] as String).length > 96 ||
                  !RegExp(r'^pub_[a-z0-9]+(?:[_-][a-z0-9]+){2,15}$')
                      .hasMatch(server['shard'] as String)) ||
          server['state'] != 'connected' &&
              (server['region'] != null || server['shard'] != null) ||
          location is! Map<String, dynamic> ||
          !const {
            'unknown',
            'confirmed',
            'likely',
            'possible',
          }.contains(location['state']) ||
          locationNames is! Map<String, dynamic> ||
          ship is! Map<String, dynamic> ||
          !const {
            'unknown',
            'confirmed',
            'likely',
            'possible',
          }.contains(ship['state']) ||
          shipNames is! Map<String, dynamic> ||
          [
            'path',
            'handle',
            'expectedHandle',
          ].any((key) => body[key] != null && body[key] is! String) ||
          [
            'englishName',
          ].any((key) => location[key] != null && location[key] is! String) ||
          ['zhHans', 'zhHant'].any(
            (key) =>
                locationNames[key] != null && locationNames[key] is! String,
          ) ||
          [
            'key',
            'englishName',
          ].any((key) => ship[key] != null && ship[key] is! String) ||
          [
            'zhHans',
            'zhHant',
          ].any((key) => shipNames[key] != null && shipNames[key] is! String) ||
          localSession['state'] == 'unavailable' &&
              (server['state'] != 'unknown' ||
                  location['state'] != 'unknown' ||
                  ship['state'] != 'unknown') ||
          location['state'] != 'unknown' &&
              location['englishName'] is! String ||
          ship['state'] != 'unknown' &&
              (ship['key'] is! String || ship['englishName'] is! String) ||
          body['handle'] != null && body['state'] != 'identified') {
        throw const FormatException();
      }
      final retainedError = command == 'read' && value.error != 'unavailable'
          ? value.error
          : null;
      value = GameLogView(
        visible: true,
        observedAt: body['observedAtUtc'] is String
            ? DateTime.tryParse(body['observedAtUtc'] as String)?.toLocal()
            : null,
        error: retainedError,
        state: body['state'] as String,
        enabled: body['enabled'] as bool,
        channel: body['channel'] as String,
        selection: body['selection'] as String,
        channels: List<String>.unmodifiable(
          (body['channels'] as List).cast<String>(),
        ),
        verifiedChannels: List<String>.unmodifiable(
          (body['verifiedChannels'] as List).cast<String>(),
        ),
        sessionState: localSession['state'] as String,
        serverState: server['state'] as String,
        serverRegion: server['region'] as String?,
        serverShard: server['shard'] as String?,
        locationState: location['state'] as String,
        locationEnglishName: location['englishName'] as String?,
        locationNameZhHans: locationNames['zhHans'] as String?,
        locationNameZhHant: locationNames['zhHant'] as String?,
        shipState: ship['state'] as String,
        shipKey: ship['key'] as String?,
        shipEnglishName: ship['englishName'] as String?,
        shipNameZhHans: shipNames['zhHans'] as String?,
        shipNameZhHant: shipNames['zhHant'] as String?,
        path: body['path'] as String?,
        handle: body['handle'] as String?,
        expectedHandle: body['expectedHandle'] as String?,
        match: body['match'] as String,
      );
      final identity = value.handle;
      if (_identity != identity) {
        _identity = identity;
        onIdentityChanged?.call();
      }
    } on BridgeRemoteException catch (error) {
      if (_current(epoch)) {
        value = _error(
          const {
                'gameLog.path',
                'gameLog.notFound',
                'gameLog.storage',
                'gameLog.accountChanged',
              }.contains(error.code)
              ? error.code.substring(8)
              : 'unavailable',
        );
      }
    } on Object {
      if (_current(epoch)) value = _error('unavailable');
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _schedule();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_disposed && value.visible && value.error != 'unsupported') {
      _timer = Timer(const Duration(seconds: 3), () => unawaited(run()));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    account.removeListener(_accountChanged);
    unawaited(_events.cancel());
    super.dispose();
  }
}
