import 'dart:async';

import 'package:flutter/foundation.dart';

import '../communities/community_ships_port.dart';

/// How many ships are shared with the main fleet, for the rail's ships tile.
/// The first page of the ships read already carries the total, so the tile
/// never walks the whole inventory. This read carries no owner presence, so
/// unlike a community tile there is no online and offline split to show.
///
/// Each read also verifies up to 20 owners with the partner, so there is no
/// timer: one read per visit, and again when sharing is reported changed.
final class OfficialFleetShipCount extends ChangeNotifier {
  OfficialFleetShipCount({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Coming back to the page sooner than this keeps the count it had.
  static const revisitAge = Duration(minutes: 5);

  final DateTime Function() _now;
  CommunityShipsPort? _port;
  String? _target;
  StreamSubscription<void>? _invalidations, _refreshes;
  DateTime? _readAt;
  int _epoch = 0;
  bool _stale = false, _left = false, _closed = false;

  int? get count => _count;
  int? _count;
  bool get failed => _failed;
  bool _failed = false;
  bool get reading => _reading;
  bool _reading = false;

  /// Called while building the rail, the same way a community tile asks for
  /// its summary. Does nothing while a recent answer is still good.
  void load(CommunityShipsPort? port, String? target, String culture) {
    if (_closed) return;
    if (!identical(port, _port)) _bind(port);
    if (target != _target) {
      _forget();
      _target = target;
    }
    if (port == null || target == null || !port.shipsAvailable) {
      _forget();
      return;
    }
    final readAt = _readAt;
    if (_reading ||
        !_stale &&
            readAt != null &&
            !(_left && _now().difference(readAt) >= revisitAge)) {
      _left = false;
      return;
    }
    final epoch = ++_epoch;
    _reading = true;
    _stale = _left = false;
    unawaited(() async {
      try {
        final page = await Future.sync(
          () => port.readShips(
            target,
            query: CommunityShipQuery(culture: culture),
          ),
        );
        if (_closed || epoch != _epoch) return;
        if (page.targetRef != target) throw const FormatException();
        _count = page.totalCount;
        _failed = false;
      } catch (_) {
        if (_closed || epoch != _epoch) return;
        // An earlier count stays on screen; only an empty tile says it failed.
        _failed = true;
      }
      _reading = false;
      _readAt = _now();
      notifyListeners();
    }());
  }

  /// The page is hidden; the next [load] after it may count as a new visit.
  void left() => _left = true;

  void _bind(CommunityShipsPort? port) {
    unawaited(_invalidations?.cancel());
    unawaited(_refreshes?.cancel());
    _forget();
    _port = port;
    _invalidations = port?.invalidations.listen((_) {
      _forget();
      notifyListeners();
    });
    _refreshes = port is CommunityShipsRefreshPort
        ? (port as CommunityShipsRefreshPort).shipRefreshes.listen((_) {
            _stale = true;
            notifyListeners();
          })
        : null;
  }

  void _forget() {
    _epoch++;
    _count = null;
    _failed = _reading = _stale = _left = false;
    _readAt = null;
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    unawaited(_invalidations?.cancel());
    unawaited(_refreshes?.cancel());
    super.dispose();
  }
}
