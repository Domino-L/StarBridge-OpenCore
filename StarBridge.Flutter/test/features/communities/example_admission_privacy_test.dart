import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/example_admission_privacy.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';

void main() {
  LocalPrivacySettings settings() => LocalPrivacySettings(
    publicationEnabled: false,
    fleetFields: 0,
    fleetAdministratorsCanView: false,
    fleetAllMembersCanView: false,
    fleetVisibilityGroupIds: const [],
    roomFields: 0,
    roomAllMembersCanView: false,
  );

  test('leases share only their owning example session', () async {
    final session = ExampleAdmissionPrivacy();
    final first = session.open(), second = session.open();
    final unrelated = ExampleAdmissionPrivacy().open();
    final value = settings();
    expect((await first.save(value)).revision, 1);
    expect((await second.read()).settings, same(value));
    expect((await second.save(value)).revision, 2);
    expect((await unrelated.read()).revision, 0);
    expect((await unrelated.read()).settings, isNull);
    await first.close();
    await second.close();
    await unrelated.close();
  });

  test(
    'closing one lease does not close the session or another lease',
    () async {
      final session = ExampleAdmissionPrivacy();
      final first = session.open(), second = session.open();
      await first.close();
      await expectLater(first.read(), throwsStateError);
      await expectLater(first.save(settings()), throwsStateError);
      expect((await second.save(settings())).revision, 1);
      await second.close();
    },
  );

  test('session reset clears values for existing and future leases', () async {
    final session = ExampleAdmissionPrivacy();
    final lease = session.open();
    await lease.save(settings());
    session.reset();
    expect((await lease.read()).revision, 0);
    expect((await lease.read()).settings, isNull);
    final next = session.open();
    expect((await next.read()).settings, isNull);
    await lease.close();
    await next.close();
  });
}
