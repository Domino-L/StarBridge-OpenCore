import 'package:flutter/widgets.dart';

import 'marketplace_copy.dart';

/// 我的交易 · 评价 / 举报与拉黑 copy, keyed by the Simplified Chinese text.
String recordsText(
  BuildContext context,
  String key, [
  Map<String, String> args = const {},
]) {
  final locale = marketLocale(context);
  final values = recordsCopy[key];
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

const recordsCopy = <String, List<String>>{
  '评价': ['评价', '評價', 'Reviews'],
  '举报与拉黑': ['举报与拉黑', '檢舉與封鎖', 'Reports & blocks'],
  '收到的评价': ['收到的评价', '收到的評價', 'Reviews received'],
  '共 {n} 条 · 来自交易和合约': [
    '共 {n} 条 · 来自交易和合约',
    '共 {n} 則 · 來自交易和合約',
    '{n} total · from trades and contracts',
  ],
  '{n} 条已公开 · {p} 条审核中': [
    '{n} 条已公开 · {p} 条审核中',
    '{n} 則已公開 · {p} 則審核中',
    '{n} public · {p} under review',
  ],
  '{n} 星': ['{n} 星', '{n} 星', '{n}★'],
  '交易': ['交易', '交易', 'Trade'],
  '合约': ['合约', '合約', 'Contract'],
  '审核中': ['审核中', '審核中', 'Under review'],
  '未通过': ['未通过', '未通過', 'Rejected'],
  '（只打了分，没有写评价）': ['（只打了分，没有写评价）', '（只評了分，沒有寫評價）', '(Rating only, no comment)'],
  '还没有收到评价。': ['还没有收到评价。', '還沒有收到評價。', 'No reviews yet.'],
  '我的举报': ['我的举报', '我的檢舉', 'My reports'],
  '黑名单': ['黑名单', '黑名單', 'Blocked'],
  '共 {n} 条 · 处理结果来自 SCM': [
    '共 {n} 条 · 处理结果来自 SCM',
    '共 {n} 則 · 處理結果來自 SCM',
    '{n} total · outcomes from SCM',
  ],
  '举报 {name}': ['举报 {name}', '檢舉 {name}', 'Reported {name}'],
  '类型：': ['类型：', '類型：', 'Type: '],
  '处理结果：': ['处理结果：', '處理結果：', 'Outcome: '],
  '处理于 {time}': ['处理于 {time}', '處理於 {time}', 'Handled {time}'],
  '还没有举报记录。新建举报从交易单里发起。': [
    '还没有举报记录。新建举报从交易单里发起。',
    '還沒有檢舉紀錄。新增檢舉請從交易單發起。',
    'No reports. File one from a trade.',
  ],
  '共 {n} 人 · 拉黑后对方不能向你发起交易': [
    '共 {n} 人 · 拉黑后对方不能向你发起交易',
    '共 {n} 人 · 封鎖後對方不能向你發起交易',
    '{n} people · they cannot start trades with you',
  ],
  '原因：': ['原因：', '原因：', 'Reason: '],
  '{time} 拉黑': ['{time} 拉黑', '{time} 封鎖', 'Blocked {time}'],
  '解除': ['解除', '解除', 'Unblock'],
  '黑名单是空的。拉黑从交易单或订单面板发起。': [
    '黑名单是空的。拉黑从交易单或订单面板发起。',
    '黑名單是空的。封鎖請從交易單或訂單面板發起。',
    'Nobody is blocked. Block from a trade or order panel.',
  ],
  '解除拉黑 {name}？': ['解除拉黑 {name}？', '解除封鎖 {name}？', 'Unblock {name}?'],
  '解除后，对方可以再次向你发起交易，你也能看到对方的挂单。': [
    '解除后，对方可以再次向你发起交易，你也能看到对方的挂单。',
    '解除後，對方可以再次向你發起交易，你也能看到對方的掛單。',
    'They will be able to trade with you again, and you will see their listings.',
  ],
  '拉黑原因：{reason}（{time}）。': [
    '拉黑原因：{reason}（{time}）。',
    '封鎖原因：{reason}（{time}）。',
    'Reason: {reason} ({time}).',
  ],
  '取消': ['取消', '取消', 'Cancel'],
  '解除拉黑': ['解除拉黑', '解除封鎖', 'Unblock'],
  '没有解除成功，列表已刷新为 SCM 上的当前状态。': [
    '没有解除成功，列表已刷新为 SCM 上的当前状态。',
    '沒有解除成功，清單已更新為 SCM 上的目前狀態。',
    'Not unblocked. The list now shows what SCM holds.',
  ],
  '需要重新授权后才能查看。': [
    '需要重新授权后才能查看。',
    '需要重新授權後才能查看。',
    'Authorize again to view this.',
  ],
  '暂时读不到，点此重试。': [
    '暂时读不到，点此重试。',
    '暫時讀不到，點此重試。',
    'Could not load. Tap to retry.',
  ],
  '加载更多': ['加载更多', '載入更多', 'Load more'],
};
