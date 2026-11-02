import 'dart:async';

import 'package:flutter/foundation.dart';

import 'marketplace_port.dart';
import 'marketplace_price_format.dart' show marketPriceFormats;

/// The hall's saved preferences (favourites, history, price format, view).
/// Writes are queued so each one builds on the last answered revision.
mixin MarketplacePreferences on ChangeNotifier {
  MarketplacePort get port;
  int get contextRevision;
  @protected
  bool get isDisposed;
  Future<void> loadFavorites();

  /// Applies the remembered view once per account (see readPreferences).
  @protected
  void restoreView(Map<Object?, Object?> raw);

  static const MarketRow _empty = {
    'revision': 0,
    'favorites': <int>[],
    'recentItems': <int>[],
    'recentSearches': <String>[],
  };
  MarketRow _preferences = _empty;
  bool preferencesFailed = false, savingPreferences = false;
  bool favoriteLimitReached = false;
  bool _viewRestored = false;
  Future<void> _preferenceQueue = Future.value();
  List<int> get favorites =>
      (_preferences['favorites'] as List? ?? const []).cast<int>();
  List<String> get recentSearches =>
      (_preferences['recentSearches'] as List? ?? const []).cast<String>();
  List<int> get recentItems =>
      (_preferences['recentItems'] as List? ?? const []).cast<int>();

  /// What each favourite looked like when followed (watch tab, G3).
  List<MarketRow> get watchedSnapshots => [
    for (final row in _preferences['watched'] as List? ?? const [])
      if (row is Map) row.cast<String, Object?>(),
  ];

  /// Snapshot of an item right now, taken when it is followed.
  MarketRow currentWatchSnapshot(int id);

  @protected
  Future<void> saveWatchSnapshots(List<MarketRow> snapshots) =>
      savePreference('watched', snapshots);
  String get priceFormat {
    final value = _preferences['priceFormat'];
    return value is String && marketPriceFormats.contains(value)
        ? value
        : 'auto';
  }

  Future<void> setPriceFormat(String value) {
    if (!marketPriceFormats.contains(value) || value == priceFormat) {
      return Future.value();
    }
    return savePreference('priceFormat', value);
  }

  /// Saves one top-level preference on top of the latest answered revision.
  @protected
  Future<void> savePreference(String key, Object? value) =>
      _save(() => {..._preferences, key: value});

  Future<void> readPreferences() async {
    final context = contextRevision;
    try {
      final result = await port.preferences();
      if (isDisposed || context != contextRevision) return;
      _preferences = result;
      preferencesFailed = false;
      if (!_viewRestored) {
        _viewRestored = true;
        final raw = result['view'];
        if (raw is Map) restoreView(raw);
      }
    } on Object {
      if (!isDisposed && context == contextRevision) preferencesFailed = true;
    }
    if (!isDisposed && context == contextRevision) notifyListeners();
  }

  Future<void> _save(MarketRow Function() update) {
    final context = contextRevision;
    final next = _preferenceQueue.then((_) async {
      if (isDisposed || context != contextRevision || preferencesFailed) {
        return;
      }
      savingPreferences = true;
      notifyListeners();
      try {
        final result = await port.preferences(update());
        if (!isDisposed && context == contextRevision) {
          _preferences = result;
          preferencesFailed = false;
        }
      } on Object {
        if (!isDisposed && context == contextRevision) preferencesFailed = true;
      } finally {
        if (!isDisposed && context == contextRevision) {
          savingPreferences = false;
          notifyListeners();
        }
      }
    });
    _preferenceQueue = next;
    return next;
  }

  Future<void> clearHistory(bool items) => _save(
    () => {
      ..._preferences,
      items ? 'recentItems' : 'recentSearches': items ? <int>[] : <String>[],
    },
  );
  Future<void> rememberSearch(String query) => _save(
    () => {
      ..._preferences,
      'recentSearches': [
        if (query.trim().isNotEmpty) query.trim(),
        ...recentSearches.where((s) => s != query.trim()),
      ].take(20).toList(),
    },
  );
  Future<void> remember(int id, String? query) async {
    await _save(
      () => {
        ..._preferences,
        'recentItems': [
          id,
          ...recentItems.where((v) => v != id),
        ].take(20).toList(),
        'recentSearches': [
          if (query != null && query.trim().isNotEmpty) query.trim(),
          ...recentSearches.where((v) => v != query?.trim()),
        ].take(20).toList(),
      },
    );
  }

  /// Follows or unfollows. Following records what the item looks like now
  /// ([snapshot], for undo the one it had); unfollowing forgets it.
  Future<void> toggleFavorite(int id, {MarketRow? snapshot}) async {
    favoriteLimitReached = false;
    if (!favorites.contains(id) && favorites.length >= 100) {
      favoriteLimitReached = true;
      notifyListeners();
      return;
    }
    final following = !favorites.contains(id);
    final taken = following ? snapshot ?? currentWatchSnapshot(id) : null;
    await _save(() {
      final kept = [
        for (final row in watchedSnapshots)
          if (marketNumber(row['id'])?.toInt() != id) row,
      ];
      final next = following
          ? [id, ...favorites].take(100).toList()
          : favorites.where((v) => v != id).toList();
      return {
        ..._preferences,
        'favorites': next,
        'watched': [
          ?taken,
          ...kept.where((row) => next.contains(marketNumber(row['id'])?.toInt())),
        ],
      };
    });
    if (!isDisposed) await loadFavorites();
  }

  /// A new account starts from empty preferences and restores its own view.
  @protected
  void resetPreferences() {
    _viewRestored = false;
    _preferences = _empty;
    preferencesFailed = false;
    savingPreferences = false;
    favoriteLimitReached = false;
  }
}
