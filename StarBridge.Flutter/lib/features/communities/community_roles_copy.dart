import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'community_profile_copy.dart';

const communityRolesCopy = <String, (String, String, String)>{
  'saving': ('正在保存并读取最新角色…', '正在儲存並讀取最新角色…', 'Saving and refreshing roles…'),
  'loading': ('正在读取角色…', '正在讀取角色…', 'Loading roles…'),
  'unavailable': (
    '角色暂时无法读取，请重试。',
    '角色暫時無法讀取，請重試。',
    'Roles are unavailable. Try again.',
  ),
  'conflict': (
    '组织资料已更新。当前草稿仍保留，请读取最新角色后再编辑。',
    '組織資料已更新。目前草稿仍保留，請讀取最新角色後再編輯。',
    'Organization data changed. Your draft is preserved. Reload roles before editing.',
  ),
  'outcomeUnknown': (
    '暂时无法确认保存结果，请先读取最新角色并核对。',
    '暫時無法確認儲存結果，請先讀取最新角色並核對。',
    'Save result is unconfirmed. Reload and check the latest roles first.',
  ),
  'refreshAfterSave': (
    '服务器已确认保存，最新角色尚未读回。请重新读取。',
    '伺服器已確認儲存，最新角色尚未讀回。請重新讀取。',
    'The server confirmed the save. Reload to view the latest roles.',
  ),
  'refreshRequired': (
    '编辑已过期，请关闭后重新打开角色。',
    '編輯已過期，請關閉後重新開啟角色。',
    'This editor expired. Close and reopen roles.',
  ),
  'rolesTitle': ('成员角色', '成員角色', 'Member roles'),
  'rolesHelp': (
    '配置角色的名称、颜色与权限。保存后生效；成员分配在成员页管理。',
    '設定角色的名稱、顏色與權限。儲存後生效；成員分配在成員頁管理。',
    'Set role names, colors and permissions. Changes apply after saving; member assignments are managed separately.',
  ),
  'newRole': ('新增角色', '新增角色', 'New role'),
  'newName': ('自定义角色', '自訂角色', 'Custom role'),
  'copyRole': ('复制角色', '複製角色', 'Duplicate role'),
  'copySuffix': ('副本', '副本', 'copy'),
  'deleteRole': ('删除角色', '刪除角色', 'Delete role'),
  'deleteHelp': (
    '保存后，该角色的成员将回到基础成员权限。',
    '儲存後，此角色的成員將回到基礎成員權限。',
    'After saving, members assigned this role will return to base member permissions.',
  ),
  'roleName': ('角色名称', '角色名稱', 'Role name'),
  'roleDescription': ('角色说明', '角色說明', 'Role description'),
  'roleColor': ('身份颜色', '身分顏色', 'Role color'),
  'systemRole': ('系统角色', '系統角色', 'System role'),
  'memberCount': ('成员数', '成員數', 'Members'),
  'ownerHelp': (
    '负责人默认拥有全部权限，不能在这里关闭。',
    '負責人預設擁有全部權限，不能在此關閉。',
    'The owner has all permissions; they cannot be disabled here.',
  ),
  'profile': ('组织资料', '組織資料', 'Organization profile'),
  'members': ('成员加入与管理', '成員加入與管理', 'Membership'),
  'audit': ('操作记录', '操作記錄', 'Activity record'),
  'fleet.profile.edit': ('编辑组织资料', '編輯組織資料', 'Edit organization profile'),
  'announcements.manage': ('维护组织公告', '維護組織公告', 'Manage announcements'),
  'fleet.banner.edit': (
    '可编辑横幅和背景',
    '可編輯橫幅和背景',
    'Can edit banners and backgrounds',
  ),
  'fleet.avatar.edit': ('更换组织标志', '更換組織標誌', 'Change organization logo'),
  'members.review': ('审核加入申请', '審核加入申請', 'Review applications'),
  'members.remove': ('移除成员', '移除成員', 'Remove members'),
  'audit.view': ('查看组织完整日志', '查看組織完整紀錄', 'View organization logs'),
  'audit.delete': ('删除日志记录', '刪除紀錄', 'Delete log entries'),
  'rolesReload': (
    '重新读取会替换当前草稿。上次提交可能已经保存，请先核对最新结果。',
    '重新讀取會取代目前草稿。上次提交可能已儲存，請先核對最新結果。',
    'Reloading replaces this draft. The last submission may have saved; check the latest result first.',
  ),
  'rolesRetry': ('上次保存结果未确认', '上次儲存結果未確認', 'Last save remains unconfirmed'),
  'rolesRetryHelp': (
    '当前版本尚未变化。再次保存可能与上次提交冲突，确定继续？',
    '目前版本尚未變更。再次儲存可能與上次提交衝突，確定繼續？',
    'The version has not changed. Saving again may conflict with the earlier submission. Continue?',
  ),
  'rolesLeave': ('离开角色编辑？', '離開角色編輯？', 'Leave role editing?'),
  'rolesLeaveHelp': (
    '未保存的草稿将被放弃；已提交的操作不会撤销。',
    '未儲存的草稿將被捨棄；已提交的操作不會撤銷。',
    'Unsaved drafts will be discarded. Submitted operations will not be undone.',
  ),
  'leaveRoles': ('放弃草稿并离开', '捨棄草稿並離開', 'Discard draft and leave'),
  'reloadRoles': ('读取最新角色', '讀取最新角色', 'Reload roles'),
};

String rolesText(BuildContext context, String key) {
  final value = communityRolesCopy[key];
  if (value == null) return profileText(context, key);
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
