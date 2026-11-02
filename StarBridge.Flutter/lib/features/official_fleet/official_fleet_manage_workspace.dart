import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../app/localization/app_strings.dart';
import '../common/organization_communication.dart';
import '../common/organization_governance_port.dart';
import '../common/organization_governance_settings.dart';
import '../common/organization_hangar_sharing.dart';
import '../communities/community_hangar_sharing_dialog.dart';
import '../settings/organization_notification_pane.dart';
import '../settings/organization_personal_settings.dart';
import '../settings/organization_privacy_pane.dart';
import 'official_fleet_models.dart';
import 'official_fleet_profile_section.dart';
import 'official_fleet_rally.dart';
import 'official_fleet_rally_views.dart';
import 'official_fleet_governance_workspace.dart';
import 'official_fleet_governance_copy.dart';

String _text(BuildContext context, String key) {
  if (const {'ranks', 'roles', 'audit'}.contains(key)) {
    return fleetGovernanceText(context, key);
  }
  const copy = <String, (String, String, String)>{
    'overview': ('概览', '概覽', 'Overview'),
    'announcements': ('公告中心', '公告中心', 'Announcements'),
    'rally': ('召集', '召集', 'Rally'),
    'sharing': ('我的共享', '我的共享', 'My sharing'),
    'teamGroup': ('团队管理', '團隊管理', 'Team management'),
    'mineGroup': ('我自己', '我自己', 'For me'),
    'privacy': ('隐私', '隱私', 'Privacy'),
    'notifications': ('通知', '通知', 'Notifications'),
    'fleet': ('舰队信息', '艦隊資訊', 'Fleet information'),
    'quickActions': ('常用管理', '常用管理', 'Quick actions'),
    'announcementsHelp': (
      '发布通知，管理当前公告与历史公告。',
      '發布通知，管理目前公告與歷史公告。',
      'Publish notices and manage current and past announcements.',
    ),
    'rallyHelp': (
      '通知此刻在线的成员马上集合。',
      '通知此刻在線的成員馬上集合。',
      'Ask the members online right now to gather.',
    ),
    'rallyRunning': (
      '召集进行中，进度显示在页面上方。',
      '召集進行中，進度顯示在頁面上方。',
      'A rally is running. Its progress is at the top of the page.',
    ),
    'sharingHelp': (
      '选择把哪些舰船共享给主舰队，只影响你自己的舰船。',
      '選擇把哪些艦船共享給主艦隊，只影響你自己的艦船。',
      'Choose which of your ships the main fleet can see.',
    ),
    'sharingOpen': ('管理我的共享舰船', '管理我的共享艦船', 'Manage my shared ships'),
    'permissionsHelp': (
      '查看你在主舰队的角色和当前权限。',
      '查看你在主艦隊的角色和目前權限。',
      'See your role and current permissions in the main fleet.',
    ),
  };
  final value = copy[key]!;
  final locale = AppStrings.of(context).locale;
  if (locale.languageCode != 'zh') return value.$3;
  return locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK'
      ? value.$2
      : value.$1;
}

/// 组织设置 for the main fleet, in the community settings' left-hand structure.
/// Only management this client can really complete: what lives on the RSI or
/// SCM sites has no entry here. Each pane shows only for who may use it, and
/// the relay and Host still decide every action.
class OfficialFleetManageWorkspace extends StatelessWidget {
  const OfficialFleetManageWorkspace({
    required this.fleet,
    required this.projection,
    required this.communication,
    required this.rally,
    required this.onBack,
    this.hangarSharingPort,
    super.key,
  });

