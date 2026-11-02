import 'dart:async';

import 'marketplace_port.dart';

/// The Host answers a hall page within two seconds, with the categories it has
/// by then, and marks the rows it has no answer for yet. Those are read again a
/// few times, quietly: no loading state, and only their categories change.
final class MarketCategoryRecheck {
  MarketCategoryRecheck({required this.current, required this.store});
  final MarketRead? Function(String key) current;
  final void Function(String key, MarketRead read) store;

  static const _delays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];
  final _timers = <String, Timer>{};
  final _runs = <String, int>{};
  int _lastRun = 0;

  /// Starts over for [key]; a new read of the page replaces the old round.
  void track(String key, MarketRead read, Future<MarketRead> Function() reread) {
    final run = ++_lastRun;
    _runs[key] = run;
    _timers.remove(key)?.cancel();
    if (read.rows.any(_waiting)) _schedule(key, run, 0, reread);
  }

  void cancel() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _runs.clear();
  }

  static bool _waiting(MarketRow row) => row['categoryPending'] == true;
  static Object? _identity(MarketRow row) => row['orderNumber'] ?? row['id'];

  void _schedule(
    String key,
    int run,
    int round,
    Future<MarketRead> Function() reread,
  ) {
    _timers[key] = Timer(_delays[round], () async {
      _timers.remove(key);
      MarketRead? next;
      try {
        next = await reread();
      } on Object {
        /* Optional: the next round asks again, the last one gives up. */
      }
      final live = current(key);
      if (_runs[key] != run || live == null) return;
      final answers = {for (final row in next?.rows ?? const []) _identity(row): row};
      final last = round + 1 >= _delays.length;
      var changed = false;
      final rows = [
        for (final row in live.rows)
          if (!_waiting(row))
            row
          else
            () {
              final answer = next == null ? null : answers[_identity(row)];
              final settled = last || (answer != null && !_waiting(answer));
              if (!settled) return row;
              changed = true;
              return {
                ...row..remove('categoryPending'),
                if (answer?['categoryId'] case final Object category)
                  'categoryId': category,
              };
            }(),
      ];
      if (changed) {
        store(key, MarketRead({...live.data, 'rows': rows}, live.readAt));
      }
      if (!last && rows.any(_waiting)) _schedule(key, run, round + 1, reread);
    });
  }
}
