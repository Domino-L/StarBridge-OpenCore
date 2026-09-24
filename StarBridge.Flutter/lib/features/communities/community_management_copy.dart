import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'community_workspace_copy.dart';

const communityManagementCopy = <String, (String, String, String)>{
  'title': ('申请与邀请', '申請與邀請', 'Applications and invites'),
  'applications': ('加入申请', '加入申請', 'Applications'),
  'invites': ('邀请码', '邀請碼', 'Invite codes'),
  'approve': ('批准加入', '批准加入', 'Approve'),
  'decline': ('拒绝申请', '拒絕申請', 'Decline'),
  'generateInvite': ('生成邀请码', '產生邀請碼', 'Generate invite'),
  'revokeInvite': ('撤销邀请', '撤銷邀請', 'Revoke invite'),
  'approveConfirm': (
    '批准后，申请人将加入此组织。',
    '批准後，申請人將加入此組織。',
    'The applicant will join this organization.',
  ),
  'declineConfirm': (
    '拒绝后，此申请将从待审批列表移除。',
    '拒絕後，此申請將從待審核清單移除。',
    'The application will be removed from the pending list.',
  ),
  'generateInviteConfirm': (
    '新码将替换你在此组织的旧有效码，旧码会立即失效。',
    '新碼將取代你在此組織的舊有效碼，舊碼會立即失效。',
    'This replaces your active invite in this organization. Your old code will stop working.',
  ),
  'revokeInviteConfirm': (
    '撤销后，将无法再使用此码加入组织。',
    '撤銷後，將無法再使用此碼加入組織。',
    'This code will no longer allow anyone to join.',
  ),
  'cancel': ('取消', '取消', 'Cancel'),
  'close': ('完成', '完成', 'Done'),
  'emptyApplications': (
    '暂时没有待处理的加入申请。',
    '目前沒有待處理的加入申請。',
    'No pending applications.',
  ),
  'emptyInvites': ('暂无邀请码。', '暫無邀請碼。', 'No invite codes yet.'),
  'days': ('有效期（天）', '有效期（天）', 'Valid for (days)'),
  'uses': ('使用次数', '使用次數', 'Maximum uses'),
  'unlimited': ('不限次数', '不限次數', 'Unlimited'),
  'own': ('你的邀请', '你的邀請', 'Your invite'),
  'currentInvite': ('我的当前邀请码', '我的目前邀請碼', 'My current invite'),
  'inviteList': ('邀请记录', '邀請紀錄', 'Invite history'),
  'noCurrentInvite': (
    '你在此组织暂无有效邀请码。',
    '你在此組織暫無有效邀請碼。',
    'You have no active invite in this organization.',
  ),
  'currentInviteUnavailable': (
    '暂时无法确认你的当前邀请码，请刷新重试。',
    '暫時無法確認你的目前邀請碼，請重新整理重試。',
    'Your current invite could not be confirmed. Refresh to try again.',
  ),
  'remainingDays': ('剩余 {n} 天', '剩餘 {n} 天', '{n} days remaining'),
  'remainingHours': ('剩余 {n} 小时', '剩餘 {n} 小時', '{n} hours remaining'),
  'remainingMinutes': ('剩余 {n} 分钟', '剩餘 {n} 分鐘', '{n} minutes remaining'),
  'remainingSoon': ('不足 1 分钟', '不足 1 分鐘', 'Less than a minute remaining'),
  'Active': ('有效', '有效', 'Active'),
  'Revoked': ('已撤销', '已撤銷', 'Revoked'),
  'Expired': ('已过期', '已過期', 'Expired'),
  'Exhausted': ('次数已用完', '次數已用完', 'Fully used'),
  'Unavailable': ('不可用', '無法使用', 'Unavailable'),
  'created': ('创建时间', '建立時間', 'Created'),
  'expires': ('到期时间', '到期時間', 'Expires'),
  'used': ('已使用', '已使用', 'Used'),
  'accepted': ('操作已完成。', '操作已完成。', 'Action completed.'),
  'readOnly': (
    '你可以查看申请，但当前没有审批权限。',
    '你可以查看申請，但目前沒有審核權限。',
    'You can view applications, but cannot approve or decline them.',
  ),
  'unknown': (
    '操作结果暂时无法确认。请先刷新查看，不要重复提交。',
    '操作結果暫時無法確認。請先重新整理查看，勿重複送出。',
    'The outcome is not yet confirmed. Refresh before submitting again.',
  ),
  'retryWarning': (
    '上次操作可能已生效。请核对最新列表后，再决定是否继续。',
    '上次操作可能已生效。請核對最新清單後，再決定是否繼續。',
    'The previous action may have completed. Check the refreshed list before continuing.',
  ),
  'notAllowed': (
    '当前没有此操作的权限，请刷新或联系组织负责人。',
    '目前沒有此操作的權限，請重新整理或聯絡組織負責人。',
    'This action is not permitted. Refresh or contact the organization owner.',
  ),
  'unavailable': (
    '暂时无法读取管理资料，请重试。',
    '暫時無法讀取管理資料，請重試。',
    'Management details are unavailable. Try again.',
  ),
  'busy': ('正在处理，请稍候。', '正在處理，請稍候。', 'An action is in progress. Please wait.'),
};

String managementText(BuildContext context, String key) {
  final value = communityManagementCopy[key];
  if (value == null) return workspaceText(context, key);
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}

String managementRemainingText(BuildContext context, Duration remaining) {
  if (remaining <= Duration.zero) return managementText(context, 'Expired');
  final (key, count) = remaining.inDays >= 1
      ? ('remainingDays', remaining.inDays)
      : remaining.inHours >= 1
      ? ('remainingHours', remaining.inHours)
      : remaining.inMinutes >= 1
      ? ('remainingMinutes', remaining.inMinutes)
      : ('remainingSoon', 0);
  return managementText(context, key).replaceAll('{n}', '$count');
}
