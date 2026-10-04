import 'overlay_workspace_models.dart';

final class OverlayWorkspaceAppearanceRule {
  const OverlayWorkspaceAppearanceRule({
    required this.theme,
    required this.startupTransition,
    required this.locksTheme,
    required this.supportsBloom,
  });

  final String theme;
  final String startupTransition;
  final bool locksTheme;
  final bool supportsBloom;
}

const overlayWorkspaceAppearanceRules =
    <String, OverlayWorkspaceAppearanceRule>{
      'Default': OverlayWorkspaceAppearanceRule(
        theme: 'Default',
        startupTransition: 'BridgeTerminal',
        locksTheme: false,
        supportsBloom: false,
      ),
      'NightShadow': OverlayWorkspaceAppearanceRule(
        theme: 'NightShadow',
        startupTransition: 'NightShadowFlowField',
        locksTheme: true,
        supportsBloom: true,
      ),
      'LagrangeWeave': OverlayWorkspaceAppearanceRule(
        theme: 'LagrangeWeave',
        startupTransition: 'LagrangeWeaveEquilibrium',
        locksTheme: true,
        supportsBloom: true,
      ),
      'Verdict': OverlayWorkspaceAppearanceRule(
        theme: 'Verdict',
        startupTransition: 'VerdictProtocol',
        locksTheme: true,
        supportsBloom: true,
      ),
    };

OverlayWorkspaceAppearanceRule overlayWorkspaceAppearanceRule(
  OverlayWorkspaceSettings settings,
) =>
    overlayWorkspaceAppearanceRules[settings['skin']] ??
    overlayWorkspaceAppearanceRules['Default']!;

OverlayWorkspaceSettings applyOverlayWorkspaceAppearanceAvailability(
  OverlayWorkspaceSettings settings,
  List<OverlayWorkspaceAppearance> appearances,
) {
  if (appearances.isEmpty) return settings;
  final byId = {
    for (final appearance in appearances) appearance.id: appearance,
  };
  final skin = settings['skin']! as String;
  final savedRequest = settings['requestedSkin']! as String;
  final requested = skin != 'Default' ? skin : savedRequest;
  final requestedAppearance = byId[requested];
  if (requestedAppearance?.isAvailable == true) {
    return applyOverlayWorkspaceSettingChange(settings, 'skin', requested);
  }

  final fallback = byId['Default']?.isAvailable == true
      ? 'Default'
      : appearances.firstWhere((appearance) => appearance.isAvailable).id;
  final next = applyOverlayWorkspaceSettingChange(settings, 'skin', fallback);
  return next.withValue(
    'requestedSkin',
    requestedAppearance == null ? fallback : requested,
  );
}

OverlayWorkspaceSettings applyOverlayWorkspaceSettingChange(
  OverlayWorkspaceSettings current,
  String field,
  Object? value,
) {
  var next = current.withValue(field, value);
  if (field == 'skin') {
    final skin = value! as String;
    final profile = overlayWorkspaceAppearanceRules[skin];
    if (profile != null) {
      // The native compatibility resolver can infer a skin from its theme.
      // Clear only appearance-locked themes when explicitly returning to the
      // standard skin; keep ordinary manufacturer palettes intact.
      if (skin == 'Default' &&
          overlayWorkspaceAppearanceRules.values.any(
            (rule) => rule.locksTheme && rule.theme == current['theme'],
          )) {
        next = next.withValue('theme', profile.theme);
      }
      next = next
          .withValue('requestedSkin', skin)
          .withValue('startupTransitionFollowOverlayTheme', true)
          .withValue('startupTransitionStyle', profile.startupTransition);
    }
  }

  final profile = overlayWorkspaceAppearanceRule(next);
  next = next
      .withValue('startupTransitionFollowOverlayTheme', true)
      .withValue('startupTransitionStyle', profile.startupTransition);
  if (profile.locksTheme) {
    next = next
        .withValue('theme', profile.theme)
        .withValue('autoThemeByShip', false);
  }
  return next;
}

bool overlayWorkspaceFieldVisible(
  String field,
  OverlayWorkspaceSettings settings,
) {
  final barrage = settings['chatDisplayMode'] == 'FullScreenBarrage';
  if (const {
    'chatDurationSeconds',
    'chatBarrageFontSize',
    'chatBarrageRegion',
    'chatBarrageDensity',
    'chatBarrageAvoidCenter',
    'chatTextEdgeStrength',
  }.contains(field)) {
    return barrage;
  }
  if (const {'chatSide', 'chatMaxVisibleCount'}.contains(field)) {
    return false;
  }
  if (field == 'nightShadowBloom') {
    return overlayWorkspaceAppearanceRule(settings).supportsBloom;
  }
  if ((field == 'theme' || field == 'autoThemeByShip') &&
      overlayWorkspaceAppearanceRule(settings).locksTheme) {
    return false;
  }
  if (field == 'requestedSkin') return false;
  if (field == 'startupTransitionFollowOverlayTheme' ||
      field == 'fleetChatScope') {
    return false;
  }
  return true;
}

bool overlayWorkspaceFieldEnabled(
  String field,
  OverlayWorkspaceSettings settings,
) => overlayWorkspaceFieldDisabledReason(field, settings) == null;

/// One policy drives both availability and its explanation.
String? overlayWorkspaceFieldDisabledReason(
  String field,
  OverlayWorkspaceSettings settings,
) {
  const prefix = 'overlay.workspace.disabled.';
  if (overlayWorkspaceAppearanceRule(settings).locksTheme &&
      const {'theme', 'autoThemeByShip'}.contains(field)) {
    return '${prefix}fixedPalette';
  }
  if (field.startsWith('crosshair') && settings['showCrosshair'] != true) {
    return '${prefix}crosshair';
  }
  if (field == 'crosshairColor' && settings['crosshairUseThemeColor'] == true) {
    return '${prefix}themeColor';
  }
  final mode = settings['crosshairMode'];
  if ((mode == 'Dot' &&
          const {
            'crosshairSize',
            'crosshairThickness',
            'crosshairGap',
            'crosshairShowCenterMark',
          }.contains(field)) ||
      (mode == 'Circle' && field == 'crosshairGap')) {
    return '${prefix}crosshairStyle';
  }
  if (field == 'crosshairCenterMarkSize' &&
      mode != 'Dot' &&
      settings['crosshairShowCenterMark'] != true) {
    return '${prefix}centerMark';
  }
  if (field.startsWith('eventNotification') &&
      settings['showEventNotifications'] != true) {
    return '${prefix}events';
  }
  if (field.startsWith('chat') &&
      field != 'chatDisplayMode' &&
      settings['showChat'] != true) {
    return '${prefix}chat';
  }
  if (field == 'hideMemberOnlineStatus' &&
      settings['hideOfflineMembers'] != true) {
    return '${prefix}offlineMembers';
  }
  if (const {
        'communicationFriendEvents',
        'communicationEventDurationSeconds',
        'communicationMessagePreview',
      }.contains(field) &&
      settings['showNotice'] != true) {
    return '${prefix}notice';
  }
  if (field == 'communicationMessagePreview' &&
      settings['communicationFriendEvents'] != true) {
    return '${prefix}friendEvents';
  }
  if (const {
        'skipStartupTransitionWhenGameForeground',
        'startupTransitionFrameRate',
      }.contains(field) &&
      settings['enableStartupTransition'] != true) {
    return '${prefix}startup';
  }
  return null;
}
