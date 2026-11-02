import 'package:flutter/widgets.dart';

import 'marketplace_copy.dart';

/// 合约 copy (0.7.2 G1), keyed by the Simplified Chinese text.
String contractText(
  BuildContext context,
  String key, [
  Map<String, String> args = const {},
]) {
  final locale = marketLocale(context);
  final values = contractCopy[key];
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

const contractCopy = <String, List<String>>{
  '公开合约': ['公开合约', '公開合約', 'Open contracts'],
  '我发布的': ['我发布的', '我發布的', 'Published'],
  '我参与的': ['我参与的', '我參與的', 'Joined'],
  '类型': ['类型', '類型', 'Type'],
  '状态': ['状态', '狀態', 'Status'],
  '报酬': ['报酬', '報酬', 'Reward'],
  '我能报名的': ['我能报名的', '我能報名的', 'I can apply'],
  '全部': ['全部', '全部', 'All'],
  '悬赏': ['悬赏', '懸賞', 'Bounty'],
  '委托': ['委托', '委託', 'Service'],
  '协作': ['协作', '協作', 'Cooperation'],
  '招募中': ['招募中', '招募中', 'Recruiting'],
  '执行中': ['执行中', '執行中', 'In progress'],
  '已完成': ['已完成', '已完成', 'Completed'],
  '已取消': ['已取消', '已取消', 'Cancelled'],
  '已过期': ['已过期', '已過期', 'Expired'],
  '草稿': ['草稿', '草稿', 'Draft'],
  '发布': ['发布', '發布', 'Published'],
  'UEC': ['UEC', 'UEC', 'UEC'],
  '物品': ['物品', '物品', 'Items'],
  '不限': ['不限', '不限', 'Any'],
  '信誉够': ['信誉够', '信譽夠', 'Reputation met'],
  '共 {n} 个 · {sort}': [
    '共 {n} 个 · {sort}',
    '共 {n} 個 · {sort}',
    '{n} total · {sort}',
  ],
  '最新发布': ['最新发布', '最新發布', 'Newest'],
  '报酬最高': ['报酬最高', '報酬最高', 'Highest reward'],
  '即将截止': ['即将截止', '即將截止', 'Ending soon'],
  '发布合约': ['发布合约', '發布合約', 'Publish contract'],
  '名额 {n}': ['名额 {n}', '名額 {n}', 'Slots {n}'],
  '信誉 ≥ {n}': ['信誉 ≥ {n}', '信譽 ≥ {n}', 'Rep ≥ {n}'],
  '剩 {n} 天': ['剩 {n} 天', '剩 {n} 天', '{n}d left'],
  '剩 {n} 小时': ['剩 {n} 小时', '剩 {n} 小時', '{n}h left'],
  '已截止': ['已截止', '已截止', 'Closed'],
  '报名': ['报名', '報名', 'Apply'],
  '已报名': ['已报名', '已報名', 'Applied'],
  '我的': ['我的', '我的', 'Mine'],
  '还没有合约。': ['还没有合约。', '還沒有合約。', 'No contracts yet.'],
  '暂时读不到合约，点此重试。': [
    '暂时读不到合约，点此重试。',
    '暫時讀不到合約，點此重試。',
    'Could not load contracts. Tap to retry.',
  ],
  '合约需要 SCM 授权更新后才能使用。': [
    '合约需要 SCM 授权更新后才能使用。',
    '合約需要 SCM 授權更新後才能使用。',
    'Contracts need an SCM permission update first.',
  ],
  '加载更多': ['加载更多', '載入更多', 'Load more'],
  '合约详情': ['合约详情', '合約詳情', 'Contract'],
  '名额': ['名额', '名額', 'Slots'],
  '信誉门槛': ['信誉门槛', '信譽門檻', 'Min. reputation'],
  '截止': ['截止', '截止', 'Deadline'],
  '说明': ['说明', '說明', 'Description'],
  '标题': ['标题', '標題', 'Title'],
  '其他要求：': ['其他要求：', '其他要求：', 'Requirements: '],
  '地点：': ['地点：', '地點：', 'Location: '],
  '里程碑': ['里程碑', '里程碑', 'Milestones'],
  '参与者': ['参与者', '參與者', 'Participants'],
  '还没有人报名。': ['还没有人报名。', '還沒有人報名。', 'Nobody has applied yet.'],
  '发布者': ['发布者', '發布者', 'Publisher'],
  '舰队合约 · {name}': [
    '舰队合约 · {name}',
    '艦隊合約 · {name}',
    'Fleet contract · {name}',
  ],
  '私信': ['私信', '私訊', 'Message'],
  '报名（可附留言）': ['报名（可附留言）', '報名（可附留言）', 'Apply (with a note)'],
  '退出': ['退出', '退出', 'Withdraw'],
  '开始合约': ['开始合约', '開始合約', 'Start'],
  '完成合约': ['完成合约', '完成合約', 'Complete'],
  '取消合约': ['取消合约', '取消合約', 'Cancel contract'],
  '发起争议': ['发起争议', '發起爭議', 'Open dispute'],
  '去评价': ['去评价', '去評價', 'Review'],
  '你的信誉未达到门槛': [
    '你的信誉未达到门槛',
    '你的信譽未達門檻',
    'Your reputation is below the minimum',
  ],
  '待审核': ['待审核', '待審核', 'Pending'],
  '已接受': ['已接受', '已接受', 'Accepted'],
  '已拒绝': ['已拒绝', '已拒絕', 'Rejected'],
  '进行中': ['进行中', '進行中', 'Working'],
  '已违约': ['已违约', '已違約', 'Breached'],
  '已退出': ['已退出', '已退出', 'Withdrew'],
  '留言（可选，最多 1000 字）': [
    '留言（可选，最多 1000 字）',
    '留言（選填，最多 1000 字）',
    'Note (optional, up to 1000 characters)',
  ],
  '原因（必填）': ['原因（必填）', '原因（必填）', 'Reason (required)'],
  '评价（可选）': ['评价（可选）', '評價（選填）', 'Comment (optional)'],
  '确认': ['确认', '確認', 'Confirm'],
  '取消': ['取消', '取消', 'Cancel'],
  '操作已完成。': ['操作已完成。', '操作已完成。', 'Done.'],
  'SCM 未接受这个操作，详情已按 SCM 的最新状态刷新。': [
    'SCM 未接受这个操作，详情已按 SCM 的最新状态刷新。',
    'SCM 未接受這個操作，詳情已按 SCM 的最新狀態更新。',
    'SCM refused this; the details now show its current state.',
  ],
  '标题（最多 100 字）': [
    '标题（最多 100 字）',
    '標題（最多 100 字）',
    'Title (up to 100 characters)',
  ],
  '说明（最多 2000 字）': [
    '说明（最多 2000 字）',
    '說明（最多 2000 字）',
    'Description (up to 2000 characters)',
  ],
  'UEC 金额': ['UEC 金额', 'UEC 金額', 'UEC amount'],
  '报酬说明（物品报酬必填）': [
    '报酬说明（物品报酬必填）',
    '報酬說明（物品報酬必填）',
    'Reward note (required for items)',
  ],
  '名额（1–100）': ['名额（1–100）', '名額（1–100）', 'Slots (1–100)'],
  '最低信誉': ['最低信誉', '最低信譽', 'Min. reputation'],
  '地点': ['地点', '地點', 'Location'],
  '其他要求': ['其他要求', '其他要求', 'Other requirements'],
  '截止时间（本机时间）': ['截止时间（本机时间）', '截止時間（本機時間）', 'Deadline (local time)'],
  '选择': ['选择', '選擇', 'Choose'],
  '请核对：标题必填；UEC 报酬要大于 0；物品报酬要写说明；名额 1–100；截止时间要在未来。': [
    '请核对：标题必填；UEC 报酬要大于 0；物品报酬要写说明；名额 1–100；截止时间要在未来。',
    '請核對：標題必填；UEC 報酬要大於 0；物品報酬要寫說明；名額 1–100；截止時間要在未來。',
    'Check: a title; a UEC reward above 0, or a note for item rewards; 1–100 slots; a future deadline.',
  ],
  '{n} 小时': ['{n} 小时', '{n} 小時', '{n} hours'],
  '{n} 天': ['{n} 天', '{n} 天', '{n} days'],
  '名额 / 信誉': ['名额 / 信誉', '名額 / 信譽', 'Slots / reputation'],
  '名额 ': ['名额 ', '名額 ', 'Slots '],
  '信誉 ≥ ': ['信誉 ≥ ', '信譽 ≥ ', 'Rep ≥ '],
  '发布者确认后结算': ['发布者确认后结算', '發布者確認後結算', 'Settled after the publisher confirms'],
};
