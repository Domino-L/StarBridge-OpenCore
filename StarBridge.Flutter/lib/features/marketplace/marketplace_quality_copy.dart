import 'package:flutter/widgets.dart';

import 'marketplace_copy.dart';
import 'marketplace_quality.dart';

/// Copy for tier pricing (user 2026-10-23); {n}, {tier} placeholders.
String qualityText(
  BuildContext context,
  String key, {
  Object? n,
  String? tier,
}) {
  final values = _copy[key];
  if (values == null) return key;
  final locale = marketLocale(context);
  var text =
      values[locale == 'en'
          ? 2
          : locale == 'hant'
          ? 1
          : 0];
  if (n != null) text = text.replaceAll('{n}', '$n');
  if (tier != null) text = text.replaceAll('{tier}', tier);
  return text;
}

/// "极品 ≥950" / "极佳 800–949": a tier with its range.
String qualityTierRange(BuildContext context, MarketQualityTier tier) =>
    '${marketText(context, tier.name)} ${switch (tier) {
      MarketQualityTier.legendary => '≥${tier.min}',
      MarketQualityTier.inferior => '<${tier.max + 1}',
      _ => '${tier.min}–${tier.max}',
    }}';

const _copy = <String, List<String>>{
  'recentAverage': ['近期均价', '近期均價', 'Recent average'],
  'recentAverageNote': [
    '近期均价（SCM 近 60 天统计）',
    '近期均價（SCM 近 60 天統計）',
    'Recent average (SCM, last 60 days)',
  ],
  'anyQuality': ['任意品质', '任意品質', 'Any quality'],
  'anyQualityLowest': ['任意品质最低', '任意品質最低', 'Lowest, any quality'],
  'bestValue': ['档内最划算', '檔內最划算', 'Best value in tier'],
  'bestValueShort': ['最划算', '最划算', 'Best value'],
  'bestValuePartial': [
    '已比较的 {n} 单中最划算',
    '已比較的 {n} 單中最划算',
    'Best of {n} compared',
  ],
  'bestLoaded': ['已加载中最划算', '已載入中最划算', 'Best of loaded'],
  'tierLowest': ['档内最低', '檔內最低', 'Lowest in tier'],
  'perPoint': ['{n}/点', '{n}/點', '{n}/pt'],
  'perPointSort': ['每点单价', '每點單價', 'Per point'],
  'perPointHint': [
    '每点单价 = 单价 ÷ 品质，越低越划算',
    '每點單價 = 單價 ÷ 品質，越低越划算',
    'Per point = price ÷ quality; lower is better value',
  ],
  'allTiers': ['全部档', '全部檔', 'All tiers'],
  'tierCount': ['{n} 单', '{n} 單', '{n} listings'],
  'tierHeaderPartial': [
    '{n} 单 · 最低 {low} · 已比较 {s} 单中最划算 {pp}/点',
    '{n} 單 · 最低 {low} · 已比較 {s} 單中最划算 {pp}/點',
    '{n} listings · lowest {low} · best of {s} compared {pp}/pt',
  ],
  'tierHeader': [
    '{n} 单 · 最低 {low} · 最划算 {pp}/点',
    '{n} 單 · 最低 {low} · 最划算 {pp}/點',
    '{n} listings · lowest {low} · best {pp}/pt',
  ],
  'sameTierLowest': [
    '同档（{tier}）最低卖价',
    '同檔（{tier}）最低賣價',
    'Lowest ask in {tier}',
  ],
  'sameTierHighest': [
    '同档（{tier}）最高收购',
    '同檔（{tier}）最高收購',
    'Highest bid in {tier}',
  ],
  'becomesTierLowest': [
    '你的价格将成为{tier}档最低',
    '你的價格將成為{tier}檔最低',
    'Your price becomes the lowest in {tier}',
  ],
  'aboveTierLowest': ['比同档最低高 {n}', '比同檔最低高 {n}', '{n} above the tier lowest'],
  'yourPerPoint': ['你的每点单价', '你的每點單價', 'Your price per point'],
  'tierBestPerPoint': ['同档最划算 {n}/点', '同檔最划算 {n}/點', 'tier best {n}/pt'],
  'alsoBestValue': ['也是最划算', '也是最划算', 'also the best value'],
  'tierBestPerPointPartial': [
    '同档已比较的单中最划算 {n}/点',
    '同檔已比較的單中最划算 {n}/點',
    'best compared {n}/pt',
  ],
  'alsoBestValuePartial': ['比已比较的都划算', '比已比較的都划算', 'better than all compared'],
  'perPointAbove': ['高 {n}', '高 {n}', '{n} higher'],
  'otherTierAside': [
    '参考：任意品质最低 {n}（不同档，不比较）',
    '參考：任意品質最低 {n}（不同檔，不比較）',
    'For reference: lowest any quality {n} (other tier, not compared)',
  ],
  'tierEmpty': ['暂无', '暫無', 'None'],
};
