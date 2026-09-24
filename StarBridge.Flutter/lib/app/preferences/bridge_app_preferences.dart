import 'package:flutter/widgets.dart';

import '../../design_system/tokens/color_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'app_preferences.dart';
import 'app_preferences_store.dart';

final class BridgeAppPreferencesStore implements AppPreferencesStore {
  BridgeAppPreferencesStore(this._session);

  final BridgeClientSession _session;

  @override
  Future<AppPreferencesReadResult> read() async {
    try {
      final response = await _session.request(
        'applicationPreferences.get',
        payload: const {'schemaVersion': 1},
      );
      return _parse(response.payload);
    } on Object catch (error) {
      throw _mapError(error, writing: false);
    }
  }

  @override
  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch patch, {
    required int expectedRevision,
  }) async {
    if (patch.isEmpty) {
      throw const AppPreferencesStoreException(
        AppPreferencesFailure.invalidValue,
      );
    }
    final payloadPatch = <String, Object?>{
      if (patch.includesLocaleOverride)
        'localeOverride': patch.localeOverride == null
            ? null
            : _localeTag(patch.localeOverride!),
      if (patch.appearanceMode != null)
        'appearanceMode': patch.appearanceMode!.name,
      if (patch.motionPreference != null)
        'motionPreference': patch.motionPreference!.name,
      if (patch.applicationBehavior != null)
        'applicationBehavior': {
          'launchAtStartup': patch.applicationBehavior!.launchAtStartup,
          'keepRunningInBackground':
              patch.applicationBehavior!.keepRunningInBackground,
          'startMinimized': patch.applicationBehavior!.startMinimized,
          'startupChoiceMade': patch.applicationBehavior!.startupChoiceMade,
          'closeBehaviorChoiceMade':
              patch.applicationBehavior!.closeBehaviorChoiceMade,
          'backgroundHintShown': patch.applicationBehavior!.backgroundHintShown,
        },
    };
    try {
      final response = await _session.request(
        'applicationPreferences.update',
        payload: {
          'schemaVersion': 1,
          'expectedRevision': expectedRevision,
          'patch': payloadPatch,
        },
      );
      return _parse(response.payload);
    } on Object catch (error) {
      throw _mapError(error, writing: true);
    }
  }

  static AppPreferencesReadResult _parse(Map<String, Object?> payload) {
    if (payload['schemaVersion'] != 1) {
      throw const BridgeFormatException(
        'Application preferences schema version is incompatible.',
      );
    }
    final revision = payload['revision'];
    if (revision is! int || revision < 0) {
      throw const BridgeFormatException(
        'Application preferences revision is invalid.',
      );
    }
    final source = switch (_requiredString(payload, 'storageState')) {
      'ready' => AppPreferencesSource.stored,
      'defaulted' => AppPreferencesSource.defaults,
      'recoveredDefaults' => AppPreferencesSource.recoveredDefaults,
      _ => throw const BridgeFormatException(
        'Application preferences storage state is unsupported.',
      ),
    };
    final preferences = payload['preferences'];
    if (preferences is! Map) {
      throw const BridgeFormatException(
        'Application preferences payload is missing preferences.',
      );
    }
    final values = preferences.cast<String, Object?>();
    final localeValue = values['localeOverride'];
    final locale = switch (localeValue) {
      null => null,
      'zh-CN' => const Locale('zh', 'CN'),
      'zh-TW' => const Locale('zh', 'TW'),
      'en-US' => const Locale('en', 'US'),
      _ => throw const BridgeFormatException(
        'Application preferences locale override is unsupported.',
      ),
    };
    final appearance = switch (_requiredString(values, 'appearanceMode')) {
      'dark' => AppearanceMode.dark,
      'light' => AppearanceMode.light,
      _ => throw const BridgeFormatException(
        'Application preferences appearance is unsupported.',
      ),
    };
    final motion = switch (_requiredString(values, 'motionPreference')) {
      'followSystem' => MotionPreference.followSystem,
      'reduce' => MotionPreference.reduce,
      _ => throw const BridgeFormatException(
        'Application preferences motion preference is unsupported.',
      ),
    };
    final behaviorValue = values['applicationBehavior'];
    if (behaviorValue != null && behaviorValue is! Map) {
      throw const BridgeFormatException(
        'Application preferences application behavior is invalid.',
      );
    }
    final applicationBehavior = behaviorValue == null
        ? ApplicationBehaviorPreferences.defaults
        : _parseApplicationBehavior(
            (behaviorValue as Map).cast<String, Object?>(),
          );
    return AppPreferencesReadResult(
      values: StoredAppPreferences(
        localeOverride: locale,
        appearanceMode: appearance,
        motionPreference: motion,
        applicationBehavior: applicationBehavior,
      ),
      revision: revision,
      source: source,
    );
  }

  static AppPreferencesStoreException _mapError(
    Object error, {
    required bool writing,
  }) {
    if (error is BridgeTimeoutException) {
      return AppPreferencesStoreException(
        writing
            ? AppPreferencesFailure.outcomeUncertain
            : AppPreferencesFailure.timeout,
        retryable: true,
        outcomeUncertain: writing,
      );
    }
    if (error is BridgeDisconnectedException ||
        error is BridgeStaleGenerationException) {
      return AppPreferencesStoreException(
        writing
            ? AppPreferencesFailure.outcomeUncertain
            : AppPreferencesFailure.hostUnavailable,
        retryable: true,
        outcomeUncertain: writing,
      );
    }
    if (error is BridgeFormatException) {
      return const AppPreferencesStoreException(
        AppPreferencesFailure.invalidResponse,
      );
    }
    if (error is BridgeClientException) {
      final failure = switch (error.code) {
        'applicationPreferences.invalid_value' =>
          AppPreferencesFailure.invalidValue,
        'applicationPreferences.read_failed' =>
          AppPreferencesFailure.readFailed,
        'applicationPreferences.save_failed' =>
          AppPreferencesFailure.saveFailed,
        'applicationPreferences.revision_conflict' =>
          AppPreferencesFailure.revisionConflict,
        'applicationPreferences.startup_registration_failed' =>
          AppPreferencesFailure.startupRegistrationFailed,
        'bridge.invalid_envelope' ||
        'bridge.protocol_incompatible' => AppPreferencesFailure.invalidResponse,
        _ =>
          writing
              ? AppPreferencesFailure.saveFailed
              : AppPreferencesFailure.readFailed,
      };
      return AppPreferencesStoreException(failure, retryable: error.retryable);
    }
    return AppPreferencesStoreException(
      writing
          ? AppPreferencesFailure.saveFailed
          : AppPreferencesFailure.invalidResponse,
    );
  }

  static String _localeTag(Locale locale) {
    if (locale.languageCode == 'en') {
      return 'en-US';
    }
    if (locale.languageCode != 'zh') {
      throw const AppPreferencesStoreException(
        AppPreferencesFailure.invalidValue,
      );
    }
    if (locale.countryCode == 'TW' ||
        locale.countryCode == 'HK' ||
        locale.countryCode == 'MO' ||
        locale.scriptCode == 'Hant') {
      return 'zh-TW';
    }
    return 'zh-CN';
  }

  static String _requiredString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String || value.trim().isEmpty) {
      throw BridgeFormatException('$key must be a non-empty string.');
    }
    return value.trim();
  }

  static bool _requiredBool(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! bool) {
      throw BridgeFormatException('$key must be a boolean.');
    }
    return value;
  }

  static ApplicationBehaviorPreferences _parseApplicationBehavior(
    Map<String, Object?> behavior,
  ) => ApplicationBehaviorPreferences(
    launchAtStartup: _requiredBool(behavior, 'launchAtStartup'),
    keepRunningInBackground: _requiredBool(behavior, 'keepRunningInBackground'),
    startMinimized: _requiredBool(behavior, 'startMinimized'),
    startupChoiceMade: behavior['startupChoiceMade'] == null
        ? false
        : _requiredBool(behavior, 'startupChoiceMade'),
    closeBehaviorChoiceMade: _requiredBool(behavior, 'closeBehaviorChoiceMade'),
    backgroundHintShown: _requiredBool(behavior, 'backgroundHintShown'),
  ).normalize();

  @override
  void dispose() {}
}
