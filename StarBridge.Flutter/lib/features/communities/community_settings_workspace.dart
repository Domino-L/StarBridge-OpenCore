import '../../design_system/icons/standard_icon.dart';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_workspace_port.dart';
import 'community_workspace_image.dart';
import 'community_profile_port.dart';
import 'community_profile_dialog.dart';
import 'community_roles_port.dart';
import 'community_roles_dialog.dart';
import 'community_admissions_port.dart';
import 'community_management_dialog.dart';
import 'community_logs_port.dart';
import 'community_logs_dialog.dart';
import 'community_announcements_port.dart';
import 'community_announcements_dialog.dart';

String communitySettingsText(BuildContext context, String key) {
  const copy = <String, (String, String, String)>{
    'title': ('组织设置', '組織設定', 'Organization settings'),
    'back': ('返回组织', '返回組織', 'Back to organization'),
    'reload': ('重新读取概览', '重新讀取概覽', 'Reload overview'),
    'refreshFailed': (
      '暂时无法读取最新概览，请重试。',
      '暫時無法讀取最新概覽，請重試。',
      'Unable to load the latest overview. Please retry.',
    ),
    'overview': ('概览', '概覽', 'Overview'),
    'profile': ('基本资料', '基本資料', 'Basic profile'),
    'discovery': ('招募与公开', '招募與公開', 'Recruitment & visibility'),
    'schedule': ('活动安排', '活動安排', 'Activity schedule'),
    'contacts': ('联系方式', '聯絡方式', 'Contact details'),
    'profileGroup': ('组织资料', '組織資料', 'Organization profile'),
    'teamGroup': ('团队管理', '團隊管理', 'Team management'),
    'quickActions': ('常用管理', '常用管理', 'Quick actions'),
    'membersHelp': (
      '查看成员并分配身份组。',
      '查看成員並分配身分組。',
      'View members and assign roles.',
    ),
    'announcementsHelp': (
      '发布通知，管理当前公告与历史公告。',
      '發布通知，管理目前公告與歷史公告。',
      'Publish notices and manage current and past announcements.',
    ),
    'announcements': ('公告中心', '公告中心', 'Announcements'),
    'admissions': ('申请与邀请', '申請與邀請', 'Applications & invites'),
    'roles': ('权限与身份组', '權限與身分組', 'Permissions & roles'),
    'logs': ('数据与日志', '資料與日誌', 'Data & logs'),
    'advanced': ('高级', '進階', 'Advanced'),
    'danger': ('交接与解散', '交接與解散', 'Transfer & dissolution'),
    'identity': ('组织信息', '組織資訊', 'Organization'),
    'members': ('组织成员', '組織成員', 'Members'),
    'code': ('组织代号', '組織代號', 'Organization code'),
    'description': ('组织简介', '組織簡介', 'Description'),
    'emptyDescription': ('尚未填写组织简介。', '尚未填寫組織簡介。', 'No description yet.'),
    'overviewHelp': (
      '管理组织资料、成员权限与加入方式。',
      '管理組織資料、成員權限與加入方式。',
      'Manage your organization, permissions and joining options.',
    ),
    'profileHelp': (
      '编辑标识、简介、活动安排与联系方式。',
      '編輯標誌、簡介、活動安排與聯絡方式。',
      'Edit branding, description, activity and contacts.',
    ),
    'rolesHelp': (
      '设置身份组与权限；在成员页分配身份组。',
      '設定身分組與權限；在成員頁分配身分組。',
      'Configure roles and permissions; assign them on the members page.',
    ),
    'admissionsHelp': (
      '处理加入申请，生成或撤销邀请码。',
      '處理加入申請，產生或撤銷邀請碼。',
      'Review applications and manage invite codes.',
    ),
    'dangerHelp': (
      '交接或解散会影响整个组织。请核对对象和后果后再确认。',
      '交接或解散會影響整個組織。請核對對象和後果後再確認。',
      'Transfer or dissolution affects the whole organization. Check the target and consequences before confirming.',
    ),
    'openMembers': ('管理成员', '管理成員', 'Manage members'),
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

/// WPF's settings-center structure: persistent categories and an inline editor.
/// All editors keep their existing controllers and write/confirmation contracts.
class CommunitySettingsWorkspace extends StatefulWidget {
  const CommunitySettingsWorkspace({
    required this.port,
    required this.workspace,
    required this.targetRef,
    required this.onMembers,
    required this.dangerActions,
    required this.hasDangerActions,
    this.logo,
    this.logoLoading = false,
    this.logoFailed = false,
    this.contextInvalidations,
    this.onWorkspaceChanged,
    this.onNameConfirmed,
    super.key,
  });
  final CommunityWorkspacePort port;
  final CommunityWorkspace workspace;
  final String targetRef;
  final Uint8List? logo;
  final bool logoLoading, logoFailed;
  final Stream<void>? contextInvalidations;
  final ValueChanged<Set<String>>? onWorkspaceChanged;
  final void Function(String code, String name)? onNameConfirmed;
  final VoidCallback onMembers;
  final Widget dangerActions;
  final bool hasDangerActions;

  @override
  State<CommunitySettingsWorkspace> createState() =>
      CommunitySettingsWorkspaceState();
}

class CommunitySettingsWorkspaceState
    extends State<CommunitySettingsWorkspace> {
  final _profile = GlobalKey<CommunityProfileDialogState>();
  final _roles = GlobalKey<CommunityRolesDialogState>();
  final _admissions = GlobalKey<CommunityManagementDialogState>();
  final _logs = GlobalKey<CommunityLogsDialogState>();
  final _announcements = GlobalKey<CommunityAnnouncementEntryState>();
  String _selected = 'overview';
  bool _switching = false;
  CommunityWorkspace? _summary;
  bool _overviewLoading = false, _overviewFailed = false;
  int _overviewRead = 0;
  String t(String key) => communitySettingsText(context, key);
  static const _profileSections = [
    'profile',
    'discovery',
    'schedule',
    'contacts',
  ];

  Future<bool> confirmLeave() async {
    if (_switching) return false;
    _switching = true;
    try {
      return await (_profile.currentState?.confirmLeave() ??
          _roles.currentState?.confirmLeave() ??
          _admissions.currentState?.confirmLeave() ??
          _logs.currentState?.confirmLeave() ??
          _announcements.currentState?.confirmLeave() ??
          Future.value(true));
    } finally {
      _switching = false;
    }
  }

  Future<void> _select(String id) async {
    if (id == _selected) {
      if (_profileSections.contains(id)) {
        _profile.currentState?.scrollToSection(_profileSections.indexOf(id));
        setState(() {});
      }
      return;
    }
    if (_profileSections.contains(id) && _profileSections.contains(_selected)) {
      // These categories edit a single shared profile draft. Do not prompt,
      // discard or refetch when moving between its fields.
      if (_switching) return;
    } else if (!await confirmLeave() || !mounted) {
      return;
    }
    setState(() => _selected = id);
  }

  void _workspaceChanged(Set<String> images) {
    _summary = null;
    if (widget.onWorkspaceChanged case final changed?) {
      changed(images);
    } else {
      // Standalone settings also refresh after confirmed writes, not navigation.
      unawaited(_refreshOverview());
    }
  }

  Future<void> _refreshOverview() async {
    final read = ++_overviewRead;
    setState(() {
      _overviewLoading = true;
      _overviewFailed = false;
      _summary = null;
    });
    try {
      final latest = await widget.port.readWorkspace(widget.targetRef, '', 0);
      if (latest.targetRef != widget.targetRef) throw const FormatException();
      if (!mounted || read != _overviewRead) return;
      setState(() => _summary = latest);
    } catch (_) {
      if (mounted && read == _overviewRead) {
        setState(() => _overviewFailed = true);
      }
    } finally {
      if (mounted && read == _overviewRead) {
        setState(() => _overviewLoading = false);
      }
    }
  }

  List<(String, StandardIconSemantic)> get _sections {
    final port = widget.port, access = widget.workspace.access;
    final owner = access['isOwner'] == true;
    return [
      ('overview', StandardIconSemantic.dashboard),
      if (port is CommunityProfilePort &&
          (owner ||
              access['canEditProfile'] == true ||
              access['canEditLogo'] == true ||
              access['canEditBanner'] == true)) ...[
        ('profile', StandardIconSemantic.edit),
        if (owner || access['canEditProfile'] == true) ...[
          ('discovery', StandardIconSemantic.visibility),
          ('schedule', StandardIconSemantic.event),
          ('contacts', StandardIconSemantic.alternateEmail),
        ],
      ],
      if (port is CommunityAnnouncementsPort &&
          (port as CommunityAnnouncementsPort).announcementsAvailable)
        ('announcements', StandardIconSemantic.campaign),
      if (port is CommunityAdmissionsPort)
        ('admissions', StandardIconSemantic.personAddAlt),
      if (port is CommunityRolesPort &&
          (port as CommunityRolesPort).rolesAvailable &&
          (owner || access['canEditProfile'] == true))
        ('roles', StandardIconSemantic.adminPanelSettings),
      if (port is CommunityLogsPort &&
          (port as CommunityLogsPort).logsAvailable &&
          access['canViewLogs'] == true)
        ('logs', StandardIconSemantic.history),
      if (widget.hasDangerActions) ('danger', StandardIconSemantic.warningAmber),
    ];
  }

  Widget _module(String title, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.tokens.surfaces.raised.fill,
      border: Border.all(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _overview() {
    if (_overviewLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_overviewFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('refreshFailed')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _refreshOverview,
                child: Text(t('reload')),
              ),
            ],
          ),
        ),
      );
    }
    final workspace = _summary ?? widget.workspace;
    final available = _sections.map((entry) => entry.$1).toSet();
    return ListView(
      key: const PageStorageKey('community-settings-overview'),
      padding: const EdgeInsets.all(24),
      children: [
        Text(t('quickActions'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          t('overviewHelp'),
          style: TextStyle(color: context.tokens.colors.textSecondary),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CommunityWorkspaceImage(
                  bytes: widget.logo,
                  loading: widget.logoLoading,
                  loadFailed: widget.logoFailed,
                  icon: StandardIconSemantic.groups,
                  maxWidth: 128,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${workspace.code}  ·  ${t('members')} ${workspace.totalCount}',
                      style: TextStyle(
                        color: context.tokens.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final action in [
          if (available.contains('profile'))
            ('profile', StandardIconSemantic.edit, 'profile', 'profileHelp'),
          ('members', StandardIconSemantic.people, 'openMembers', 'membersHelp'),
          if (available.contains('admissions'))
            (
              'admissions',
              StandardIconSemantic.personAddAlt,
              'admissions',
              'admissionsHelp',
            ),
          if (available.contains('roles'))
            (
              'roles',
              StandardIconSemantic.adminPanelSettings,
              'roles',
              'rolesHelp',
            ),
          if (available.contains('announcements'))
            (
              'announcements',
              StandardIconSemantic.campaign,
              'announcements',
              'announcementsHelp',
            ),
        ])
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _quickAction(action.$1, action.$2, action.$3, action.$4),
            ),
          ),
        const SizedBox(height: 28),
        Text(t('description'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(
          workspace.description.isEmpty
              ? t('emptyDescription')
              : workspace.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _quickAction(String id, StandardIconSemantic icon, String title, String help) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('settings-quick-$id'),
          onTap: id == 'members' ? widget.onMembers : () => _select(id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.tokens.surfaces.panel.border),
              ),
            ),
            child: Row(
              children: [
                StandardIcon(icon, size: 22, color: context.tokens.colors.accent),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(title),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t(help),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const StandardIcon(StandardIconSemantic.chevronRight, size: 18),
              ],
            ),
          ),
        ),
      );

  String? _group(String section) => switch (section) {
    'overview' => null,
    'profile' || 'discovery' || 'schedule' || 'contacts' => 'profileGroup',
    'danger' => 'advanced',
    _ => 'teamGroup',
  };

  Widget _content(String selected) => switch (selected) {
    'profile' ||
    'discovery' ||
    'schedule' ||
    'contacts' => CommunityProfileDialog(
      key: _profile,
      embedded: true,
      sectionIndex: _profileSections.indexOf(selected),
      onSectionChanged: (index) =>
          setState(() => _selected = _profileSections[index]),
      port: widget.port as CommunityProfilePort,
      targetRef: widget.targetRef,
      logoBytes: widget.logo,
      onNameConfirmed: widget.onNameConfirmed,
      onSaved: (fields) {
        _workspaceChanged({
          if (fields.contains('logoImageData')) 'logo',
          if (fields.contains('bannerImageData')) 'banner',
        });
      },
    ),
    'roles' => CommunityRolesDialog(
      key: _roles,
      embedded: true,
      port: widget.port as CommunityRolesPort,
      targetRef: widget.targetRef,
      onSaved: () {
        _workspaceChanged({});
      },
    ),
    'admissions' => CommunityManagementDialog(
      key: _admissions,
      embedded: true,
      port: widget.port as CommunityAdmissionsPort,
      targetRef: widget.targetRef,
      name: widget.workspace.name,
      onMembersChanged: () {
        _workspaceChanged({});
      },
      initialSection:
          widget.workspace.access['canReviewApplications'] == true ||
              widget.workspace.access['isOwner'] == true
          ? 'applications'
          : 'invites',
    ),
    'logs' => CommunityLogsDialog(
      key: _logs,
      embedded: true,
      port: widget.port as CommunityLogsPort,
      targetRef: widget.targetRef,
      contextInvalidations: widget.contextInvalidations,
    ),
    'announcements' => CommunityAnnouncementEntry(
      key: _announcements,
      embedded: true,
      port: widget.port as CommunityAnnouncementsPort,
      targetRef: widget.targetRef,
    ),
    'danger' => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(t('danger'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          t('dangerHelp'),
          style: TextStyle(color: context.tokens.colors.textSecondary),
        ),
        const SizedBox(height: 24),
        _module(t('advanced'), widget.dangerActions),
      ],
    ),
    _ => _overview(),
  };

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final selected = sections.any((entry) => entry.$1 == _selected)
        ? _selected
        : 'overview';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final content = ClipRect(
          child: Material(
            color: context.tokens.surfaces.panel.fill,
            child: _content(selected),
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: t('title'),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const ValueKey('settings-category'),
                      value: selected,
                      isExpanded: true,
                      isDense: true,
                      style: Theme.of(context).textTheme.bodyMedium,
                      items: [
                        for (final entry in sections)
                          DropdownMenuItem(
                            value: entry.$1,
                            child: Text(t(entry.$1)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) _select(value);
                      },
                    ),
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 220,
              decoration: BoxDecoration(
                color: context.tokens.surfaces.panel.fill,
                border: Border(
                  right: BorderSide(
                    color: context.tokens.surfaces.panel.border,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                primary: false,
                key: const ValueKey('settings-navigation-scroll'),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < sections.length; index++) ...[
                      if (_group(sections[index].$1) != null &&
                          (index == 0 ||
                              _group(sections[index].$1) !=
                                  _group(sections[index - 1].$1)))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                          child: Text(
                            t(_group(sections[index].$1)!),
                            style: TextStyle(
                              color: context.tokens.colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.zero,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            key: ValueKey('settings-nav-${sections[index].$1}'),
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -2),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            minLeadingWidth: 18,
                            horizontalTitleGap: 10,
                            leading: StandardIcon(sections[index].$2, size: 18),
                            title: Text(
                              t(sections[index].$1),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            selected: selected == sections[index].$1,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            onTap: () => _select(sections[index].$1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }
}
