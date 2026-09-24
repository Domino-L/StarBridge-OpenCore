import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design_system/tokens/color_tokens.dart';
import 'app_preferences.dart';
import 'app_preferences_port.dart';
import 'app_preferences_projection.dart';
import 'app_preferences_store.dart';

final class AppPreferencesModule implements AppPreferencesPort {
  AppPreferencesModule({
    Iterable<Locale> systemLocales = const <Locale>[],
    Locale? accountLocale,
  }) : _systemLocales = List.unmodifiable(systemLocales),
       _accountLocale = accountLocale,
       _projection = ValueNotifier(
         AppPreferencesProjection(
           effective: AppPreferences.defaults.copyWith(
             locale: resolveLocale(
               localeOverride: null,
               accountLocale: accountLocale,
               systemLocales: systemLocales,
             ),
           ),
           confirmed: null,
           revision: null,
           phase: AppPreferencesPhase.unavailable,
           operation: AppPreferencesOperation.idle,
           source: null,
           failure: AppPreferencesFailure.hostUnavailable,
         ),
       );

  final List<Locale> _systemLocales;
  Locale? _accountLocale;
  final ValueNotifier<AppPreferencesProjection> _projection;
  AppPreferencesStore? _store;
  int _bindingRevision = 0;
  bool _disposed = false;

  @override
  ValueListenable<AppPreferencesProjection> get projection => _projection;

  Future<void> attachStore(AppPreferencesStore store) async {
    if (_disposed) {
      store.dispose();
      return;
    }
    final previous = _store;
    if (!identical(previous, store)) {
      previous?.dispose();
    }
    _store = store;
    final binding = ++_bindingRevision;
    await _read(store, binding, markLoading: true);
  }

  void detachStore() {
    if (_disposed) {
      return;
    }
    _bindingRevision++;
    final previous = _store;
    _store = null;
    previous?.dispose();
    final current = _projection.value;
    _projection.value = AppPreferencesProjection(
      effective: _effectiveFrom(current.confirmed) ?? current.effective,
      confirmed: current.confirmed,
      revision: current.revision,
      phase: AppPreferencesPhase.unavailable,
      operation: AppPreferencesOperation.idle,
      source: current.source,
      failure: AppPreferencesFailure.hostUnavailable,
    );
  }

  @override
  Future<bool> retry() async {
    final store = _store;
    if (_disposed || store == null) {
      return false;
    }
    final binding = ++_bindingRevision;
    return _read(store, binding, markLoading: true);
  }

  @override
  Future<bool> setLocale(Locale locale) =>
      _apply(AppPreferencesPatch.locale(locale));

  @override
  Future<bool> setAppearanceMode(AppearanceMode mode) =>
      _apply(AppPreferencesPatch.appearance(mode));

  @override
  Future<bool> setMotionPreference(MotionPreference preference) =>
      _apply(AppPreferencesPatch.motion(preference));

  @override
  Future<bool> setApplicationBehavior(
    ApplicationBehaviorPreferences behavior,
  ) => _apply(AppPreferencesPatch.applicationBehavior(behavior.normalize()));

  void updateAccountLocale(Locale? locale) {
    if (_disposed) {
      return;
    }
    _accountLocale = locale;
    final current = _projection.value;
    if (current.confirmed?.localeOverride != null) {
      return;
    }
    _projection.value = AppPreferencesProjection(
      effective: _effectiveFrom(current.confirmed) ?? current.effective,
      confirmed: current.confirmed,
      revision: current.revision,
      phase: current.phase,
      operation: current.operation,
      source: current.source,
      failure: current.failure,
    );
  }

  Future<bool> _read(
    AppPreferencesStore store,
    int binding, {
    required bool markLoading,
  }) async {
    final current = _projection.value;
    if (markLoading) {
      _projection.value = AppPreferencesProjection(
        effective: current.effective,
        confirmed: current.confirmed,
        revision: current.revision,
        phase: AppPreferencesPhase.loading,
        operation: AppPreferencesOperation.idle,
        source: current.source,
        failure: null,
      );
    }
    try {
      final result = await store.read();
      if (!_isCurrent(store, binding)) {
        return false;
      }
      _projection.value = AppPreferencesProjection(
        effective: _resolve(result.values),
        confirmed: result.values,
        revision: result.revision,
        phase: AppPreferencesPhase.ready,
        operation: AppPreferencesOperation.idle,
        source: result.source,
        failure: result.source == AppPreferencesSource.recoveredDefaults
            ? AppPreferencesFailure.recoveredDefaults
            : null,
      );
      return true;
    } on AppPreferencesStoreException catch (error) {
      if (!_isCurrent(store, binding)) {
        return false;
      }
      _setUnavailable(error.failure);
      return false;
    } on Object {
      if (!_isCurrent(store, binding)) {
        return false;
      }
      _setUnavailable(AppPreferencesFailure.invalidResponse);
      return false;
    }
  }

