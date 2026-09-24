import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/overlay_settings/overlay_preview_identity.dart';
import '../../features/personal_profile/personal_profile_models.dart';

/// Combines account and personal-profile projections without coupling either
/// feature implementation to the overlay feature.
final class OverlayPreviewIdentityAdapter
    implements ValueListenable<OverlayPreviewIdentity?> {
  const OverlayPreviewIdentityAdapter({
    required this.account,
    required this.personalProfile,
  });

  final ValueListenable<AccountProjection> account;
  final ValueListenable<PersonalProfileProjection> personalProfile;

  @override
  OverlayPreviewIdentity? get value {
    final profile = personalProfile.value;
    final accountValue = account.value;
    final accountName = accountValue.profile?.displayName?.trim() ?? '';
    final accountHandle =
        accountValue.identity.authoritativeHandle?.trim() ?? '';
    var callSign = profile.callSign.trim();
    var gameHandle = profile.gameHandle.trim();
    if (callSign.isEmpty) callSign = accountName;
    if (gameHandle.isEmpty) gameHandle = accountHandle;
    if (callSign.isEmpty) callSign = gameHandle;
    if (gameHandle.isEmpty) gameHandle = callSign;
    if (callSign.isEmpty) return null;
    return OverlayPreviewIdentity(callSign: callSign, gameHandle: gameHandle);
  }

  @override
  void addListener(VoidCallback listener) {
    account.addListener(listener);
    personalProfile.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    account.removeListener(listener);
    personalProfile.removeListener(listener);
  }
}
