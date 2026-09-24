import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

void main() {
  test(
    'resolves locale by device override, account, system, then English',
    () async {
      final module = AppPreferencesModule(
        accountLocale: const Locale('zh', 'TW'),
        systemLocales: const [Locale('zh', 'CN')],
      );
      addTearDown(module.dispose);
      final store = _ScriptedStore(
        readResult: _result(locale: null, revision: 0),
      );

      await module.attachStore(store);
      expect(
        module.projection.value.effective.locale,
        const Locale('zh', 'TW'),
      );

      await module.setLocale(const Locale('en', 'US'));
      expect(
        module.projection.value.effective.locale,
        const Locale('en', 'US'),
      );
    },
  );

  test('projects a choice immediately and confirms it after saving', () async {
    final save = Completer<AppPreferencesReadResult>();
    final module = AppPreferencesModule(
      systemLocales: const [Locale('zh', 'CN')],
    );
    addTearDown(module.dispose);
    final store = _ScriptedStore(
      readResult: _result(locale: const Locale('zh', 'CN'), revision: 0),
      onUpdate: (_, _) => save.future,
    );
    await module.attachStore(store);

    final pending = module.setAppearanceMode(AppearanceMode.light);
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.operation, AppPreferencesOperation.saving);
    expect(
      module.projection.value.effective.appearanceMode,
      AppearanceMode.light,
    );

    save.complete(
      _result(
        locale: const Locale('zh', 'CN'),
        appearance: AppearanceMode.light,
        revision: 1,
        source: AppPreferencesSource.stored,
      ),
    );
    expect(await pending, isTrue);
    expect(module.projection.value.revision, 1);
    expect(module.projection.value.canEdit, isTrue);
  });

  test('rolls back to the last confirmed value after a save failure', () async {
    final module = AppPreferencesModule(
      systemLocales: const [Locale('zh', 'CN')],
    );
    addTearDown(module.dispose);
    final store = _ScriptedStore(
      readResult: _result(locale: const Locale('zh', 'CN'), revision: 4),
      onUpdate: (_, _) async => throw const AppPreferencesStoreException(
        AppPreferencesFailure.saveFailed,
        retryable: true,
      ),
    );
    await module.attachStore(store);

    expect(await module.setAppearanceMode(AppearanceMode.light), isFalse);
    final projection = module.projection.value;
    expect(projection.effective.appearanceMode, AppearanceMode.dark);
    expect(projection.failure, AppPreferencesFailure.saveFailed);
    expect(projection.revision, 4);
  });

  test(
    'disconnect keeps the last confirmed settings and disables writes',
    () async {
      final module = AppPreferencesModule(
        systemLocales: const [Locale('en', 'US')],
      );
      addTearDown(module.dispose);
      final store = _ScriptedStore(
        readResult: _result(
          locale: const Locale('zh', 'TW'),
          appearance: AppearanceMode.light,
          revision: 3,
          source: AppPreferencesSource.stored,
        ),
      );
      await module.attachStore(store);

      module.detachStore();

      final projection = module.projection.value;
      expect(projection.phase, AppPreferencesPhase.unavailable);
      expect(projection.effective.locale, const Locale('zh', 'TW'));
      expect(projection.effective.appearanceMode, AppearanceMode.light);
      expect(projection.canEdit, isFalse);
      expect(store.disposed, isTrue);
    },
  );

  test(
    'a late read from an old Host binding cannot overwrite a new one',
    () async {
      final oldRead = Completer<AppPreferencesReadResult>();
      final module = AppPreferencesModule(
        systemLocales: const [Locale('en', 'US')],
      );
      addTearDown(module.dispose);
      final oldStore = _ScriptedStore(read: () => oldRead.future);
      final newStore = _ScriptedStore(
        readResult: _result(
          locale: const Locale('zh', 'TW'),
          revision: 8,
          source: AppPreferencesSource.stored,
        ),
      );

      final oldAttach = module.attachStore(oldStore);
      await Future<void>.delayed(Duration.zero);
      await module.attachStore(newStore);
      oldRead.complete(
        _result(
          locale: const Locale('zh', 'CN'),
          revision: 2,
          source: AppPreferencesSource.stored,
        ),
      );
      await oldAttach;

      expect(
        module.projection.value.effective.locale,
        const Locale('zh', 'TW'),
      );
      expect(module.projection.value.revision, 8);
    },
  );

  test(
    'corrupt settings recovery remains visible while controls stay usable',
    () async {
      final module = AppPreferencesModule(
        systemLocales: const [Locale('en', 'US')],
      );
      addTearDown(module.dispose);
      await module.attachStore(
        _ScriptedStore(
          readResult: _result(
            locale: null,
            revision: 0,
            source: AppPreferencesSource.recoveredDefaults,
          ),
        ),
      );

      final projection = module.projection.value;
      expect(projection.failure, AppPreferencesFailure.recoveredDefaults);
      expect(projection.canEdit, isTrue);
    },
  );
}

AppPreferencesReadResult _result({
  required Locale? locale,
  AppearanceMode appearance = AppearanceMode.dark,
  MotionPreference motion = MotionPreference.followSystem,
  required int revision,
  AppPreferencesSource source = AppPreferencesSource.defaults,
}) {
  return AppPreferencesReadResult(
    values: StoredAppPreferences(
      localeOverride: locale,
      appearanceMode: appearance,
      motionPreference: motion,
    ),
    revision: revision,
    source: source,
  );
}

typedef _Update = Future<AppPreferencesReadResult> Function(
  AppPreferencesPatch patch,
  int expectedRevision,
);

final class _ScriptedStore implements AppPreferencesStore {
  _ScriptedStore({
    AppPreferencesReadResult? readResult,
    Future<AppPreferencesReadResult> Function()? read,
    this.onUpdate,
  }) : _current = readResult,
       _read = read ?? (() async => readResult!);

  AppPreferencesReadResult? _current;
  final Future<AppPreferencesReadResult> Function() _read;
  final _Update? onUpdate;
  bool disposed = false;

  @override
  Future<AppPreferencesReadResult> read() => _read();

  @override
  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch patch, {
    required int expectedRevision,
  }) {
    final handler = onUpdate;
    if (handler != null) {
      return handler(patch, expectedRevision);
    }
    final current = _current;
    if (current == null) {
      throw StateError('A scripted update is required for this store.');
    }
    final result = AppPreferencesReadResult(
      values: current.values.apply(patch),
      revision: expectedRevision + 1,
      source: AppPreferencesSource.stored,
    );
    _current = result;
    return Future.value(result);
  }

  @override
  void dispose() {
    disposed = true;
  }
}
