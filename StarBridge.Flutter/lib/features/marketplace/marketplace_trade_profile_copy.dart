import 'package:flutter/widgets.dart';

import 'marketplace_copy.dart';

String tradeProfileText(BuildContext context, String key) {
  final locale = marketLocale(context);
  final values =
      tradeProfileCopy[key] ?? tradeProfileCopy['trade_profile.rejected']!;
  return values[locale == 'en'
      ? 2
      : locale == 'hant'
      ? 1
      : 0];
}

const tradeProfileCopy = <String, List<String>>{
  'title': ['交易资料', '交易資料', 'Trading profile'],
  'prepare': ['完善交易资料', '完善交易資料', 'Complete your trading profile'],
  'edit': ['编辑交易资料', '編輯交易資料', 'Edit trading profile'],
  'editShort': ['编辑', '編輯', 'Edit'],
  'hours': ['交易时段', '交易時段', 'Trading hours'],
  'days': ['交易日', '交易日', 'Trading days'],
  'daily': ['每天', '每天', 'Every day'],
  'mon': ['一', '一', 'Mon'],
  'tue': ['二', '二', 'Tue'],
  'wed': ['三', '三', 'Wed'],
  'thu': ['四', '四', 'Thu'],
  'fri': ['五', '五', 'Fri'],
  'sat': ['六', '六', 'Sat'],
  'sun': ['日', '日', 'Sun'],
  'start': ['开始时间', '開始時間', 'Start time'],
  'end': ['结束时间', '結束時間', 'End time'],
  'duration': [
    '至少 1 小时，允许跨天',
    '至少 1 小時，允許跨天',
    'At least 1 hour; overnight allowed',
  ],
  'zone': ['时区', '時區', 'Time zone'],
  'local': ['你的本机时间', '你的本機時間', 'Your local time'],
  'zoneUnknown': [
    '暂无法换算，请选择有效时区',
    '暫無法換算，請選擇有效時區',
    'Select an available time zone for the preview',
  ],
  'contact': ['联系方式', '聯絡方式', 'Contact details'],
  'public': [
    '会在 SCM 公开显示',
    '會在 SCM 公開顯示',
    'These details will be publicly visible on SCM',
  ],
  'more': ['更多', '更多', 'More'],
  'mark': ['简介', '簡介', 'About you'],
  'language': ['语言', '語言', 'Language'],
  'zh': ['中文', '中文', 'Chinese'],
  'en': ['英文', '英文', 'English'],
  'save': ['保存', '儲存', 'Save'],
  'saving': ['保存中…', '儲存中…', 'Saving…'],
  'cancel': ['取消', '取消', 'Cancel'],
  'retry': ['重新读取', '重新讀取', 'Reload'],
  'done': ['完成', '完成', 'Done'],
  'saved': [
    '已保存，以下为 SCM 实际保存的资料',
    '已儲存，以下為 SCM 實際儲存的資料',
    'Saved. The values below were read back from SCM',
  ],
  'noAutoTrade': [
    '保存后返回确认弹框，不会自动下单',
    '儲存後返回確認彈框，不會自動下單',
    'Return to confirmation after saving. No trade will be submitted automatically',
  ],
  'limit': ['挂单上限', '掛單上限', 'Listing limit'],
  'marketplace.reauthorize_required': [
    '当前授权不足，请重新授权 SCM',
    '目前授權不足，請重新授權 SCM',
    'Your current grant is missing permissions. Reauthorize SCM',
  ],
  'reauthorize': ['重新授权 SCM', '重新授權 SCM', 'Reauthorize SCM'],
  'marketplace.forbidden': [
    'SCM 拒绝了这次操作；一直这样请联系支持',
    'SCM 拒絕了這次操作；一直這樣請聯絡支援',
    'SCM refused this action. If it keeps happening, contact support',
  ],
  'trade_profile.time_range': [
    '请选择开始和结束时间，交易时段至少 1 小时',
    '請選擇開始和結束時間，交易時段至少 1 小時',
    'Choose a start and end time at least 1 hour apart',
  ],
  'trade_profile.no_day': [
    '至少选择一天开启交易',
    '至少選擇一天開啟交易',
    'Select at least one trading day',
  ],
  'trade_profile.contact_invalid': [
    '联系方式至少 5 个字符',
    '聯絡方式至少 5 個字元',
    'Contact details must contain at least 5 characters',
  ],
  'trade_profile.timezone_invalid': [
    '时区不存在或已停用，请重新选择',
    '時區不存在或已停用，請重新選擇',
    'This time zone is unavailable. Choose another',
  ],
  'trade_profile.rejected': [
    '暂时无法保存，请检查填写内容或稍后重试',
    '暫時無法儲存，請檢查填寫內容或稍後重試',
    'Unable to save. Check your details or try again later',
  ],
  'trade_profile.read_failed': [
    '暂时读不到交易资料，请稍后重新读取',
    '暫時讀不到交易資料，請稍後重新讀取',
    'Trading profile could not be loaded. Reload later',
  ],
  'trade_profile.unknown': [
    '保存结果未确认，请先重新读取核对，不要重复提交',
    '儲存結果未確認，請先重新讀取核對，不要重複提交',
    'Save outcome is uncertain. Reload and review before submitting again',
  ],
  'marketplace.context_changed': [
    '账号已改变，请关闭后重新打开',
    '帳號已改變，請關閉後重新開啟',
    'The account changed. Close and reopen this form',
  ],
  'marketplace.sign_in_required': [
    '请先登录 SCM',
    '請先登入 SCM',
    'Sign in to SCM first',
  ],
};

const _reauthorizeCodes = {
  'marketplace.reauthorize_required',
  'account.reauthorization_required',
};

bool tradeProfileNeedsReauthorize(String? code) =>
    _reauthorizeCodes.contains(code) || code == 'marketplace.sign_in_required';

/// A failed read never shows save wording, and a code without its own copy
/// stays visible so a live failure can be traced from a screenshot.
String tradeProfileErrorText(
  BuildContext context,
  String code, {
  bool reading = false,
}) {
  final key = _reauthorizeCodes.contains(code)
      ? 'marketplace.reauthorize_required'
      : code;
  if (key == 'marketplace.reauthorize_required' ||
      key == 'marketplace.sign_in_required' ||
      key == 'marketplace.context_changed') {
    return tradeProfileText(context, key);
  }
  if (reading) {
    return '${tradeProfileText(context, 'trade_profile.read_failed')} ($code)';
  }
  return tradeProfileCopy.containsKey(key)
      ? tradeProfileText(context, key)
      : '${tradeProfileText(context, 'trade_profile.rejected')} ($code)';
}
