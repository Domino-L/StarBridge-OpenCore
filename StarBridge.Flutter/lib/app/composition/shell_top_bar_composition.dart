import 'package:flutter/widgets.dart';

import 'app_composition.dart';
import 'account_menu_motion.dart';
import '../feature_registry.dart';
import '../shell/chrome/shell_chrome_projection.dart';
import '../shell/shell_layout_mode.dart';
import '../shell/shell_navigation_controller.dart';
import '../shell/widgets/sharing_status_indicator.dart';
import '../shell/widgets/shell_top_bar.dart';

/// Presentation wiring only. Navigation and account command owners are borrowed.
ShellTopBar composeShellTopBar({
  required AppComposition composition,
  required FeatureDescriptor selected,
  required ShellChromeProjection projection,
  required ShellLayoutMode mode,
  required ValueChanged<FeatureDescriptor> onSelect,
  required VoidCallback onPrivacy,
  NavigationInteraction interaction = NavigationInteraction.keyboard,
}) => ShellTopBar(
  selected: selected,
  interaction: interaction,
  topBarDestinations: composition.features.inRegion(NavigationRegion.topBar),
  accountMenuDestinations: composition.features.inRegion(
    NavigationRegion.accountMenu,
  ),
  projection: projection,
  shellChrome: composition.shellChrome,
  mode: mode,
  onSelect: onSelect,
  onAccountLogin: () =>
      onSelect(composition.features.byRoute('/settings/account')),
  onAccountLogout: composition.logoutFromMenu,
  onAccountIssueAction: composition.resolveIssueFromMenu,
  windowChrome: composition.windowChrome,
  sharingIndicator: composition.sharingStatus == null
      ? null
      : SharingStatusIndicator(
          monitor: composition.sharingStatus!,
          compact: mode != ShellLayoutMode.wide,
          onOpenSettings: onPrivacy,
        ),
);
