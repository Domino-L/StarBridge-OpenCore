import 'dart:async';

import '../presence/manual_presence.dart';
import 'menu_account_avatar.dart';

import '../../features/friends/friends_module.dart';
import '../../platform/window/menu_preview_window_port.dart';
import '../../platform/window/menu_profile_navigation.dart';

/// Primary-engine account-scoped directory and explicit, confirmed commands.
/// No credentials, Host target refs or command authority cross to the renderer.
final class MenuFriendsSession
    implements
        MenuFriendsReadLease,
        MenuFriendsActionLease,
        MenuChatTargets,
        MenuProfileTargets {
  MenuFriendsSession(
    this._port,
    this._publish, {
    DateTime Function()? now,
    this.presence,
    this.identity,
  }) : _now = now ?? DateTime.now {
    presence?.addListener(_presenceChanged);
    _subscription = _port.invalidations.listen((_) {
      if (_disposed) return;
      _identityEpoch++;
      _ownAvatar.clear();
      _busy = _requiresRefresh = false;
      _feedback = null;
      _section = 'friends';
      _query = null;
      _retire();
      if (_active) unawaited(_read());
    });
  }

  final FriendsPort _port;
  final ManualPresenceController? presence;
  final ({String name, String handle, String? avatar})? Function()? identity;
  late final _ownAvatar = MenuAccountAvatar(() => _emit(_view));
  Object? _presenceScope;
  int _presenceSerial = 0;
  String get _presenceKey {
    if (_presenceScope != presence?.snapshot.scope) {
      _presenceScope = presence?.snapshot.scope;
      _presenceSerial++;
    }
    return 'self$_presenceSerial';
  }

  void _presenceChanged() {
    if (!_disposed && _active) _emit(_view);
  }

  final DateTime Function() _now;
  final void Function(Map<String, Object?>) _publish;
  late final StreamSubscription<void> _subscription;
  Timer? _timer;
  int _epoch = 0;
  int _identityEpoch = 0;
  int _serial = 0;
  Map<String, FriendRow> _targets = {};
  bool _active = false, _reading = false, _disposed = false;
  bool _silentRead = false;
  bool _busy = false, _requiresRefresh = false;
  String _section = 'friends';
  String? _query, _feedback;
  DateTime? _readAt;
  Map<String, Object?> _view = const {'state': 'idle'};
  ({
    String key,
    String ref,
    String action,
    String name,
    String token,
    DateTime expires,
  })?
  _pending;
  int _confirmationSerial = 0;
  bool get _commands =>
      _port is FriendsCommandPort &&
      (_port as FriendsCommandPort).commandsAvailable;
  bool _allowed(FriendRow row, String action) =>
      _commands &&
      row.targetRef != null &&
      row.actions.contains(action) &&
      friendActionsFor(row.relationship).contains(action);

  @override
  MenuChatTarget? chatTarget(String key) {
    final row = _targets[key];
    if (_disposed ||
        !_active ||
        !_fresh ||
        _busy ||
        _requiresRefresh ||
        row == null ||
        row.chatTargetRef == null ||
        row.chatTargetRef!.isEmpty ||
        row.relationship == 'blocked') {
      return null;
    }
    return MenuChatTarget(
      row.chatTargetRef!,
      _text(row.name),
      avatar: _avatar(row.avatar),
      stableKey: row.conversationKey,
    );
  }

  bool get _fresh =>
      _readAt != null &&
      !_now().isBefore(_readAt!) &&
      _now().difference(_readAt!) < const Duration(seconds: 30);

  void _emit(Map<String, Object?> view) {
    _view = view;
    if (!_active || _disposed) return;
    final pending = _pending;
    final own = view['state'] == 'signedOut' ? null : identity?.call();
    final ownPhoto = _ownAvatar.read(own?.avatar);
    _publish({
      ...view,
      'interactive': true,
      'scope': 'friends$_identityEpoch',
      'section': _section,
      'query': _query ?? '',
      'busy': _busy,
      'refreshing': _reading && !_silentRead,
      'feedback': _feedback ?? '',
      'requiresRefresh': _requiresRefresh,
      if (own != null)
        'identity': {
          'name': _text(own.name),
          'handle': _text(own.handle),
          'avatar': ownPhoto,
        },
      'chatKeys': [
        for (final key in _targets.keys)
          if (chatTarget(key) != null) key,
      ],
      if (presence != null && view['state'] != 'signedOut')
        'self': {
          'key': _presenceKey,
          'status': presence!.snapshot.selfKey,
          'change': presence!.canChange,
          'busy': presence!.busy,
          'failed': presence!.failed,
        },
      'actions': {
        if (!_busy && !_requiresRefresh && _fresh)
          for (final entry in _targets.entries)
            entry.key: entry.value.actions
                .where((a) => _allowed(entry.value, a))
                .toList(),
      },
      if (pending != null)
        'confirmation': {
          'token': pending.token,
          'name': pending.name,
          'action': pending.action,
        },
    });
  }

  @override
  void act(String action, String key, String value) {
    if (_disposed || !_active || _busy) return;
    if (action == 'presence') {
      if (key == _presenceKey &&
          presence?.canChange == true &&
          const {'online', 'invisible'}.contains(value)) {
        unawaited(
          presence!.select(
            value == 'online'
                ? PresenceVisibility.online
                : PresenceVisibility.invisible,
          ),
        );
      }
      return;
    }
    if (action == 'dismiss') {
      _pending = null;
      _emit(_view);
      return;
    }
    if (action == 'refresh') {
      _retire();
      unawaited(_read(reconcile: true));
      return;
    }
    if (action == 'section' &&
        const {'friends', 'incoming', 'outgoing', 'blocked'}.contains(value)) {
      _section = value;
      _query = null;
      _retire();
      if (_requiresRefresh) {
        _emit({'state': 'unavailable'});
      } else {
        unawaited(_read());
      }
      return;
    }
    if (action == 'search') {
      final query = value.trim();
      if (query.length < 2 ||
          query.length > 128 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        _feedback = 'invalidSearch';
        _emit(_view);
        return;
      }
      _section = 'search';
      _query = query;
      _retire();
      if (_requiresRefresh) {
        _emit({'state': 'unavailable'});
      } else {
        unawaited(_read());
      }
      return;
    }
    if (action == 'prepare') {
      final row = _targets[key];
      if (_requiresRefresh || !_fresh || row == null || !_allowed(row, value)) {
        return;
      }
      _pending = (
        key: key,
        ref: row.targetRef!,
        action: value,
        name: _text(row.name),
        token: 'confirm${++_confirmationSerial}',
        expires: _now().add(const Duration(seconds: 30)),
      );
      _feedback = null;
      _emit(_view);
      return;
    }
    if (action == 'confirm') {
      final pending = _pending;
      if (pending == null || pending.token != key) return;
      _pending = null;
      final row = _targets[pending.key];
      if (_requiresRefresh ||
          !_fresh ||
          !_now().isBefore(pending.expires) ||
          row == null ||
          row.targetRef != pending.ref ||
          !_allowed(row, pending.action)) {
        _feedback = 'expired';
        _emit(_view);
        return;
      }
      unawaited(_execute(pending.action, pending.ref));
    }
  }

  Future<void> _execute(String action, String ref) async {
    final identity = _identityEpoch;
    _epoch++;
    _reading = false;
    _port.cancelPending();
    _busy = true;
    _feedback = null;
    _emit(_view);
    FriendCommandResult result;
    try {
      result = await (_port as FriendsCommandPort)
          .execute(action, ref)
          .timeout(const Duration(seconds: 15));
    } on Object {
      result = const FriendCommandResult('unknown');
    }
    if (_disposed || identity != _identityEpoch) return;
    _busy = false;
    final directory = result.directory;
    if (result.status == 'accepted' &&
        directory != null &&
        directory.query == null) {
      _query = null;
      _section = switch (action) {
        'send' || 'cancel' => 'outgoing',
        'accept' => 'friends',
        'reject' => 'incoming',
        'block' || 'unblock' => 'blocked',
        _ => 'friends',
      };
      _feedback = 'success.$action';
      if (_active && _project(directory)) return;
      if (!_active) {
        _requiresRefresh = true;
        return;
      }
    }
    _requiresRefresh = true;
    _feedback = result.status == 'rejected' ? 'rejected' : 'unknown';
    _targets = {};
    _emit({'state': 'unavailable'});
  }

  @override
  MenuProfileTarget? profileTarget(String key) {
    final row = _targets[key];
    final ref = row?.targetRef;
    if (_disposed || !_active || row == null || ref == null || ref.isEmpty) {
      return null;
    }
    final epoch = _epoch;
    final identity = _identityEpoch;
    return MenuProfileTarget(
      source: 'friend',
      reference: ref,
      query: row.gameId,
      avatar: _avatar(row.avatar),
      isAccountCurrent: () => !_disposed && identity == _identityEpoch,
      isCurrent: () =>
          !_disposed &&
          _active &&
          epoch == _epoch &&
          _targets[key]?.targetRef == ref,
    );
  }

  @override
  void show(bool visible) {
    if (_disposed || visible == _active) return;
    _active = visible;
    _retire();
    _timer?.cancel();
    _timer = null;
    if (visible) {
      if (_requiresRefresh) {
        _emit({'state': 'unavailable'});
      } else {
        unawaited(_read());
      }
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_read(silent: true));
      });
    }
  }

  void _retire() {
    _epoch++;
    _targets = {};
    _pending = null;
    _readAt = null;
    _reading = false;
    _port.cancelPending();
    _view = {'state': _active ? 'loading' : 'idle'};
    if (_active) {
      _emit(_view);
    } else {
      _publish(_view);
    }
  }

  Future<void> _read({bool reconcile = false, bool silent = false}) async {
    if (_disposed ||
        !_active ||
        _reading ||
        _busy ||
        (_requiresRefresh && !reconcile)) {
      return;
    }
    _reading = true;
    _silentRead = silent;
    if (!silent) _emit(_view);
    final epoch = _epoch;
    FriendsReadResult result;
    try {
      result = await _port
          .read(query: _query)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              if (!_disposed && epoch == _epoch) _port.cancelPending();
              return const FriendsReadResult(FriendsReadState.unavailable);
            },
          );
    } on Object {
      result = const FriendsReadResult(FriendsReadState.unavailable);
    }
    if (_disposed || !_active || epoch != _epoch) return;
    _reading = false;
    final snapshot = result.snapshot;
    if (result.state != FriendsReadState.ready ||
        snapshot == null ||
        snapshot.query != _query) {
      if (silent &&
          result.state == FriendsReadState.unavailable &&
          _view['state'] == 'ready') {
        return;
      }
      _targets = {};
      _pending = null;
      final failure = <String, Object?>{
        'state': result.state == FriendsReadState.signedOut
            ? 'signedOut'
            : 'unavailable',
      };
      _view = failure;
      _emit(failure);
      return;
    }
    if (reconcile) {
      _requiresRefresh = false;
      _feedback = 'reviewed';
    }
    if (!_project(snapshot)) {
      _targets = {};
      _pending = null;
      _emit({'state': 'unavailable'});
    }
  }

  bool _project(FriendsSnapshot snapshot) {
    // Only bounded inline avatars and opaque UI keys cross engines; no target
    // refs, action grants, URLs, endpoints or unfiltered shared maps.
    final rows = _query != null
        ? snapshot.results
        : snapshot.groups[FriendsSection.values.byName(_section)] ?? const [];
    final requests = _section == 'friends' && _query == null
        ? snapshot.groups[FriendsSection.incoming] ?? const <FriendRow>[]
        : const <FriendRow>[];
    if (rows.length + requests.length > 5000) {
      _targets = {};
      return false;
    }
    final previous = {
      for (final e in _targets.entries) e.value.targetRef: e.key,
    };
    final seen = <String>{};
    _targets = {};
    final display = <Map<String, Object?>>[];
    final requestDisplay = <Map<String, Object?>>[];
    var avatarBudget = 512 * 1024;
    for (final row in [...rows, ...requests]) {
      final ref = row.targetRef;
      String? key;
      if (ref != null && ref.isNotEmpty && seen.add(ref)) {
        key = previous[ref] ?? 'f${++_serial}';
        _targets[key] = row;
      }
      final image = _avatar(row.avatar);
      final avatar = image != null && image.length <= avatarBudget
          ? image
          : null;
      avatarBudget -= avatar?.length ?? 0;
      final destination = display.length < rows.length
          ? display
          : requestDisplay;
      destination.add({
        'name': _text(
          _section == 'search'
              ? row.name
              : row.callsign.isEmpty
              ? row.gameId
              : row.callsign,
        ),
        'key': key,
        'avatar': avatar,
        'presence': switch (row.shared['presence']) {
          'InGame' => 'inGame',
          'AppOnline' => 'online',
          'Away' => 'away',
          'Offline' => 'offline',
          _ => 'unknown',
        },
      });
    }
    _readAt = _now();
    final pending = _pending;
    if (pending != null &&
        (_targets[pending.key]?.targetRef != pending.ref ||
            !_allowed(_targets[pending.key]!, pending.action))) {
      _pending = null;
      _feedback = 'expired';
    }
    _emit({
      'state': 'ready',
      'incoming': snapshot.groups[FriendsSection.incoming]?.length ?? 0,
      'rows': display,
      'requests': requestDisplay,
    });
    return true;
  }

  static String? _avatar(String? value) =>
      value != null &&
          value.length <= 128 * 1024 &&
          (value.startsWith('data:image/png;base64,') ||
              value.startsWith('data:image/jpeg;base64,'))
      ? value
      : null;

  static String _text(String value) {
    final clean = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    return clean.length <= 128 ? clean : clean.substring(0, 128);
  }

  @override
  void dispose() {
    presence?.removeListener(_presenceChanged);
    if (_disposed) return;
    show(false);
    _disposed = true;
    _ownAvatar.dispose();
    _epoch++;
    _timer?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_port.close());
  }
}
