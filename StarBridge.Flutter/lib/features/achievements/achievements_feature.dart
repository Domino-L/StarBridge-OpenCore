import '../../app/feature_registry.dart';
import '../account/account_module.dart';
import 'achievements_page.dart';
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
}) {
  final session = AchievementCollectionSession(
    account: account.projection,
    port: port,
    mode: mode,
  );
  final scmSession = scmPort == null
      ? null
      : AchievementCollectionSession(
          account: account.projection,
          port: scmPort,
          mode: mode,
          permanentMilestones: false,
        );
  return FeatureDescriptor(
    id: 'achievements',
    route: '/achievements',
    labelKey: 'navigation.achievements',
    descriptionKey: 'navigation.achievements.description',
    icon: StarBridgeIconSemantic.achievement,
    navigationRegion: NavigationRegion.accountMenu,
    order: 15,
    onDispose: () {
      session.dispose();
      scmSession?.dispose();
    },
    prefetch: () async {
      await Future.wait([
        session.activate(),
        if (scmSession != null) scmSession.activate(),
      ]);
    },
    buildDestination: (_) => AchievementsPage(
      session: session,
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
