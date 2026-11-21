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
      'Verdict': OverlayWorkspaceAppearanceRule(
        theme: 'Verdict',
        startupTransition: 'VerdictProtocol',
        locksTheme: true,
        supportsBloom: true,
      ),
      // 0.7.3 visor projection (open core): keeps the chosen palette and
      // "follow my ship" colours; same startup as the standard appearance.
      'Visor': OverlayWorkspaceAppearanceRule(
        theme: 'Default',
        startupTransition: 'BridgeTerminal',
        locksTheme: false,
        supportsBloom: false,
      ),
    };

/// 0.7.3 overlay v2 (user, 11-07: "之前的外观都暂时隐藏 只留面罩这一个"; "藏，等之后做v2"):
/// these appearances stay saved and qualified, but the overlay shows the visor
/// until each is redone for v2. Mirrors OverlaySkinCatalog.HiddenUntilV2.
const overlayAppearancesHiddenUntilV2 = {
  'Default',
  'NightShadow',
  'Verdict',
  'HajiCitizen',
};

/// The appearance the overlay shows: a hidden one shows as the visor. The
/// saved `skin` is left as it is, so the choice comes back with v2.
String overlayWorkspaceShownSkin(OverlayWorkspaceSettings settings) {
  final skin = settings['skin']! as String;
  return overlayAppearancesHiddenUntilV2.contains(skin) ? 'Visor' : skin;
}

OverlayWorkspaceAppearanceRule overlayWorkspaceAppearanceRule(
  OverlayWorkspaceSettings settings,
) =>
    overlayWorkspaceAppearanceRules[overlayWorkspaceShownSkin(settings)] ??
    overlayWorkspaceAppearanceRules['Default']!;

