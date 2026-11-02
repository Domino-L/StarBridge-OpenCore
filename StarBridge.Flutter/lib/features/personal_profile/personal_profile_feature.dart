import '../../app/feature_registry.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../account/account_models.dart';
import '../account/account_avatar.dart';
import '../account/account_avatar_editor.dart';

import '../../app/shell/chrome/shell_chrome_projection.dart';
import 'personal_profile_module.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_page.dart';
import 'personal_profile_trade_strip.dart';
import '../onboarding/connection_mode_port.dart';
import 'personal_profile_port.dart';
import 'offline_personal_profile_page.dart';
import 'personal_profile_display_session.dart';

FeatureDescriptor createPersonalProfileFeature(
  PersonalProfileModule module, {
  ValueListenable<ShellChromeProjection>? presence,
  GameplayTimeController? gameplayTime,
  ValueListenable<AccountProjection>? account,
  AccountAvatarPort? avatar,
  ConnectionModeControl? connectionMode,
  PersonalProfilePort Function()? offlineFactory,
  PersonalProfilePort Function(String readId)? retainedFactory,
  ProfileTradeStripBuilder? tradeStrip,
}) {
  final display = connectionMode == null || offlineFactory == null
      ? null
      : PersonalProfileDisplaySession(
          mode: connectionMode,
          createPort: offlineFactory,
          onlineModule: module,
          account: account,
          createRetainedPort: retainedFactory,
        );
  return FeatureDescriptor(
    id: 'personal-profile',
    route: '/profile',
    labelKey: 'navigation.profile',
    descriptionKey: 'navigation.profile.description',
    icon: StarBridgeIconSemantic.profile,
    navigationRegion: NavigationRegion.accountMenu,
    order: 10,
    onDispose: display?.dispose,
    buildDestination: (_) {
      Widget page = PersonalProfilePage(
        module: module,
        presence: presence,
        gameplayTime: gameplayTime,
      );
      if (tradeStrip != null) {
        page = ProfileTradeStripScope(builder: tradeStrip, child: page);
      }
      if (connectionMode != null && offlineFactory != null) {
        page = OfflinePersonalProfilePage(
          mode: connectionMode,
          createPort: offlineFactory,
          account: account,
          createRetainedPort: retainedFactory,
          onlineModule: module,
          displaySession: display,
          online: page,
        );
      }
      if (account == null) return page;
      return ValueListenableBuilder<AccountProjection>(
        valueListenable: account,
        builder: (context, value, _) => AccountAvatarScope(
          port: avatar,
          imageData: value.profile?.avatarImageData,
          editable:
              value.isLegacyAccount ||
              (value.isSignedIn && avatar?.canEditScm == true),
          rsiManaged: value.isSignedIn && !value.isLegacyAccount,
          child: page,
        ),
      );
    },
  );
}
