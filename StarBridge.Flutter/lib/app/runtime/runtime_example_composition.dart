import '../../features/account/in_memory_account_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import '../../features/personal_profile/in_memory_personal_profile_adapter.dart';
import '../../platform/window/method_channel_menu_preview_window.dart';
import '../../platform/window/window_chrome_port.dart';
import '../bootstrap/shell_review_configuration.dart';
import '../composition/app_composition.dart';
import '../preferences/in_memory_app_preferences.dart';
import '../shell/chrome/in_memory_shell_chrome.dart';

/// Builds the explicit example scene without changing the product connection
/// owner, its preferences or its Host lifecycle.
AppComposition createRuntimeExampleComposition({
  required Map<String, String> environment,
  required MenuWindowLifetime menuLifetime,
  required WindowChromePort windowChrome,
}) {
  final review = ShellReviewConfiguration.forExampleScene(environment);
  return AppComposition.forShellReview(
    menuLifetime: menuLifetime,
    windowChrome: windowChrome,
    preferences: InMemoryAppPreferences(initial: review.preferences),
    shellChrome: InMemoryShellChrome(initial: review.projection),
    accountPort: InMemoryAccountAdapter.forReview(review.accountState),
    personalProfilePort: InMemoryPersonalProfileAdapter.forReview(
      signedIn: review.accountState != AccountReviewState.signedOut,
    ),
    officialFleetPort: InMemoryOfficialFleetAdapter.forReview(
      signedIn: review.accountState != AccountReviewState.signedOut,
    ),
    officialFleetMembersPort: InMemoryOfficialFleetMembersAdapter.forReview(),
  );
}