  final OfficialFleetSummary fleet;
  final OfficialFleetProjection projection;
  final OrganizationCommunication communication;
  final OfficialFleetRallyController rally;
  final Future<void> Function() onBack;
  final OrganizationHangarSharingPort? hangarSharingPort;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: rally,
    builder: (context, _) {
      final live = rally.current?.activeAt(rally.now()) == true;
      final canAnnounce = communication.announcementManagementGranted;
      // A running rally stays in the page strip for everyone; this section is
      // only for who may start one (user 2026-10-31: revoking removes it).
      final canRally = rally.canStart;
      final sharing = hangarSharingPort?.available == true
          ? hangarSharingPort
          : null;
      final personal = OrganizationPersonalSettings.of(context);
      final privacy = personal?.privacy;
      final notifications = personal?.notificationSources;
      return OfficialFleetGovernanceWorkspace(
        port: communication.governance,
        source: fleet.sourceRef,
        onAuthorityRead: (authority) {
          unawaited(rally.refresh(eligibility: true));
          unawaited(
            communication.recheckAnnouncementManagement(
              allowed: authority.capabilities.any(
                (d) =>
                    d.key == 'announcements.manage' &&
                    d.state == OrganizationDecisionState.allowed,
              ),
            ),
          );
        },
        builder: (governancePanes, authorityRead, authorityUnavailable) =>
            OrganizationGovernanceSettings(
              port: communication.governance,
              sourceRef: fleet.sourceRef,
              name: fleet.name,
              onBack: onBack,
              label: (key) => _text(context, key),
              initialPane: 'overview',
              permissionsGroup: 'mineGroup',
              // Enabling or revoking changes what this page may offer at once.
              onAuthorityRead: authorityRead,
              onAuthorityUnavailable: authorityUnavailable,
              panesBefore: [
                OrganizationGovernancePane(
                  id: 'overview',
                  icon: StandardIconSemantic.dashboard,
                  builder: (select) => _Overview(
                    fleet: fleet,
                    projection: projection,
                    canAnnounce: canAnnounce,
                    canRally: canRally,
                    sharing: sharing != null,
                    select: select,
                  ),
                ),
                if (canAnnounce)
                  OrganizationGovernancePane(
                    id: 'announcements',
                    icon: StandardIconSemantic.campaign,
                    group: 'teamGroup',
                    // The page frame already offers 公告处理结果 above this section.
                    builder: (_) => communication.announcement(expanded: true),
                  ),
                if (canRally)
                  OrganizationGovernancePane(
                    id: 'rally',
                    icon: StandardIconSemantic.event,
                    group: 'teamGroup',
                    builder: (_) => _RallyPane(rally: rally, live: live),
                  ),
                ...governancePanes,
              ],
              panesAfter: [
                if (sharing != null)
                  OrganizationGovernancePane(
                    id: 'sharing',
                    icon: StandardIconSemantic.visibility,
                    group: 'mineGroup',
                    builder: (_) =>
                        _SharingPane(port: sharing, sourceRef: fleet.sourceRef),
                  ),
                if (privacy != null)
                  OrganizationGovernancePane(
                    id: 'privacy',
                    icon: StandardIconSemantic.verifiedUser,
                    group: 'mineGroup',
                    builder: (_) =>
                        OrganizationPrivacyPane(controller: privacy),
                  ),
                if (notifications != null)
                  OrganizationGovernancePane(
                    id: 'notifications',
                    icon: StandardIconSemantic.campaign,
                    group: 'mineGroup',
                    builder: (_) =>
                        OrganizationNotificationPane(create: notifications),
                  ),
              ],
            ),
      );
    },
  );
}

/// The same start action and rally state as the activity page; the running
/// rally itself stays in the workspace strip above, so it never shows twice.
class _RallyPane extends StatelessWidget {
  const _RallyPane({required this.rally, required this.live});

  final OfficialFleetRallyController rally;
  final bool live;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_text(context, live ? 'rallyRunning' : 'rallyHelp')),
      const SizedBox(height: 16),
      OfficialFleetRallyStartButton(controller: rally),
    ],
  );
}

class _SharingPane extends StatelessWidget {
  const _SharingPane({required this.port, required this.sourceRef});

  final OrganizationHangarSharingPort port;
  final String sourceRef;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_text(context, 'sharingHelp')),
      const SizedBox(height: 16),
      StarBridgeActionButton(
        controlKey: const Key('official-fleet-manage-sharing'),
        kind: StarBridgeActionKind.primary,
        // As from the ships page: a save in flight must not lose its result.
        onActivate: (source) => showStarBridgeDialog<bool>(
          context,
          source: source,
          useRootNavigator: false,
          barrierDismissible: false,
          builder: (_) => CommunityHangarSharingDialog.editor(
            editor: port,
            sourceRef: sourceRef,
          ),
        ),
        child: Text(_text(context, 'sharingOpen')),
      ),
    ],
  );
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.fleet,
    required this.projection,
    required this.canAnnounce,
    required this.canRally,
    required this.sharing,
    required this.select,
  });

  final OfficialFleetSummary fleet;
  final OfficialFleetProjection projection;
  final bool canAnnounce, canRally, sharing;
  final Future<void> Function(String) select;

  Widget _action(
    BuildContext context,
    String id,
    StandardIconSemantic icon,
    String help,
  ) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        type: MaterialType.transparency,
        child: StarBridgeActionRow(
          controlKey: ValueKey('official-fleet-manage-quick-$id'),
          semanticLabel: _titleOf(context, id),
          onActivate: (_, _) => select(id),
          child: ListTile(
            dense: true,
            leading: StandardIcon(icon, size: 20),
            title: Text(_titleOf(context, id)),
            subtitle: Text(
              help,
              style: TextStyle(color: tokens.colors.textSecondary),
            ),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: tokens.surfaces.panel.border),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }

  String _titleOf(BuildContext context, String id) => id == 'permissions'
      ? organizationGovernanceText(context, 'permissions')
      : _text(context, id);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _text(context, 'quickActions'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      if (canAnnounce)
        _action(
          context,
          'announcements',
          StandardIconSemantic.campaign,
          _text(context, 'announcementsHelp'),
        ),
      if (canRally)
        _action(
          context,
          'rally',
          StandardIconSemantic.event,
          _text(context, 'rallyHelp'),
        ),
      _action(
        context,
        'permissions',
        StandardIconSemantic.adminPanelSettings,
        _text(context, 'permissionsHelp'),
      ),
      if (sharing)
        _action(
          context,
          'sharing',
          StandardIconSemantic.visibility,
          _text(context, 'sharingHelp'),
        ),
      const SizedBox(height: 16),
      Text(
        _text(context, 'fleet'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      OfficialFleetProfileSection(
        fleet: fleet,
        observedAtUtc: projection.observedAtUtc,
        profileReadState: projection.profileReadState,
        isReading: projection.isProfileReading,
        profileObservedAtUtc: projection.profileObservedAtUtc,
      ),
    ],
  );
}
