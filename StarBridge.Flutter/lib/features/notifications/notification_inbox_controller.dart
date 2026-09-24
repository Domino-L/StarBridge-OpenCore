import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';

class InboxItem {
  const InboxItem(
    this.reference,
    this.category,
    this.priority,
    this.title,
    this.body,
    this.created,
    this.read,
    this.target,
    this.action,
    this.available,
  );
  final String reference, category, priority, title, body, target, action;
  final DateTime created;
  final bool read, available;
  static InboxItem parse(Map<String, Object?> value) {
    String text(String key) => value[key] is String
        ? value[key] as String
        : throw const FormatException('Invalid inbox text');
    final reference = text('reference');
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(reference) ||
        value['read'] is! bool ||
        value['isAvailable'] is! bool) {
      throw const FormatException('Invalid inbox item');
    }
    return InboxItem(
      reference,
      text('category'),
      text('priority'),
      text('title'),
      text('body'),
      DateTime.parse(text('createdAt')),
      value['read'] as bool,
      text('actionTarget'),
      text('actionLabel'),
      value['isAvailable'] as bool,
    );
  }
}

/// Account-scoped receipt state. Loading the page never marks anything read.
class NotificationInboxController extends ChangeNotifier {
  NotificationInboxController(this.session, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _events = session?.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        _owner = null;
        items = const [];
        ready = false;
        busy = false;
        unread.value = 0;
        notifyListeners();
        unawaited(refresh());
      }
    });
  }
  final BridgeClientSession? session;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  int? _readGeneration;
  final unread = ValueNotifier<int>(0);
  StreamSubscription<BridgeEnvelope>? _events;
  Timer? _timer;
  BridgeAccountContext? _owner;
  int _epoch = 0;
  bool _disposed = false;
  bool busy = false, ready = false;
  String? error;
  List<InboxItem> items = const [];
  void start() {
    unawaited(refresh());
    if (session == null) return;
    _timer ??= Timer.periodic(const Duration(seconds: 60), (_) {
      if (!busy) unawaited(refresh(quiet: true));
    });
  }

  bool _current(int epoch, int generation) =>
      !_disposed && epoch == _epoch && generation == session?.activeGeneration;

  Future<bool> refresh({bool quiet = false, bool reuseFresh = false}) async {
    if (_disposed || busy) return false;
    final bridge = session;
    if (bridge == null ||
        !bridge.hostCapabilities.contains('notificationInbox.read')) {
      error = 'unavailable';
      notifyListeners();
      return false;
    }
    final epoch = _epoch, generation = bridge.activeGeneration;
    final age = _lastSuccessfulRead == null
        ? null
        : _now().difference(_lastSuccessfulRead!);
    if (reuseFresh &&
        ready &&
        error == null &&
        _owner != null &&
        _readGeneration == generation &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 15)) {
      return true;
    }
    busy = true;
    if (!quiet) error = null;
    notifyListeners();
    try {
      final account = await bridge.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      if (!_current(epoch, generation)) return false;
      if (!hasRelayAccount(account)) {
        items = const [];
        ready = false;
        unread.value = 0;
        _owner = null;
        error = 'signedOut';
        return false;
      }
      if (_owner != null && _owner != account.accountContext) {
        items = const [];
        ready = false;
        unread.value = 0;
      }
      _owner = account.accountContext;
      final response = await bridge.request(
        'notificationInbox.read',
        accountContext: _owner,
        payload: const {'schemaVersion': 1},
      );
      if (!_current(epoch, generation)) return false;
      final body = response.payload;
      if (body['schemaVersion'] != 1 || body['items'] is! List) {
        throw const FormatException('Invalid inbox');
      }
      final next = (body['items'] as List)
          .map((v) => InboxItem.parse(Map<String, Object?>.from(v as Map)))
          .toList();
      if (next.length > 5000 ||
          next.map((v) => v.reference).toSet().length != next.length ||
          body['unreadCount'] != next.where((v) => !v.read).length) {
        throw const FormatException('Invalid inbox count');
      }
      items = List.unmodifiable(next);
      unread.value = next.where((v) => !v.read).length;
      ready = true;
      error = null;
      _lastSuccessfulRead = _now();
      _readGeneration = generation;
      return true;
    } catch (_) {
      if (_current(epoch, generation)) error = 'read';
      return false;
    } finally {
      if (_current(epoch, generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> markRead(List<InboxItem> selected) async {
    final bridge = session;
    if (_disposed || busy || !ready || bridge == null || _owner == null) {
      return false;
    }
    final refs = selected
        .where((x) => !x.read && items.contains(x))
        .map((x) => x.reference)
        .toSet()
        .toList();
    if (refs.isEmpty) return true;
    final epoch = _epoch, generation = bridge.activeGeneration;
    busy = true;
    error = null;
    notifyListeners();
    var confirmed = false;
    try {
      final response = await bridge.request(
        'notificationInbox.markRead',
        accountContext: _owner,
        payload: {'schemaVersion': 1, 'references': refs},
      );
      if (!_current(epoch, generation)) return false;
      confirmed =
          response.payload['schemaVersion'] == 1 &&
          response.payload['confirmed'] == true;
      if (!confirmed) error = 'write';
    } catch (_) {
      if (_current(epoch, generation)) error = 'write';
    } finally {
      if (_current(epoch, generation)) {
        busy = false;
        notifyListeners();
      }
    }
    if (confirmed && _current(epoch, generation)) return refresh();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    unawaited(_events?.cancel());
    unread.dispose();
    super.dispose();
  }
}
