import '../../design_system/tokens/color_tokens.dart';
import '../../features/account/in_memory_account_adapter.dart';
import '../preferences/app_preferences.dart';
import '../shell/chrome/in_memory_shell_chrome.dart';
import '../shell/chrome/shell_chrome_projection.dart';

final class ShellReviewConfiguration {
  const ShellReviewConfiguration({
    required this.preferences,
    required this.projection,
    required this.accountState,
  });

  static const appearanceEnvironmentKey = 'STARBRIDGE_SHELL_REVIEW_APPEARANCE';
  static const stateEnvironmentKey = 'STARBRIDGE_SHELL_REVIEW_STATE';
  static const accountEnvironmentKey = 'STARBRIDGE_ACCOUNT_REVIEW_STATE';

  final AppPreferences preferences;
  final ShellChromeProjection projection;
  final AccountReviewState accountState;

  static ShellReviewConfiguration fromEnvironment(
    Map<String, String> environment,
  ) {
    final requestedAppearance = environment[appearanceEnvironmentKey]
        ?.trim()
        .toLowerCase();
    final requestedState = environment[stateEnvironmentKey]
        ?.trim()
        .toLowerCase();
    final requestedAccount = environment[accountEnvironmentKey]
        ?.trim()
        .toLowerCase();

    return ShellReviewConfiguration(
      preferences: AppPreferences.defaults.copyWith(
        appearanceMode: requestedAppearance == 'light'
            ? AppearanceMode.light
            : AppearanceMode.dark,
      ),
      projection: requestedState == 'healthy'
          ? InMemoryShellChrome.connectedProjection
          : InMemoryShellChrome.disconnectedProjection,
      accountState: switch (requestedAccount) {
        'signedin' => AccountReviewState.signedIn,
        'cached' => AccountReviewState.cached,
        'mismatch' => AccountReviewState.mismatch,
        'reauthorizationrequired' => AccountReviewState.reauthorizationRequired,
        _ => AccountReviewState.signedOut,
      },
    );
  }

  static ShellReviewConfiguration forExampleScene(
    Map<String, String> environment,
  ) {
    return fromEnvironment({
      stateEnvironmentKey: 'healthy',
      accountEnvironmentKey: 'signedin',
      ...environment,
    });
  }
}
