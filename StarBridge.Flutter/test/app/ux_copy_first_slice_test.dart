import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';

void main() {
  test('reviewed fleet copy stays user-facing in every locale', () {
    const keys = [
      'officialFleet.error.hostUnavailable',
      'officialFleet.error.invalidResponse',
      'officialFleet.overview.error.contractUnavailable',
      'officialFleet.overview.announcement.body',
      'officialFleet.overview.body',
      'officialFleet.overview.snapshot.title',
      'officialFleet.overview.data.body',
      'officialFleet.data.members',
      'officialFleet.data.pending',
      'officialFleet.data.pending.starBridge',
      'officialFleet.data.pending.hybrid',
      'officialFleet.members.field.notConnected',
      'officialFleet.members.presence.notConnected',
      'officialFleet.section.members.title',
      'officialFleet.section.members.body',
      'officialFleet.members.error.contractUnavailable',
      'officialFleet.section.channel.title',
      'officialFleet.section.ships.title',
      'officialFleet.section.broadcasts.title',
      'officialFleet.profile.body',
      'officialFleet.profile.unavailable.title',
      'officialFleet.profile.unavailable.body',
      'officialFleet.ships.error.contractUnavailable',
      'officialFleet.ships.empty.body',
    ];
    final jargon = RegExp(r'Native Host|Flutter|WPF|Presence|contract|合同|合約|快照|snapshot|尚未接入|暂未开放|暫未開放|尚未開放');
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in keys) {
        expect(strings.text(key), isNot(key));
        expect(jargon.hasMatch(strings.text(key)), isFalse, reason: '$locale $key');
      }
    }
  });
}