OverlayWorkspaceSettings applyOverlayWorkspaceAppearanceAvailability(
  OverlayWorkspaceSettings settings,
  List<OverlayWorkspaceAppearance> appearances,
) {
  if (appearances.isEmpty) return settings;
  // A hidden appearance is shown as the visor without touching what was saved
  // (skin and requestedSkin), so the next save keeps the user's choice.
  if (overlayAppearancesHiddenUntilV2.contains(settings['skin'])) {
    return settings;
  }
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
  // Choosing the events' side from the list takes them back to that screen
  // edge: their place across (11-12) is measured from the side they had.
  if (field == 'eventNotificationSide' &&
      value != current['eventNotificationSide'] &&
      next.values.containsKey('visorEventsX')) {
    next = next.withValue('visorEventsX', -1.0);
  }
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
  OverlayWorkspaceSettings settings, {
  OverlayWorkspaceAppearanceRule? appearanceRule,
}) {
  // Settings that apply only in some mode stay visible and explain when they
  // apply (overlayWorkspaceFieldDisabledReason). Only retired or internal
  // fields are hidden.
  // 0.7.3: only the visor is offered, so there is no appearance to choose;
  // the overlay has no holiday look for now (user, 11-07: "浮层先不做节日").
  if (const {'skin', 'visorHolidayGold'}.contains(field)) return false;
  if (field == 'chatSide') return false;
  // 11-10 user (settings comparison): "去掉“隐藏成员在线状态”"
  if (field == 'hideMemberOnlineStatus') return false;
  // 11-10 user: settings the visor has no use for are not shown with it
  // ("面罩下隐藏这个开关" for the fleet overview, which the visor shows on top
  // of the members; the name column width and startup style likewise).
  if (overlayWorkspaceShownSkin(settings) == 'Visor' &&
      const {
        'showSquads',
        'memberNameColumnRatio',
        'startupTransitionStyle',
      }.contains(field)) {
    return false;
  }
  // bloom only where the shown appearance has it (11-10: hidden otherwise)
  if (field == 'nightShadowBloom') {
    return (appearanceRule ?? overlayWorkspaceAppearanceRule(settings))
        .supportsBloom;
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
  OverlayWorkspaceSettings settings, {
  OverlayWorkspaceAppearanceRule? appearanceRule,
}) =>
    overlayWorkspaceFieldDisabledReason(
      field,
      settings,
      appearanceRule: appearanceRule,
    ) ==
    null;

const _barrageFields = {
  'chatDurationSeconds',
  'chatBarrageFontSize',
  'chatBarrageRegion',
  'chatBarrageDensity',
  'chatBarrageAvoidCenter',
  'chatTextEdgeStrength',
};

/// The members size values read as a maximum while their dimension is
/// adaptive and as the fixed size otherwise (11-07); their label says which.
String? overlayWorkspaceFieldLabelKey(
  String field,
  OverlayWorkspaceSettings settings,
) => switch (field) {
  'visorMembersWidth' =>
    'overlay.workspace.field.visorMembersWidth.'
        '${settings['visorMembersAutoWidth'] == false ? 'fixed' : 'max'}',
  // 11-10 user: the members height is always fixed ("就要固定上下高度")
  'visorMembersHeight' => 'overlay.workspace.field.visorMembersHeight',
  'visorEventsWidth' =>
    'overlay.workspace.field.visorEventsWidth.'
        '${settings['visorEventsAutoWidth'] == false ? 'fixed' : 'max'}',
  'visorChatWidth' =>
    'overlay.workspace.field.visorChatWidth.'
        '${settings['visorChatAutoWidth'] == false ? 'fixed' : 'max'}',
  _ => null,
};

/// One policy drives both availability and its explanation.
String? overlayWorkspaceFieldDisabledReason(
  String field,
  OverlayWorkspaceSettings settings, {
  OverlayWorkspaceAppearanceRule? appearanceRule,
}) {
  final profile = appearanceRule ?? overlayWorkspaceAppearanceRule(settings);
  const prefix = 'overlay.workspace.disabled.';
  if (profile.locksTheme &&
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
  if (_barrageFields.contains(field) &&
      settings['chatDisplayMode'] != 'FullScreenBarrage') {
    return '${prefix}barrage';
  }
  // the message list keeps a number of lines; the barrage runs them across
  if (field == 'chatMaxVisibleCount' &&
      settings['chatDisplayMode'] == 'FullScreenBarrage') {
    return '${prefix}messageList';
  }
  // 11-10 user: the visor's message list shows no send time
  if (field == 'chatShowTimestamp' &&
      overlayWorkspaceShownSkin(settings) == 'Visor' &&
      settings['chatDisplayMode'] != 'FullScreenBarrage') {
    return '${prefix}visorListTime';
  }
  if (field == 'nightShadowBloom' && !profile.supportsBloom) {
    return '${prefix}bloom';
  }
  if (const {
        'visorSize',
        'visorTilt',
        'visorViewingDistance',
        'visorChatPlate',
        'visorMembersAutoWidth',
        'visorMembersAutoHeight',
        'visorMembersWidth',
        'visorMembersHeight',
        'visorEventsAutoWidth',
        'visorEventsWidth',
        'visorChatAutoWidth',
        'visorChatWidth',
        'visorHolidayGold',
      }.contains(field) &&
      overlayWorkspaceShownSkin(settings) != 'Visor') {
    return '${prefix}visor';
  }
  if (field == 'visorViewingDistance' &&
      ((settings['visorTilt'] as num?)?.toDouble() ?? 15) == 0) {
    return '${prefix}visorFlat';
  }
  if (field == 'hideMemberOnlineStatus' &&
      settings['hideOfflineMembers'] != true) {
    return '${prefix}offlineMembers';
  }
  if (field == 'communicationEventDurationSeconds' &&
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

/// [settings] with the events placed: the screen side they open from and lean
/// to, their height (0..1) and, when given, where they sit across (11-12: [x]
/// a screen fraction of their screen-edge side, anything else -1, at the
/// edge); null when nothing changes.
OverlayWorkspaceSettings? overlayWorkspaceEventPlacement(
  OverlayWorkspaceSettings settings,
  String side,
  double y, {
  double? x,
}) {
  final nextSide = side == 'Left' ? 'Left' : 'Right';
  final nextY = y.clamp(0.0, 1.0).toDouble();
  final currentX = (settings['visorEventsX'] as num?)?.toDouble() ?? -1.0;
  final nextX = x == null
      ? currentX
      : x >= 0 && x <= 1
      ? x
      : -1.0;
  if (settings['eventNotificationSide'] == nextSide &&
      ((settings['eventNotificationY']! as num) - nextY).abs() < 0.000001 &&
      (currentX - nextX).abs() < 0.000001) {
    return null;
  }
  final next = settings
      .withValue('eventNotificationSide', nextSide)
      .withValue('eventNotificationY', nextY);
  return x == null ? next : next.withValue('visorEventsX', nextX);
}

/// The visor shows the overview inside the members block and the overview has
/// no settings of its own (D6; 11-13 user, 请你定 7): it reads from the
/// members' source, so the counts above the list always match the list.
OverlayPresetSources overlayOverviewFollowsMembers(OverlayPresetSources value) {
  final members = value.forModule(OverlaySourceModule.members);
  return value.forModule(OverlaySourceModule.overview) == members
      ? value
      : value.withModule(OverlaySourceModule.overview, members);
}
