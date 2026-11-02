import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

String fleetGovernanceText(BuildContext context, String key) {
  final value = _copy[key] ?? _copy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode != 'zh'
      ? value.$3
      : locale.scriptCode == 'Hant' ||
            locale.countryCode == 'TW' ||
            locale.countryCode == 'HK'
      ? value.$2
      : value.$1;
}

const _copy = <String, (String, String, String)>{
  'ranks': ('星级权限', '星級權限', 'Star permissions'),
  'roles': ('成员角色', '成員角色', 'Member roles'),
  'audit': ('操作记录', '操作記錄', 'Activity record'),
  'announcements.manage': ('公告', '公告', 'Announcements'),
  'rally.manage': ('发起召集', '發起召集', 'Start rallies'),
  'audit.view': ('操作记录', '操作記錄', 'Activity record'),
  'fixed': ('全部权限（固定）', '全部權限（固定）', 'All permissions (fixed)'),
  'closed': (
    '星级权限与召集授权尚未开放。',
    '星級權限與召集授權尚未開放。',
    'Star permission changes and rally grants are not yet open.',
  ),
  'additive': (
    '角色只会增加权限，不会减少成员星级已有的权限。未勾选表示不额外授予。',
    '角色只會增加權限，不會減少成員星級已有的權限。未勾選表示不額外授予。',
    'Roles only add permissions. They never remove star permissions. Unchecked means no extra grant.',
  ),
  'extra': ('额外授予', '額外授予', 'Additional grants'),
  'roleChange': (
    '修改角色权限后，原有的角色授权会失效，需要重新设置成员角色。星级权限不受影响。',
    '修改角色權限後，原有的角色授權會失效，需要重新設定成員角色。星級權限不受影響。',
    'Changing role permissions invalidates existing role grants. Set member roles again. Star permissions are unaffected.',
  ),
  'permissionsSaved': (
    '角色权限已保存，名称修改结果见下方。',
    '角色權限已儲存，名稱修改結果見下方。',
    'Role permissions were saved. The name change result is shown below.',
  ),
  'save': ('保存', '儲存', 'Save'),
  'discard': ('放弃修改', '放棄修改', 'Discard changes'),
  'retry': ('重试原操作', '重試原操作', 'Retry original operation'),
  'refresh': ('重新读取', '重新讀取', 'Read again'),
  'load': ('加载更多', '載入更多', 'Load more'),
  'read': ('查看角色', '檢視角色', 'View roles'),
  'assign': ('设置角色', '設定角色', 'Set role'),
  'revoke': ('撤销', '撤銷', 'Revoke'),
  'create': ('新建角色', '新增角色', 'New role'),
  'edit': ('编辑', '編輯', 'Edit'),
  'name': ('角色名称', '角色名稱', 'Role name'),
  'members': ('成员', '成員', 'Members'),
  'fleet': ('主舰队', '主艦隊', 'Main fleet'),
  'templates': ('角色列表', '角色清單', 'Roles'),
  'onDemand': (
    '点“查看角色”可以看这位成员已有的角色。',
    '點「檢視角色」可以看這位成員已有的角色。',
    'Choose "View roles" to see the roles this member already has.',
  ),
  'none': ('无额外角色', '無額外角色', 'No extra role'),
  'unnamed': ('未命名角色', '未命名角色', 'Unnamed role'),
  'member': ('成员资料不可用', '成員資料無法使用', 'Member unavailable'),
  'empty': ('暂无操作记录。', '暫無操作記錄。', 'No activity yet.'),
  'accepted': ('已保存。', '已儲存。', 'Saved.'),
  'duplicate': ('已保存。', '已儲存。', 'Saved.'),
  'conflict': (
    '权限状态刚刚变化，已重新读取。请确认后再操作。',
    '權限狀態剛剛變化，已重新讀取。請確認後再操作。',
    'Permissions changed and were reread. Check before trying again.',
  ),
  'notAllowed': (
    '当前不能执行此操作，已重新读取权限。',
    '目前不能執行此操作，已重新讀取權限。',
    'This is no longer allowed. Permissions were reread.',
  ),
  'operationOutcomeUnknown': (
    '尚未收到确认，请重试原操作，重试不会重复执行。也可以先关闭，之后再打开这里继续确认。',
    '尚未收到確認，請重試原操作，重試不會重複執行。也可以先關閉，之後再開啟這裡繼續確認。',
    'No confirmation arrived. Retry the original operation; it will not run twice. You can also close this and come back here to continue.',
  ),
  'identityUnavailable': (
    '登录状态已变化，请重新打开设置。',
    '登入狀態已變化，請重新開啟設定。',
    'Sign-in changed. Reopen settings.',
  ),
  'unavailable': (
    '暂时无法完成，请稍后重试。',
    '暫時無法完成，請稍後重試。',
    'Unavailable for now. Try again later.',
  ),
  'other': ('其他管理操作', '其他管理操作', 'Other management action'),
  'ranks.permissions': ('修改星级权限', '修改星級權限', 'Changed star permissions'),
  'roles.metadata': ('修改角色名称', '修改角色名稱', 'Changed role details'),
  'roles.permissions': ('修改角色权限', '修改角色權限', 'Changed role permissions'),
  'grant.assign': ('设置成员角色', '設定成員角色', 'Assigned member role'),
  'grant.revoke': ('撤销成员角色', '撤銷成員角色', 'Revoked member role'),
  'root.activate': ('启用管理', '啟用管理', 'Enabled management'),
  'root.recover': ('撤销管理', '撤銷管理', 'Revoked management'),
};

String fleetGovernanceAuditKind(BuildContext context, Object? kind) =>
    fleetGovernanceText(
      context,
      _copy.containsKey(kind) &&
              const {
                'ranks.permissions',
                'roles.metadata',
                'roles.permissions',
                'grant.assign',
                'grant.revoke',
                'root.activate',
                'root.recover',
              }.contains(kind)
          ? kind as String
          : 'other',
    );
