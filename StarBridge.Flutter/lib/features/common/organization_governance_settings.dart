import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../communities/communities_module.dart';
import '../communities/community_workspace_management_chrome.dart';
import '../communities/community_settings_workspace.dart'
    show communitySettingsText;
import 'organization_governance_port.dart';
import 'organization_settings_layout.dart';

/// One more left-hand section beside the permissions read.
@immutable
final class OrganizationGovernancePane {
  const OrganizationGovernancePane({
    required this.id,
    required this.icon,
    required this.builder,
    this.group,
    this.retainState = false,
  });
  final String id;
  final StandardIconSemantic icon;
  final String? group;
  final bool retainState;

  /// Receives the way to switch to another section.
  final Widget Function(Future<void> Function(String) select) builder;
}

class OrganizationGovernanceSettings extends StatefulWidget {
  const OrganizationGovernanceSettings({
    required this.port,
    required this.sourceRef,
    required this.name,
    required this.onBack,
    this.panesBefore = const [],
    this.panesAfter = const [],
    this.label,
    this.initialPane = 'permissions',
    this.permissionsGroup,
    this.onAuthorityRead,
    this.onAuthorityUnavailable,
    super.key,
  });
  final OrganizationGovernancePort port;

  /// Every completed read of the viewer's rights, on entry and after enabling
  /// or revoking, for what the rest of the organization page derives from them.
  final ValueChanged<OrganizationGovernanceContext>? onAuthorityRead;
  final ValueChanged<String>? onAuthorityUnavailable;
  final String sourceRef, name;
  final Future<void> Function() onBack;
  final List<OrganizationGovernancePane> panesBefore, panesAfter;

  /// Names the extra panes and groups; permissions keep their own copy.
  final String Function(String)? label;
  final String initialPane;
  final String? permissionsGroup;
  @override
  State<OrganizationGovernanceSettings> createState() => _SettingsState();
}

class _SettingsState extends State<OrganizationGovernanceSettings> {
  late String _selected = widget.initialPane;
  late StreamSubscription<void> _subscription;
  OrganizationGovernanceContext? _context;
  String? _error;
  bool _loading = false, _writing = false;
  int _epoch = 0, _writeEpoch = 0;
  final _visitedPanes = <String>{};

  /// The whole request whose outcome is unknown: a retry repeats exactly it
  /// (same id, same expected revision) instead of creating a second intent.
  ({bool active, String id, int revision, String source})? _pendingIntent;

  void _retireWrite() {
    ++_writeEpoch;
    _writing = false;
    _pendingIntent = null;
    _writeResult = null;
  }

