import 'package:flutter/material.dart';

import 'marketplace_copy.dart';
import 'marketplace_port.dart';

String marketBrowserText(BuildContext context, String cn, String en) =>
    marketLocale(context) == 'en'
    ? en
    : marketLocale(context) == 'hant'
    ? (_hant[cn] ?? cn)
    : cn;
const _hant = {
  '全部物品': '全部物品',
  '类型': '類型',
  '卖家状态': '賣家狀態',
  '在线': '線上',
  '游戏中': '遊戲中',
  '单价（UEC）': '單價（UEC）',
  '全部地点': '全部地點',
  '品质': '品質',
  '只看有品质': '只看有品質',
  '最低品质': '最低品質',
  '此分类暂无专属筛选条件': '此分類暫無專屬篩選條件',
  '关闭分类与筛选': '關閉分類與篩選',
  '分类与筛选': '分類與篩選',
  '关闭订单': '關閉訂單',
  '订单详情': '訂單詳情',
  '剩余数量': '剩餘數量',
  '查看物品': '檢視物品',
  '暂无挂单': '暫無掛單',
  '最新发布': '最新發布',
  '单价': '單價',
  '挂单最多': '掛單最多',
  '求购最多': '求購最多',
  '订单': '訂單',
  '切换升降序': '切換升降序',
  '全部订单': '全部訂單',
  '只看有挂单': '只看有掛單',
  '卖家': '賣家',
  '地点 / 交易时段': '地點 / 交易時段',
  '数量': '數量',
  '发布': '發布',
  '显示全部': '顯示全部',
  '定价': '定價',
  '已选地点': '已選地點',
  '最低价': '最低價',
  '最高价': '最高價',
  '交易地点': '交易地點',
  '搜索地点': '搜尋地點',
  '关闭': '關閉',
  '求购': '求購',
  '以物易物': '以物易物',
  '种物品': '種物品',
  '条订单': '條訂單',
  '种有挂单': '種有掛單',
};
String marketBrowserLabel(BuildContext context, MarketRow row) =>
    (row[marketLocale(context) == 'en' ? 'labelEn' : 'label'] ??
            row['label'] ??
            '')
        .toString();
