import 'dart:async';

import 'package:flutter/foundation.dart';

const localEventCategories = [
  'all',
  'session',
  'identity',
  'server',
  'ship',
  'location',
  'life',
  'other',
];

final class LocalHistoryEntry {
  const LocalHistoryEntry({
    required this.id,
    required this.at,
    required this.category,
    required this.eventType,
    required this.title,
    required this.detail,
  });
  final String id, category, eventType, title, detail;
  final DateTime at;
}

final class LocalHistoryPage {
  const LocalHistoryPage({
    required this.state,
    required this.totalCount,
    required this.filteredCount,
    required this.offset,
    required this.pageSize,
    required this.hasMore,
    required this.entries,
    this.revision,
  });
  final String state;
  final int totalCount, filteredCount, offset, pageSize;
  final bool hasMore;
  final String? revision;
  final List<LocalHistoryEntry> entries;
}

abstract interface class LocalHistoryPort {
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  });
}

final class LocalHistoryUnavailable implements LocalHistoryPort {
  const LocalHistoryUnavailable();
  @override
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async => throw const LocalHistoryException('unavailable');
}

final class LocalHistoryException implements Exception {
  const LocalHistoryException(this.code);
  final String code;
}

final class LocalHistoryView {
  const LocalHistoryView({
    this.category = 'all',
    this.busy = false,
    this.page,
    this.failure,
    this.changed = false,
    this.hasUpdates = false,
  });
  final String category;
  final bool busy, changed;
  final bool hasUpdates;
  final LocalHistoryPage? page;
  final String? failure;
}

final class LocalHistoryController extends ValueNotifier<LocalHistoryView> {
  LocalHistoryController(
    this.port, {
    this.timeout = const Duration(seconds: 15),
  }) : super(const LocalHistoryView());
  final LocalHistoryPort port;
  final Duration timeout;
  bool _disposed = false;
  bool _checking = false;
  int _epoch = 0;
  Timer? _poll;
  void startWatching() {
    _poll ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => checkForUpdates(),
    );
  }

  Future<void> checkForUpdates() async {
    final current = value;
    if (_disposed ||
        _checking ||
        current.busy ||
        current.page?.revision == null ||
        current.hasUpdates) {
      return;
    }
    _checking = true;
    final epoch = _epoch;
    try {
      final latest = await port
          .read(category: current.category, offset: 0, pageSize: 50)
          .timeout(timeout);
      if (!_disposed &&
          epoch == _epoch &&
          latest.revision != current.page!.revision) {
        value = LocalHistoryView(
          category: current.category,
          page: current.page,
          hasUpdates: true,
        );
      }
    } on Object {
      // Background reads never erase the user's currently visible history.
    } finally {
      _checking = false;
    }
  }

  Future<void> refresh() => _load(value.category, 0, null);
  Future<void> select(String category) {
    if (!localEventCategories.contains(category)) return Future.value();
    return _load(category, 0, null);
  }

  Future<void> next() {
    final p = value.page;
    return p == null || !p.hasMore
        ? Future.value()
        : _load(value.category, p.offset + p.pageSize, p.revision);
  }

  Future<void> previous() {
    final p = value.page;
    return p == null || p.offset == 0
        ? Future.value()
        : _load(
            value.category,
            (p.offset - p.pageSize).clamp(0, 3000),
            p.revision,
          );
  }

  Future<void> _load(String category, int offset, String? revision) async {
    if (_disposed || value.busy) return;
    _epoch++;
    final previous = value.category == category ? value.page : null;
    value = LocalHistoryView(category: category, busy: true, page: previous);
    try {
      LocalHistoryPage page;
      var changed = false;
      try {
        page = await port
            .read(
              category: category,
              offset: offset,
              pageSize: 50,
              revision: revision,
            )
            .timeout(timeout);
      } on LocalHistoryException catch (error) {
        if (error.code != 'changed' || revision == null || _disposed) rethrow;
        changed = true;
        // A changed history restarts at page one once, never concatenates revisions.
        page = await port
            .read(category: category, offset: 0, pageSize: 50)
            .timeout(timeout);
      }
      if (!_disposed) {
        value = LocalHistoryView(
          category: category,
          page: page,
          changed: changed,
        );
      }
    } on Object {
      if (!_disposed) {
        value = LocalHistoryView(
          category: category,
          page: previous,
          failure: 'readFailed',
        );
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
