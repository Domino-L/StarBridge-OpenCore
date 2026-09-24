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

FeatureDescriptor createPersonalProfileFeature(
  PersonalProfileModule module, {
  ValueListenable<ShellChromeProjection>? presence,
  GameplayTimeController? gameplayTime,
  ValueListenable<AccountProjection>? account,
  AccountAvatarPort? avatar,
}) {
  return FeatureDescriptor(
    id: 'personal-profile',
    route: '/profile',
    labelKey: 'navigation.profile',
    descriptionKey: 'navigation.profile.description',
    icon: StarBridgeIconSemantic.profile,
    navigationRegion: NavigationRegion.accountMenu,
    order: 10,
    buildDestination: (_) {
      final page = PersonalProfilePage(
        module: module,
        presence: presence,
        gameplayTime: gameplayTime,
      );
      if (account == null) return page;
      return ValueListenableBuilder<AccountProjection>(
        valueListenable: account,
        builder: (context, value, _) => AccountAvatarScope(
          port: avatar,
          imageData: value.profile?.avatarImageData,
          editable: value.isLegacyAccount,
          child: page,
        ),
      );
    },
  );
}
