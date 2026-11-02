import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_holo_workspace.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_screen_switch.dart';

/// Joined communities open on the holo shell's upper screen (2026-10-23).
/// Enter a section's lower screen the way a user does: through its rail
/// entry. Does nothing when the lower screen (or no shell) is already shown.
Future<void> enterCommunitySection(
  WidgetTester tester, [
  String section = 'members',
]) async {
  final entry = find.byKey(
    Key('official-fleet-tab-${communityHoloSections[section]!.name}'),
  );
  if (entry.evaluate().isEmpty) return;
  await tester.ensureVisible(entry.first);
  await tester.tap(entry.first);
  await tester.pump();
  await tester.pump(OfficialFleetScreenSwitch.duration);
  await tester.pump();
}
