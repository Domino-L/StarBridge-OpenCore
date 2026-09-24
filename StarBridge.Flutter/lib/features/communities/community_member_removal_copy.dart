import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityMemberRemovalCopy = <String, (String, String, String)>{
  'remove': ('移除成员', '移除成員', 'Remove member'),
  'cancel': ('取消', '取消', 'Cancel'),
  'close': ('关闭', '關閉', 'Close'),
  'reload': ('重新读取', '重新讀取', 'Reload'),
  'retry': ('确认再次移除', '確認再次移除', 'Confirm removal retry'),
  'consequence': (
    '该成员将失去此组织的同步与内部资料访问权限，操作会写入组织日志。不影响其加入的其他组织。',
    '該成員將失去此組織的同步與內部資料存取權限，操作會寫入組織日誌。不影響其加入的其他組織。',
    'This removes access to this organization’s sync and internal data and records the action in its log. Other memberships are not affected.',
  ),
  'protected': (
    '当前不能移除此成员。',
    '目前不能移除此成員。',
    'This member cannot be removed now.',
  ),
  'outcomeUnknown': (
    '尚未确认移除结果。请先重新读取；再次移除需要你明确确认。',
    '尚未確認移除結果。請先重新讀取；再次移除需要你明確確認。',
    'Removal is not confirmed. Reload first; another attempt needs your explicit confirmation.',
  ),
  'retryHelp': (
    '上次操作可能已生效。请核对最新成员资料，再决定是否再次移除。',
    '上次操作可能已生效。請核對最新成員資料，再決定是否再次移除。',
    'The previous attempt may have succeeded. Check the latest member details before trying again.',
  ),
  'conflict': (
    '成员资料或权限已变化，或旧关联资料无法区分。请重新读取后再试。',
    '成員資料或權限已變更，或舊關聯資料無法區分。請重新讀取後再試。',
    'Member details or permissions changed, or older linked data is ambiguous. Reload before retrying.',
  ),
  'identityUnavailable': (
    '账号或组织已切换，请关闭后重新打开。',
    '帳號或組織已切換，請關閉後重新開啟。',
    'The account or organization changed. Close and reopen this dialog.',
  ),
  'notAllowed': (
    '当前没有移除此成员的权限，请返回成员列表。',
    '目前沒有移除此成員的權限，請返回成員清單。',
    'You cannot remove this member now. Return to the member list.',
  ),
  'refreshRequired': (
    '成员可能已离开或资料已过期，请关闭并刷新成员列表。',
    '成員可能已離開或資料已過期，請關閉並重新整理成員清單。',
    'The member may have left or these details expired. Close and refresh the member list.',
  ),
  'unavailable': (
    '暂时无法读取成员资料，请重试。',
    '暫時無法讀取成員資料，請重試。',
    'Member details are unavailable. Try again.',
  ),
  'dataInvalid': (
    '成员资料不完整，请重新读取。',
    '成員資料不完整，請重新讀取。',
    'Member details are incomplete. Reload to retry.',
  ),
  'busy': (
    '另一项组织操作正在处理，请稍后重新读取。',
    '另一項組織操作正在處理，請稍後重新讀取。',
    'Another organization action is running. Reload shortly.',
  ),
  'invalidDraft': (
    '移除请求已失效，请关闭后重新打开。',
    '移除請求已失效，請關閉後重新開啟。',
    'This removal request is invalid. Close and reopen this dialog.',
  ),
  'requestChanged': (
    '请求内容已变化，请关闭后重新打开。',
    '請求內容已變更，請關閉後重新開啟。',
    'The request changed. Close and reopen this dialog.',
  ),
};
String memberRemovalText(BuildContext context, String key) {
  final value =
      communityMemberRemovalCopy[key] ??
      communityMemberRemovalCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
