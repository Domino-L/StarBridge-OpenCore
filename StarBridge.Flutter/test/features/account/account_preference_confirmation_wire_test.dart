import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';

import 'account_profile_cache_wire_test.dart' show AccountProfileWireHost;

void main() {
  const path = String.fromEnvironment(
    'STARBRIDGE_PREFERENCE_CONFIRMATION_WIRE',
  );
  test(
    'actual Native confirmation keeps prepared options and shows saved without refresh',
    () async {
      final host = await AccountProfileWireHost.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      final prepared = module.projection.value.timeZoneOptions;
      expect(prepared, isNotEmpty);
      expect(module.projection.value.canEditPreferences, isTrue);
      host.names.clear();
      final result = await module.savePreferences(
        locale: 'en-US',
        timeZone: 'UTC',
      );
      expect(result.outcome, AccountActionOutcome.completed);
      final saved = module.projection.value;
      expect(saved.profile?.locale, 'en-US');
      expect(saved.profileFreshness, AccountProfileFreshness.live);
      expect(
        saved.timeZoneOptions.map((zone) => zone.value),
        prepared.map((zone) => zone.value),
      );
      expect(saved.canEditPreferences, isTrue);
      expect(saved.notice?.messageKey, 'account.preferences.saved');
      expect(saved.failure, isNull);
      expect(host.names, ['profile.patchPreferences']);
      expect(host.fixture['counts'], {
        'patches': 1,
        'authorizations': 1,
        'directoryReadsAfterPreparation': 0,
      });
    },
    skip: path.isEmpty
        ? 'Requires actual Native preference confirmation fixture.'
        : false,
  );
}
