import 'package:flutter/foundation.dart';

import 'app_preferences.dart';
import 'app_preferences_store.dart';

enum AppPreferencesPhase { loading, ready, unavailable }

enum AppPreferencesOperation { idle, saving }

@immutable
final class AppPreferencesProjection {
  const AppPreferencesProjection({
    required this.effective,
    required this.confirmed,
    required this.revision,
    required this.phase,
    required this.operation,
    required this.source,
    required this.failure,
  });

  final AppPreferences effective;
  final StoredAppPreferences? confirmed;
  final int? revision;
  final AppPreferencesPhase phase;
  final AppPreferencesOperation operation;
  final AppPreferencesSource? source;
  final AppPreferencesFailure? failure;

  bool get canEdit =>
      phase == AppPreferencesPhase.ready &&
      operation == AppPreferencesOperation.idle &&
      confirmed != null &&
      revision != null;

  bool get isInitialLoading =>
      phase == AppPreferencesPhase.loading && confirmed == null;
}
