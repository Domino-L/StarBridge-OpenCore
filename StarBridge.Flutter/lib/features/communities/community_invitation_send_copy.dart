import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const invitationSendCopy = <String, (String, String, String)>{
  'sendTitle': ('邀请加入组织', '邀請加入組織', 'Invite to organization'),
  'send': ('发送邀请', '傳送邀請', 'Send invitation'),
  'sendTo': ('发送给：', '傳送給：', 'Send to:'),
  'sendInfo': (
    '选择要邀请对方加入的组织。邀请有效期为 7 天，可使用 1 次。',
    '選擇要邀請對方加入的組織。邀請有效期限為 7 天，可使用 1 次。',
    'Choose an organization. The invitation is valid for 7 days and can be used once.',
  ),
  'noOrganizations': (
    '尚未加入组织。加入后可在这里发送邀请。',
    '尚未加入組織。加入後可在這裡傳送邀請。',
    'Join an organization before sending an invitation.',
  ),
  'reloadOrganizations': ('重新读取组织', '重新讀取組織', 'Reload organizations'),
  'moreOrganizations': ('更多组织', '更多組織', 'More organizations'),
  'recordsHint': (
    '可在组织页的“邀请发送记录”中继续处理。',
    '可在組織頁的「邀請傳送記錄」中繼續處理。',
    'Continue from Invitation delivery on the Organizations page.',
  ),
  'records': ('邀请发送记录', '邀請傳送記錄', 'Invitation delivery'),
  'intro': (
    '查看组织邀请的发送结果，或继续未完成的发送。打开此页不会自动发送。',
    '查看組織邀請的傳送結果，或繼續未完成的傳送。開啟此頁不會自動傳送。',
    'Review organization invites or continue unfinished deliveries. Opening this page does not send anything.',
  ),
  'empty': ('暂无邀请发送记录。', '暫無邀請傳送記錄。', 'No invitation deliveries yet.'),
  'refresh': ('刷新记录', '重新整理記錄', 'Refresh records'),
  'close': ('关闭', '關閉', 'Close'),
  'check': ('查看发送结果', '查看傳送結果', 'Check delivery'),
  'continue': ('继续发送', '繼續傳送', 'Continue sending'),
  'retry': ('重试原邀请', '重試原邀請', 'Retry original invite'),
  'retryTitle': ('重试这条邀请？', '重試這則邀請？', 'Retry this invite?'),
  'retryBody': (
    '会先确认之前的发送结果，再尝试发送原邀请。不会生成新邀请码，也不会更换接收方。',
    '會先確認先前的傳送結果，再嘗試傳送原邀請。不會產生新邀請碼，也不會更換接收方。',
    'Check the previous delivery first, then try sending the original invite. The invite code and recipient will not change.',
  ),
  'cancel': ('暂不重试', '暫不重試', 'Not now'),
  'private': ('私信', '私訊', 'Direct message'),
  'room': ('房间', '房間', 'Room'),
  'organization': ('组织', '組織', 'Organization'),
  'recipient': ('原接收方', '原接收方', 'Original recipient'),
  'prepared': ('等待生成', '等待產生', 'Ready to generate'),
  'generating': ('生成结果待确认', '產生結果待確認', 'Generation unconfirmed'),
  'ready': ('已生成，尚未发送', '已產生，尚未傳送', 'Generated, not sent'),
  'sending': ('发送结果待确认', '傳送結果待確認', 'Delivery unconfirmed'),
  'sent': ('已发送', '已傳送', 'Sent'),
  'pending': (
    '尚未发送，可继续处理。',
    '尚未傳送，可繼續處理。',
    'Not sent yet. You can continue this delivery.',
  ),
  'unknown': (
    '尚未确认发送结果，请查看结果后再决定是否重试。',
    '尚未確認傳送結果，請查看結果後再決定是否重試。',
    'Delivery is not confirmed. Check the result before retrying.',
  ),
  'rejected': (
    '此次操作未获准，请检查组织权限及接收方状态。',
    '此次操作未獲准，請檢查組織權限及接收方狀態。',
    'This action was not allowed. Check organization permissions and recipient access.',
  ),
  'localRecoveryUnavailable': (
    '无法读取或保存本机发送记录。请检查本机存储；原记录不会被清空。',
    '無法讀取或儲存本機傳送記錄。請檢查本機儲存空間；原記錄不會被清空。',
    'Local delivery records could not be read or saved. Check local storage; existing records have not been cleared.',
  ),
  'identityUnavailable': (
    '账号状态已变化，请关闭后重新打开。',
    '帳號狀態已變更，請關閉後重新開啟。',
    'Your account changed. Close and reopen this page.',
  ),
  'unavailable': (
    '暂时无法读取，请检查连接后刷新记录。',
    '暫時無法讀取，請檢查連線後重新整理記錄。',
    'Records are unavailable. Check your connection and refresh.',
  ),
};

String invitationSendText(BuildContext context, String key) {
  final value = invitationSendCopy[key] ?? invitationSendCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