  String? _writeResult;
  void _bind() {
    final port = widget.port, source = widget.sourceRef;
    _subscription = port.invalidations.listen((_) {
      if (!mounted || widget.port != port || widget.sourceRef != source) return;
      ++_epoch;
      setState(() {
        _retireWrite();
        _context = null;
        _error = 'identityUnavailable';
        _loading = false;
      });
    });
    unawaited(_read());
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant OrganizationGovernanceSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.sourceRef != widget.sourceRef) {
      ++_epoch;
      unawaited(_subscription.cancel());
      _context = null;
      _visitedPanes.clear();
      _loading = false;
      _retireWrite();
      _bind();
    }
  }

  Future<void> _read() async {
    if (_loading || _writing) return;
    final epoch = ++_epoch, port = widget.port, source = widget.sourceRef;
    setState(() {
      _loading = true;
      _context = null;
      _error = null;
    });
    try {
      final result = await port.read(source);
      if (mounted &&
          epoch == _epoch &&
          widget.port == port &&
          widget.sourceRef == source) {
        setState(() => _context = result);
        widget.onAuthorityRead?.call(result);
      }
    } catch (error) {
      if (mounted && epoch == _epoch) {
        final code = error is CommunityFailure ? error.code : 'dataInvalid';
        setState(() => _error = code);
        widget.onAuthorityUnavailable?.call(code);
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ++_epoch;
    unawaited(_subscription.cancel());
    super.dispose();
  }

  String t(String key) {
    if (key == 'title') return communitySettingsText(context, 'title');
    final copy = _copy[key];
    if (copy == null) throw StateError('Missing governance copy: $key');
    final locale = AppStrings.of(context).locale;
    return locale.languageCode == 'en'
        ? copy.$3
        : locale.scriptCode == 'Hant' ||
              locale.countryCode == 'TW' ||
              locale.countryCode == 'HK'
        ? copy.$2
        : copy.$1;
  }

  static String _newOperationId() {
    final random = math.Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  Future<void> _setActivation(bool active) async {
    final value = _context, port = widget.port, source = widget.sourceRef;
    if (value == null || _writing || !port.canActivate) return;
    final pending = _pendingIntent;
    final intent =
        pending != null && pending.active == active && pending.source == source
        ? pending
        : (
            active: active,
            id: _newOperationId(),
            revision: value.policyRevision,
            source: source,
          );
    final epoch = ++_writeEpoch;
    setState(() {
      _writing = true;
      _writeResult = null;
    });
    String result;
    try {
      final outcome = await port.setActivation(
        source,
        active: active,
        operationId: intent.id,
        expectedPolicyRevision: intent.revision,
      );
      result = outcome.state;
    } on CommunityFailure catch (error) {
      result = error.code;
    } on Object {
      result = 'outcomeUnknown';
    }
    // An invalidation or a new source already retired this write.
    if (!mounted || epoch != _writeEpoch) return;
    setState(() {
      _writing = false;
      // 'unavailable' means this attempt never left Host, which says nothing
      // about an earlier unknown write: it stays pending with its original id.
      _pendingIntent = switch (result) {
        'outcomeUnknown' => intent,
        'unavailable' => pending,
        _ => null,
      };
      _writeResult = result;
    });
    // Success, a stale revision or lost rights: show the server's view.
    if (const {
      'accepted',
      'duplicate',
      'conflict',
      'notAllowed',
    }.contains(result)) {
      await _read();
      if (mounted) setState(() => _writeResult = result);
    }
  }

  String? _decisionState(OrganizationGovernanceContext value, String action) {
    for (final d in value.rootControls) {
      if (d.key == action) return d.state.name;
    }
    return null;
  }

  Widget _leaderPanel(OrganizationGovernanceContext value) {
    final text = Theme.of(context).textTheme;
    final canActivate = _decisionState(value, 'activate') == 'allowed';
    final activated = _decisionState(value, 'delegate') == 'allowed';
    final writable = widget.port.canActivate && !_writing && !_loading;
    final unknown = _pendingIntent;
    final updated = value.membershipUpdatedAt;
    return Column(
      key: const Key('governance-leader-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value.role case final role?)
          Text(
            t('role.$role'),
            key: const Key('governance-role'),
            style: text.titleMedium,
          ),
        if (value.evidenceStale) ...[
          const SizedBox(height: 6),
          Text(
            updated == null
                ? t('stale')
                : t('staleSince').replaceAll(
                    '{time}',
                    '${MaterialLocalizations.of(context).formatShortDate(updated.toLocal())} '
                        '${TimeOfDay.fromDateTime(updated.toLocal()).format(context)}',
                  ),
            key: const Key('governance-stale'),
            style: text.bodySmall,
          ),
        ],
        // Entries follow the relay's decisions; the role above is display.
        if (widget.port.canActivate &&
            (canActivate || activated || unknown != null)) ...[
          const SizedBox(height: 10),
          Text(
            t(activated ? 'activeHint' : 'activateHint'),
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          if (!activated)
            FilledButton(
              key: const Key('governance-enable'),
              onPressed: writable && (canActivate || unknown?.active == true)
                  ? () => _setActivation(true)
                  : null,
              child: Text(t('activateMine')),
            )
          else
            OutlinedButton(
              key: const Key('governance-disable'),
              onPressed: writable ? () => _setActivation(false) : null,
              child: Text(t('revokeMine')),
            ),
        ],
        if (_writing) const LinearProgressIndicator(),
        if (_writeResult case final result?
            when result != 'accepted' && result != 'duplicate')
          Text(
            t(
              _copy.containsKey('write.$result')
                  ? 'write.$result'
                  : 'write.unavailable',
            ),
            key: const Key('governance-write-result'),
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _decision(OrganizationGovernanceDecision decision) => ListTile(
    key: ValueKey('governance-${decision.key}'),
    dense: true,
    title: Text(t(decision.key)),
    subtitle: Text(t(decision.state.name)),
    trailing: decision.reason == 'notGranted' ? Text(t('notGranted')) : null,
  );
  Future<void> _select(String id) async {
    if (mounted && id != _selected) setState(() => _selected = id);
  }

  @override
  Widget build(BuildContext context) {
    final panes = [...widget.panesBefore, ...widget.panesAfter];
    final extra = {for (final pane in panes) pane.id};
    // A pane the viewer lost (a permission changed) falls back to the first.
    final selected = _selected == 'permissions' || extra.contains(_selected)
        ? _selected
        : panes.isEmpty
        ? 'permissions'
        : panes.first.id;
    final selectedPane = panes.where((pane) => pane.id == selected).firstOrNull;
    _visitedPanes.add(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        communityWorkspaceManagementHeader(
          context,
          name: widget.name,
          onBack: widget.onBack,
          onRefresh: _loading || _writing ? () async {} : _read,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: OrganizationSettingsLayout(
            identity: 'official-fleet-settings',
            selected: selected,
            sections: [
              for (final pane in widget.panesBefore)
                (id: pane.id, icon: pane.icon, group: pane.group),
              (
                id: 'permissions',
                icon: StandardIconSemantic.adminPanelSettings,
                group: widget.permissionsGroup,
              ),
              for (final pane in widget.panesAfter)
                (id: pane.id, icon: pane.icon, group: pane.group),
            ],
            label: (key) =>
                key == 'title' || _copy.containsKey(key) && !extra.contains(key)
                ? t(key)
                : widget.label?.call(key) ?? t(key),
            onSelected: _select,
            content: IndexedStack(
              index: selectedPane == null
                  ? panes.length
                  : panes.indexOf(selectedPane),
              children: [
                for (final pane in panes)
                  if (pane.id == selected ||
                      pane.retainState && _visitedPanes.contains(pane.id))
                    SingleChildScrollView(
                      key: ValueKey('official-fleet-manage-${pane.id}'),
                      padding: const EdgeInsets.all(20),
                      child: pane.builder(_select),
                    )
                  else
                    SizedBox.shrink(key: ValueKey(pane.id)),
                SingleChildScrollView(
                  key: const Key('official-fleet-governance-content'),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_loading) const LinearProgressIndicator(),
                      if (_error != null)
                        Text(
                          t(switch (_error) {
                            'upgradeRequired' => 'oldHost',
                            'membershipEvidenceStale' => 'stale',
                            _ => 'readUnavailable',
                          }),
                          key: const Key('governance-unavailable'),
                        ),
                      if (_context case final value?) ...[
                        _leaderPanel(value),
                        Text(
                          t('permissions'),
                          key: const Key('governance-permissions'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(t('useOnly')),
                        for (final decision in value.capabilities)
                          _decision(decision),
                        const Divider(),
                        Text(
                          t('rootAuthority'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          t(value.rootProviderState),
                          key: const Key('governance-root-provider'),
                        ),
                        for (final decision in value.rootControls)
                          _decision(decision),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The permission copy, for the section's entry on the overview.
String organizationGovernanceText(BuildContext context, String key) {
  final copy = _copy[key]!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? copy.$3
      : locale.scriptCode == 'Hant' ||
            locale.countryCode == 'TW' ||
            locale.countryCode == 'HK'
      ? copy.$2
      : copy.$1;
}

const _copy = <String, (String, String, String)>{
  'permissions': ('我的权限', '我的權限', 'My permissions'),
  'useOnly': (
    '这里显示你当前可用的权限。',
    '這裡顯示你目前可用的權限。',
    'Your currently available permissions are shown here.',
  ),
  'rally.manage': ('发起召集', '發起召集', 'Start rallies'),
  'announcements.manage': ('维护公告', '維護公告', 'Manage announcements'),
  'audit.view': ('查看治理审计', '檢視治理稽核', 'View governance audit'),
  'organization.roles.manage': ('维护应用角色', '維護應用角色', 'Manage application roles'),
  'allowed': ('当前允许', '目前允許', 'Currently allowed'),
  'denied': ('当前不允许', '目前不允許', 'Currently denied'),
  'unavailable': ('当前无法确认', '目前無法確認', 'Currently unavailable'),
  'notGranted': ('尚未授予此能力', '尚未授予此能力', 'Not granted'),
  'rootAuthority': ('负责人管理', '負責人管理', 'Leader management'),
  'unconfigured': (
    'SCM 舰队等级验证尚未开放',
    'SCM 艦隊等級驗證尚未開放',
    'SCM fleet rank verification is not yet available',
  ),
  'role.leader': (
    '你是舰队负责人（RSI 等级 1）',
    '你是艦隊負責人（RSI 等級 1）',
    'You are a fleet leader (RSI rank 1)',
  ),
  'role.admin': (
    '你是舰队管理员（RSI 等级 2–3），当前权限见下方',
    '你是艦隊管理員（RSI 等級 2–3），目前權限見下方',
    'You are a fleet admin (RSI rank 2–3). Current permissions are shown below.',
  ),
  'role.editor': (
    '你是舰队编辑者（RSI 等级 4）',
    '你是艦隊編輯者（RSI 等級 4）',
    'You are a fleet editor (RSI rank 4)',
  ),
  'role.member': ('你是舰队成员', '你是艦隊成員', 'You are a fleet member'),
  'stale': (
    '你的成员资料超过 48 小时未更新，部分权限暂时无法确认。请在 SCM 个人页或舰队页点刷新后重试。',
    '你的成員資料超過 48 小時未更新，部分權限暫時無法確認。請在 SCM 個人頁或艦隊頁點重新整理後重試。',
    'Your member record is over 48 hours old, so some rights cannot be confirmed. Refresh it on your SCM profile or fleet page, then try again.',
  ),
  'staleSince': (
    '你的成员资料上次更新于 {time}，已超过 48 小时，部分权限暂时无法确认。请在 SCM 个人页或舰队页点刷新后重试。',
    '你的成員資料上次更新於 {time}，已超過 48 小時，部分權限暫時無法確認。請在 SCM 個人頁或艦隊頁點重新整理後重試。',
    'Your member record was last updated {time}, over 48 hours ago, so some rights cannot be confirmed. Refresh it on SCM, then try again.',
  ),
  'activateHint': (
    '每位负责人需要各自启用一次管理，才能委派权限、发起召集。',
    '每位負責人需要各自啟用一次管理，才能委派權限、發起召集。',
    'Each leader enables management once before delegating or starting rallies.',
  ),
  'activeHint': (
    '你已启用管理。撤销后，你本人委派出去的权限也会一并失效；其他负责人各自启用的管理不受影响。',
    '你已啟用管理。撤銷後，你本人委派出去的權限也會一併失效；其他負責人各自啟用的管理不受影響。',
    'Management is enabled for you. Revoking also ends the permissions you delegated; other leaders keep their own.',
  ),
  'activateMine': ('启用管理', '啟用管理', 'Enable management'),
  'revokeMine': ('撤销我的管理', '撤銷我的管理', 'Revoke my management'),
  'write.conflict': (
    '权限状态刚刚变化，已刷新，请确认后再操作。',
    '權限狀態剛剛變化，已重新整理，請確認後再操作。',
    'Permissions just changed and were refreshed. Check and try again.',
  ),
  'write.notAllowed': (
    '当前不能执行这项操作，已刷新权限。',
    '目前不能執行這項操作，已重新整理權限。',
    'This is not allowed right now. Permissions were refreshed.',
  ),
  'write.outcomeUnknown': (
    '没有收到确认结果，请稍后再点一次（不会重复执行）。',
    '沒有收到確認結果，請稍後再點一次（不會重複執行）。',
    'No confirmation arrived. Try again later; it will not run twice.',
  ),
  'write.identityUnavailable': (
    '登录状态需要恢复，请稍后重试。',
    '登入狀態需要恢復，請稍後重試。',
    'Sign-in needs to recover. Try again later.',
  ),
  'write.unavailable': (
    '暂时无法完成，请稍后重试。',
    '暫時無法完成，請稍後重試。',
    'Not available right now. Try again later.',
  ),
  'observed': (
    '已读取根资格状态；各项控制分别核验',
    '已讀取根資格狀態；各項控制分別核驗',
    'Root qualification observed; each control is evaluated separately',
  ),
  'activate': ('启用管理', '啟用管理', 'Enable management'),
  'recover': ('恢复管理', '恢復管理', 'Recover management'),
  'delegate': ('委派权限', '委派權限', 'Delegate permissions'),
  'oldHost': (
    '当前版本暂不支持读取权限状态，请更新客户端。',
    '目前版本暫不支援讀取權限狀態，請更新用戶端。',
    'This version cannot read permission status. Please update the client.',
  ),
  'readUnavailable': (
    '权限状态暂不可用，请手动刷新。',
    '權限狀態暫不可用，請手動重新整理。',
    'Permission status is unavailable. Refresh to try again.',
  ),
};
