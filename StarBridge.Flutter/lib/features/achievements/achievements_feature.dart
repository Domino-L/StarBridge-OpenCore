import '../../app/feature_registry.dart';
import '../account/account_module.dart';
import 'achievements_page.dart';
import 'swift_leaderboard.dart';
import 'swift_leaderboard_page.dart';
import 'achievement_collection_port.dart';
import 'achievement_collection_session.dart';
import 'achievement_ideas_port.dart';
import '../onboarding/connection_mode_port.dart';

FeatureDescriptor createAchievementsFeature(
  AccountModule account, {
  AchievementCollectionPort port = const UnavailableAchievementCollection(),
  AchievementCollectionPort? scmPort,
  AchievementIdeasPort ideas = const UnavailableAchievementIdeas(),
  ConnectionModeControl? mode,
  // Shared with the personal profile's achievement showcase; this feature
  // still owns and disposes it.
  AchievementCollectionSession? session,
  // The SCM half, shared with the personal profile the same way.
  AchievementCollectionSession? scmSession,
  SwiftLeaderboardController? leaderboard,
}) {
  session ??= AchievementCollectionSession(
    account: account.projection,
    port: port,
    mode: mode,
  );
  scmSession ??= scmPort == null
      ? null
      : AchievementCollectionSession(
          account: account.projection,
          port: scmPort,
          mode: mode,
          permanentMilestones: false,
        );
  return FeatureDescriptor(
    id: 'achievements',
    runtimePromptBuilder: leaderboard == null
        ? null
        : (child) => SwiftAwardPrompt(controller: leaderboard, child: child),
    route: '/achievements',
    labelKey: 'navigation.achievements',
    descriptionKey: 'navigation.achievements.description',
    icon: StarBridgeIconSemantic.achievement,
    navigationRegion: NavigationRegion.accountMenu,
    order: 15,
    onDispose: () {
      leaderboard?.dispose();
      session!.dispose();
      scmSession?.dispose();
    },
    prefetch: () async {
      await Future.wait([
        session!.activate(),
        if (scmSession != null) scmSession.activate(),
      ]);
    },
    buildDestination: (_) => AchievementsPage(
      session: session!,
      leaderboard: leaderboard,
      scmSession: scmSession,
      scmPort: scmPort,
      account: account.projection,
      port: port,
      ideas: ideas,
      mode: mode,
      onSignIn: () {
        account.beginLogin();
      },
    ),
  );
}
