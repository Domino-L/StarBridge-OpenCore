import 'package:flutter/widgets.dart';

import 'marketplace_copy.dart';

/// 交易私信 copy, keyed by the Simplified Chinese text.
String chatText(
  BuildContext context,
  String key, [
  Map<String, String> args = const {},
]) {
  final locale = marketLocale(context);
  final values = chatCopy[key];
  var text = values == null
      ? key
      : values[locale == 'en'
            ? 2
            : locale == 'hant'
            ? 1
            : 0];
  for (final entry in args.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  return text;
}

const chatCopy = <String, List<String>>{
  '更早的消息尚未同步，请向上滚动加载。': [
    '更早的消息尚未同步，请向上滚动加载。',
    '更早的訊息尚未同步，請向上捲動載入。',
    'Earlier messages have not synced yet. Scroll up to load them.',
  ],
  '私信': ['私信', '私訊', 'Messages'],
  '交易消息': ['交易消息', '交易訊息', 'Trade messages'],
  '与 SCM 网站互通 · 实时同步': [
    '与 SCM 网站互通 · 实时同步',
    '與 SCM 網站互通 · 即時同步',
    'Shared with the SCM site · live',
  ],
  '封禁记录 {n}': ['封禁记录 {n}', '封禁紀錄 {n}', '{n} past ban(s)'],
  '还没有交易消息。在交易单或订单详情里可以私信对方。': [
    '还没有交易消息。在交易单或订单详情里可以私信对方。',
    '還沒有交易訊息。可以在交易單或訂單詳情裡私訊對方。',
    'No trade messages yet. Message someone from a trade or an order.',
  ],
  '选择一个会话': ['选择一个会话', '選擇一個對話', 'Choose a conversation'],
  '在线': ['在线', '線上', 'Online'],
  '离开': ['离开', '離開', 'Away'],
  '离线': ['离线', '離線', 'Offline'],
  '在 SCM 打开': ['在 SCM 打开', '在 SCM 開啟', 'Open on SCM'],
  '该用户在 SCM 有 {n} 次封禁记录（最近原因：{reason}，{state}）。交易前请核对对方信誉。': [
    '该用户在 SCM 有 {n} 次封禁记录（最近原因：{reason}，{state}）。交易前请核对对方信誉。',
    '該使用者在 SCM 有 {n} 次封禁紀錄（最近原因：{reason}，{state}）。交易前請核對對方信譽。',
    'This member has {n} past ban(s) on SCM (latest: {reason}, {state}). Check their reputation before trading.',
  ],
  '封禁中': ['封禁中', '封禁中', 'still banned'],
  '已解封': ['已解封', '已解封', 'lifted'],
  '你已拉黑该用户，双方都不能再发消息或发起交易。可在“我的交易 → 举报与拉黑”解除。': [
    '你已拉黑该用户，双方都不能再发消息或发起交易。可在“我的交易 → 举报与拉黑”解除。',
    '你已封鎖該使用者，雙方都不能再傳訊息或發起交易。可在「我的交易 → 檢舉與封鎖」解除。',
    'You blocked this member; neither of you can message or trade. Unblock under My trades → Reports & blocks.',
  ],
  '你已拉黑该用户，双方都不能再发消息或发起交易。': [
    '你已拉黑该用户，双方都不能再发消息或发起交易。',
    '你已封鎖該使用者，雙方都不能再傳訊息或發起交易。',
    'You blocked this member; neither of you can message or trade.',
  ],
  '解除拉黑': ['解除拉黑', '解除封鎖', 'Unblock'],
  '解除拉黑 {name}？': ['解除拉黑 {name}？', '解除封鎖 {name}？', 'Unblock {name}?'],
  '解除后，对方可以再次向你发起交易和发私信，你也能看到对方的挂单。': [
    '解除后，对方可以再次向你发起交易和发私信，你也能看到对方的挂单。',
    '解除後，對方可以再次向你發起交易和傳私訊，你也能看到對方的掛單。',
    'They will be able to trade with and message you again, and you will see their listings.',
  ],
  '取消': ['取消', '取消', 'Cancel'],
  '没有解除成功，会话已刷新为 SCM 上的当前状态。': [
    '没有解除成功，会话已刷新为 SCM 上的当前状态。',
    '沒有解除成功，對話已更新為 SCM 上的目前狀態。',
    'Not unblocked. The conversation now shows what SCM holds.',
  ],
  '对方已将你拉黑，无法发送消息或发起交易。': [
    '对方已将你拉黑，无法发送消息或发起交易。',
    '對方已將你封鎖，無法傳訊息或發起交易。',
    'This member blocked you; you cannot message or trade.',
  ],
  '加载更早的消息': ['加载更早的消息', '載入更早的訊息', 'Load earlier messages'],
  '读取失败，点此重试': ['读取失败，点此重试', '讀取失敗，點此重試', 'Could not load. Tap to retry'],
  '含外部链接，谨慎打开；SCM 不会通过链接收款。': [
    '含外部链接，谨慎打开；SCM 不会通过链接收款。',
    '含外部連結，謹慎開啟；SCM 不會透過連結收款。',
    'Contains an external link. Be careful; SCM never collects payment through links.',
  ],
  '已读': ['已读', '已讀', 'Read'],
  '已送达': ['已送达', '已送達', 'Delivered'],
  '发送中…': ['发送中…', '傳送中…', 'Sending…'],
  '未确认：没有收到 SCM 回执，不会自动重发': [
    '未确认：没有收到 SCM 回执，不会自动重发',
    '未確認：沒有收到 SCM 回執，不會自動重送',
    'Unconfirmed: no reply from SCM; it is not resent automatically',
  ],
  '刷新查看': ['刷新查看', '重新整理查看', 'Refresh'],
  '再发一次': ['再发一次', '再傳一次', 'Send again'],
  '未发出：{reason}': ['未发出：{reason}', '未送出：{reason}', 'Not sent: {reason}'],
  'SCM 未接受': ['SCM 未接受', 'SCM 未接受', 'SCM refused it'],
  '移除': ['移除', '移除', 'Remove'],
  '附上订单：{label}': ['附上订单：{label}', '附上訂單：{label}', 'Attached order: {label}'],
  '附上订单': ['附上订单', '附上訂單', 'Attach order'],
  '发送': ['发送', '傳送', 'Send'],
  '输入消息，Enter 发送，Shift+Enter 换行': [
    '输入消息，Enter 发送，Shift+Enter 换行',
    '輸入訊息，Enter 傳送，Shift+Enter 換行',
    'Message — Enter to send, Shift+Enter for a new line',
  ],
  '消息会同步到 SCM 网站；请勿在私信里交换账号密码。': [
    '消息会同步到 SCM 网站；请勿在私信里交换账号密码。',
    '訊息會同步到 SCM 網站；請勿在私訊中交換帳號密碼。',
    'Messages are shared with the SCM site. Never share passwords here.',
  ],
  '最多 150 个字符（表情算 2 个），请删减后再发送。': [
    '最多 150 个字符（表情算 2 个），请删减后再发送。',
    '最多 150 個字元（表情符號算 2 個），請刪減後再傳送。',
    'Up to 150 characters (an emoji counts as 2). Shorten it to send.',
  ],
  '无法发送：你们之间存在拉黑关系。': [
    '无法发送：你们之间存在拉黑关系。',
    '無法傳送：你們之間存在封鎖關係。',
    'Cannot send: one of you blocked the other.',
  ],
  '订单': ['订单', '訂單', 'Order'],
  '图片': ['图片', '圖片', 'Image'],
  '[订单] {name}': ['[订单] {name}', '[訂單] {name}', '[Order] {name}'],
  '最近的交易单': ['最近的交易单', '最近的交易單', 'Recent trades'],
  '返回': ['返回', '返回', 'Back'],
  '交易消息需要 SCM 授权更新后才能使用。': [
    '交易消息需要 SCM 授权更新后才能使用。',
    '交易訊息需要 SCM 授權更新後才能使用。',
    'Trade messages need an SCM permission update first.',
  ],
};
