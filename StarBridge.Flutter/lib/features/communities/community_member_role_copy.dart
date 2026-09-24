import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'community_roles_copy.dart';

const communityMemberRoleCopy = <String, (String, String, String)>{
  'notAllowed': (
    '当前无法更改此成员身份，请关闭后重新打开。',
    '目前無法變更此成員身分，請關閉後重新開啟。',
    'You cannot change this member’s role now. Close and reopen this dialog.',
  ),
  'refreshRequired': (
    '成员资料已过期，请返回成员列表重新打开。',
    '成員資料已過期，請返回成員清單重新開啟。',
    'These member details expired. Open the member again from the list.',
  ),
  'dataInvalid': (
    '成员身份资料不完整，请重新读取。',
    '成員身分資料不完整，請重新讀取。',
    'The member’s role details are incomplete. Reload to retry.',
  ),
  'unavailable': (
    '暂时无法读取成员身份，请重试。',
    '暫時無法讀取成員身分，請重試。',
    'The member’s role is unavailable. Try again.',
  ),
  'assignRole': ('更改身份', '變更身分', 'Change role'),
  'baseMember': ('基础成员', '基礎成員', 'Base member'),
  'currentRole': ('当前身份', '目前身分', 'Current role'),
  'chooseRole': ('选择新身份', '選擇新身分', 'Choose a role'),
  'assignmentHelp': (
    '保存后，新身份权限立即生效，并写入组织日志。',
    '儲存後，新身分權限立即生效，並寫入組織日誌。',
    'Saving applies the new permissions immediately and records the change in the organization log.',
  ),
  'confirmAssignment': ('确认更改身份', '確認變更身分', 'Confirm role change'),
  'assignmentProtected': (
    '此成员的身份不能在这里更改。',
    '此成員的身分不能在這裡變更。',
    'This member’s role cannot be changed here.',
  ),
  'assignmentChanged': (
    '成员身份已有新的变更，已显示最新结果。',
    '成員身分已有新的變更，已顯示最新結果。',
    'The member’s role changed again. The latest role is shown.',
  ),
  'assignmentRefreshFailed': (
    '更改已保存，但最新身份未能读取。请重新读取，不要重复提交。',
    '變更已儲存，但未能讀取最新身分。請重新讀取，不要重複提交。',
    'The change was saved, but the latest role could not be read. Reload instead of submitting again.',
  ),
  'reloadAssignment': ('读取最新身份', '讀取最新身分', 'Reload role'),
  'reloadAssignmentHelp': (
    '重新读取会替换当前选择；已提交的更改不会撤销。',
    '重新讀取會取代目前選擇；已提交的變更不會撤銷。',
    'Reloading replaces your selection. Submitted changes will not be undone.',
  ),
  'leaveAssignment': ('放弃当前选择？', '捨棄目前選擇？', 'Discard this selection?'),
  'assignmentUnavailable': (
    '暂时无法读取成员身份，请重试。',
    '暫時無法讀取成員身分，請重試。',
    'The member’s role is unavailable. Try again.',
  ),
  'outcomeUnknown': (
    '未能确认更改结果，请先读取最新身份。',
    '未能確認變更結果，請先讀取最新身分。',
    'The result is uncertain. Reload the latest role first.',
  ),
  'conflict': (
    '确认期间身份或权限发生变化，请读取最新身份后重新选择。',
    '確認期間身分或權限已變更，請讀取最新身分後重新選擇。',
    'Roles or permissions changed during confirmation. Reload and select again.',
  ),
  'retryAssignmentHelp': (
    '上次更改可能已生效。确认仍要应用当前选择吗？',
    '上次變更可能已生效。確認仍要套用目前選擇嗎？',
    'The previous change may already have applied. Apply this selection anyway?',
  ),
  'close': ('关闭', '關閉', 'Close'),
};
String memberRoleText(BuildContext context, String key) {
  final value = communityMemberRoleCopy[key];
  if (value == null) return rolesText(context, key);
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
