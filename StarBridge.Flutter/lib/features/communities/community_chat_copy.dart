import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityChatCopy = <String, (String, String, String)>{
  'sharePreset': ('分享浮层预设', '分享浮層預設', 'Share overlay preset'),
  'importPreset': ('导入为新预设', '匯入為新預設', 'Import as new preset'),
  'shareHint': (
    '选择本机已保存的预设，添加到草稿后再发送。',
    '選擇本機已儲存的預設，加入草稿後再傳送。',
    'Choose a saved preset to attach to your draft before sending.',
  ),
  'importHint': (
    '新增到本机，不覆盖或切换当前预设。外观仍需拥有使用资格。',
    '新增至本機，不覆寫或切換目前預設。外觀仍需擁有使用資格。',
    'Adds a local preset without replacing or activating one. Appearance access is still required.',
  ),
  'presetReadFailed': (
    '暂时无法读取预设，请重试。',
    '暫時無法讀取預設，請重試。',
    'Could not read presets. Try again.',
  ),
  'presetChanged': (
    '预设已发生变化，请重新读取后再选择。',
    '預設已變更，請重新讀取後再選擇。',
    'Presets changed. Reload them before continuing.',
  ),
  'presetInvalid': (
    '此预设无法导入，请联系发送者重新分享。',
    '此預設無法匯入，請聯絡傳送者重新分享。',
    'This preset cannot be imported. Ask the sender to share it again.',
  ),
  'presetImportUnknown': (
    '尚未确认是否导入成功，请先到浮层设置检查，避免重复导入。',
    '尚未確認是否匯入成功，請先至浮層設定檢查，避免重複匯入。',
    'Import is unconfirmed. Check overlay settings before importing again.',
  ),
  'imported': ('已新增预设', '已新增預設', 'Preset added'),
  'noPresets': (
    '没有可分享的预设，请先在浮层设置中创建。',
    '沒有可分享的預設，請先在浮層設定中建立。',
    'No presets to share. Create one in overlay settings first.',
  ),
  'close': ('关闭', '關閉', 'Close'),
  'title': ('组织聊天', '組織聊天', 'Organization chat'),
  'back': ('返回组织资料', '返回組織資料', 'Organization details'),
  'refresh': ('刷新消息', '重新整理訊息', 'Refresh messages'),
  'older': ('查看更早消息', '查看更早訊息', 'Older messages'),
  'latest': ('回到最新', '回到最新', 'Back to latest'),
  'empty': (
    '还没有消息，可以在这里开始交流。',
    '還沒有訊息，可以在這裡開始交流。',
    'No messages yet. Start a conversation here.',
  ),
  'draft': ('输入消息', '輸入訊息', 'Write a message'),
  'send': ('发送', '傳送', 'Send'),
  'keys': (
    'Enter 发送 · Shift+Enter 换行',
    'Enter 傳送 · Shift+Enter 換行',
    'Enter to send · Shift+Enter for a new line',
  ),
  'retry': ('重试', '重試', 'Retry'),
  'readFailed': (
    '已读状态未能确认，未读提醒暂时保留。',
    '已讀狀態未能確認，未讀提醒暫時保留。',
    'Could not confirm read status. Unread reminders are unchanged.',
  ),
  'unavailable': (
    '暂时无法读取消息，请刷新重试。',
    '暫時無法讀取訊息，請重新整理。',
    'Messages are unavailable. Refresh to retry.',
  ),
  'dataInvalid': (
    '内容未能完整读取或超出限制，请检查后重试。',
    '內容未能完整讀取或超出限制，請檢查後重試。',
    'Content is incomplete or exceeds its limit. Check and retry.',
  ),
  'rateLimited': (
    '发送过于频繁，请稍后重试。草稿已保留。',
    '傳送過於頻繁，請稍後重試。草稿已保留。',
    'Sending too quickly. Try again shortly. Your draft is kept.',
  ),
  'busy': (
    '正在处理上一次操作，请稍后重试。',
    '正在處理上一次操作，請稍後重試。',
    'Another action is in progress. Try again shortly.',
  ),
  'outcomeUnknown': (
    '尚未确认是否发送成功。草稿已保留，请刷新消息核对，避免重复发送。',
    '尚未確認是否傳送成功。草稿已保留，請重新整理訊息核對，避免重複傳送。',
    'Sending is not yet confirmed. Your draft is kept. Refresh messages to check before sending again.',
  ),
  'intentConflict': (
    '发送内容已变化，请核对草稿后重试。',
    '傳送內容已變更，請核對草稿後重試。',
    'The message content changed. Check your draft and retry.',
  ),
  'notAllowed': (
    '你已无法访问此组织，请返回组织列表刷新。',
    '你已無法存取此組織，請返回組織清單重新整理。',
    'This organization is no longer accessible. Refresh the organization list.',
  ),
  'notFound': (
    '此组织或消息已不可用，请返回组织列表刷新。',
    '此組織或訊息已無法使用，請返回組織清單重新整理。',
    'The organization or message is unavailable. Refresh the organization list.',
  ),
  'identityUnavailable': (
    '账号状态已变化，请重新打开组织。',
    '帳號狀態已變更，請重新開啟組織。',
    'Your account changed. Open the organization again.',
  ),
  'refreshRequired': (
    '当前会话已过期，请返回组织列表刷新后重新打开。',
    '目前對話已過期，請返回組織清單重新整理後再次開啟。',
    'This conversation expired. Refresh the organization list and open it again.',
  ),
  'mediaFailed': (
    '图片或附件未能加载。',
    '圖片或附件未能載入。',
    'The image or attachment could not be loaded.',
  ),
  'preset': ('浮层预设', '浮層預設', 'Overlay preset'),
  'removeAttachment': ('移除附件', '移除附件', 'Remove attachment'),
  'leaveTitle': ('离开组织聊天？', '離開組織聊天？', 'Leave this conversation?'),
  'leaveBody': (
    '离开会丢弃当前草稿。尚未确认的消息可能已经发送，请勿重复发送相同内容。',
    '離開會捨棄目前草稿。尚未確認的訊息可能已經傳送，請勿重複傳送相同內容。',
    'Leaving discards this draft. An unconfirmed message may already have been sent; avoid sending it again.',
  ),
  'stay': ('继续编辑', '繼續編輯', 'Keep editing'),
  'leave': ('丢弃草稿并返回', '捨棄草稿並返回', 'Discard draft and return'),
};

String communityChatText(BuildContext context, String key) {
  final row = communityChatCopy[key] ?? communityChatCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? row.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? row.$2
      : row.$1;
}