  Future<bool> _apply(AppPreferencesPatch patch) async {
    final store = _store;
    final current = _projection.value;
    if (_disposed || store == null || !current.canEdit || patch.isEmpty) {
      return false;
    }
    final confirmed = current.confirmed!;
    final revision = current.revision!;
    final binding = _bindingRevision;
    final optimistic = confirmed.apply(patch);
    _projection.value = AppPreferencesProjection(
      effective: _resolve(optimistic),
      confirmed: confirmed,
      revision: revision,
      phase: AppPreferencesPhase.ready,
      operation: AppPreferencesOperation.saving,
      source: current.source,
      failure: null,
    );
    try {
      final result = await store.update(patch, expectedRevision: revision);
      if (!_isCurrent(store, binding)) {
        return false;
      }
      _projection.value = AppPreferencesProjection(
        effective: _resolve(result.values),
        confirmed: result.values,
        revision: result.revision,
        phase: AppPreferencesPhase.ready,
        operation: AppPreferencesOperation.idle,
        source: result.source,
        failure: null,
      );
      return true;
    } on AppPreferencesStoreException catch (error) {
      if (!_isCurrent(store, binding)) {
        return false;
      }
      if (error.failure == AppPreferencesFailure.revisionConflict) {
        await _read(store, binding, markLoading: false);
        if (_isCurrent(store, binding)) {
          final reconciled = _projection.value;
          _projection.value = AppPreferencesProjection(
            effective: reconciled.effective,
            confirmed: reconciled.confirmed,
            revision: reconciled.revision,
            phase: reconciled.phase,
            operation: AppPreferencesOperation.idle,
            source: reconciled.source,
            failure: AppPreferencesFailure.revisionConflict,
          );
        }
        return false;
      }
      _rollback(confirmed, revision, current.source, error.failure);
      return false;
    } on Object {
      if (_isCurrent(store, binding)) {
        _rollback(
          confirmed,
          revision,
          current.source,
          AppPreferencesFailure.invalidResponse,
        );
      }
      return false;
    }
  }

  void _rollback(
    StoredAppPreferences confirmed,
    int revision,
    AppPreferencesSource? source,
    AppPreferencesFailure failure,
  ) {
    _projection.value = AppPreferencesProjection(
      effective: _resolve(confirmed),
      confirmed: confirmed,
      revision: revision,
      phase: AppPreferencesPhase.ready,
      operation: AppPreferencesOperation.idle,
      source: source,
      failure: failure,
    );
  }

  void _setUnavailable(AppPreferencesFailure failure) {
    final current = _projection.value;
    _projection.value = AppPreferencesProjection(
      effective: _effectiveFrom(current.confirmed) ?? current.effective,
      confirmed: current.confirmed,
      revision: current.revision,
      phase: AppPreferencesPhase.unavailable,
      operation: AppPreferencesOperation.idle,
      source: current.source,
      failure: failure,
    );
  }

  bool _isCurrent(AppPreferencesStore store, int binding) =>
      !_disposed && identical(_store, store) && _bindingRevision == binding;

  AppPreferences? _effectiveFrom(StoredAppPreferences? values) =>
      values == null ? null : _resolve(values);

  AppPreferences _resolve(StoredAppPreferences values) => AppPreferences(
    locale: resolveLocale(
      localeOverride: values.localeOverride,
      accountLocale: _accountLocale,
      systemLocales: _systemLocales,
    ),
    appearanceMode: values.appearanceMode,
    designStyleId: AppPreferences.defaults.designStyleId,
    motionPreference: values.motionPreference,
    applicationBehavior: values.applicationBehavior,
  );

  static Locale resolveLocale({
    required Locale? localeOverride,
    required Locale? accountLocale,
    required Iterable<Locale> systemLocales,
  }) {
    final override = normalizeSupportedLocale(localeOverride);
    if (override != null) {
      return override;
    }
    final account = normalizeSupportedLocale(accountLocale);
    if (account != null) {
      return account;
    }
    for (final locale in systemLocales) {
      final normalized = normalizeSupportedLocale(locale);
      if (normalized != null) {
        return normalized;
      }
    }
    return const Locale('en', 'US');
  }

  static Locale? normalizeSupportedLocale(Locale? locale) {
    if (locale == null) {
      return null;
    }
    if (locale.languageCode == 'en') {
      return const Locale('en', 'US');
    }
    if (locale.languageCode != 'zh') {
      return null;
    }
    final traditional =
        locale.scriptCode == 'Hant' ||
        locale.countryCode == 'TW' ||
        locale.countryCode == 'HK' ||
        locale.countryCode == 'MO';
    return traditional ? const Locale('zh', 'TW') : const Locale('zh', 'CN');
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _bindingRevision++;
    _store?.dispose();
    _store = null;
    _projection.dispose();
  }
}
