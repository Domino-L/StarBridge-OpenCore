import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_read_failure.dart';
import 'package:starbridge_flutter/app/localization/official_fleet_strings.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

void main() {
  test('all three locales explain the condition and Windows recovery', () {
    for (final strings in [
      simplifiedOfficialFleetStrings,
      traditionalOfficialFleetStrings,
      englishOfficialFleetStrings,
    ]) {
      final message = strings['officialFleet.error.clockSkew']!;
      expect(message, contains('Windows'));
      expect(
        message,
        isNot(strings['officialFleet.members.error.unavailable']),
      );
    }
  });
  test('only confirmed clock skew selects the Windows time guidance', () {
    for (final members in [false, true]) {
      expect(
        fleetReadFailureKey(
          const BridgeClientException('official_fleet.identity_clock_skew'),
          members: members,
        ),
        'officialFleet.error.clockSkew',
      );
      for (final code in [
        'official_fleet.identity_time_invalid',
        'official_fleet.data_invalid',
        'official_fleet.identity_unavailable',
        'official_fleet.read_transient',
      ]) {
        expect(
          fleetReadFailureKey(BridgeClientException(code), members: members),
          isNot('officialFleet.error.clockSkew'),
        );
      }
    }
    expect(
      fleetReadIsTransient(
        const BridgeClientException('official_fleet.identity_clock_skew'),
      ),
      isFalse,
    );
  });
}
