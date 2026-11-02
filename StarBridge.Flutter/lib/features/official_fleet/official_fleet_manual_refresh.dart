import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'official_fleet_first_sharing_choice.dart';
import 'official_fleet_module.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// The fleet page's refresh button (user report 2026-10-29: "点刷新没反应").
/// Rereads the fleet and its members, rechecks the member's own main fleet
/// and sharing (which may now ask them to share with a changed fleet), and
/// says that it happened, so an unchanged result is not mistaken for none.
Future<void> officialFleetRefresh(
  BuildContext context,
  OfficialFleetModule module,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final strings = AppStrings.of(context);
  final rechecked = OfficialFleetFirstSharingChoice.recheck(context);
  await Future.wait([module.refresh(), module.members.refresh(), rechecked]);
  // A default applied by this refresh keeps its own notice.
  if (await rechecked) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      starBridgeTimedSnackBar(content: Text(strings.text('privacy.official.refreshed'))),
    );
}
