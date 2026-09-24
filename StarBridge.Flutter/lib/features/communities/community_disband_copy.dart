import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityDisbandCopy = <String, (String, String, String)>{
  'action': ('解散组织', '解散組織', 'Disband organization'),
  'title': ('解散此组织？', '解散此組織？', 'Disband this organization?'),
  'members': ('当前 {count} 位成员', '目前 {count} 位成員', 'Currently {count} members'),
  'consequence': (
    '组织将被移除，所有成员将失去对此组织的访问。此操作无法在应用中撤销，不会退出其他组织。',
    '組織將被移除，所有成員將失去對此組織的存取。此操作無法在應用程式中復原，不會退出其他組織。',
    'The organization will be removed and all members will lose access to it. This cannot be undone in the app. Other organization memberships are unchanged.',
  ),
  'password': (
    '原星海舰桥账号密码',
    '原星海艦橋帳號密碼',
    'Original StarBridge account password',
  ),
  'credential': (
    '验证关联的原账号，不是 SCM 账号密码。密码仅用于本次确认。',
    '驗證關聯的原帳號，不是 SCM 帳號密碼。密碼僅用於本次確認。',
    'Verifies the linked original account, not your SCM password. Used only for this confirmation.',
  ),
  'example': (
    '示例操作：无需输入真实密码，不影响真实组织。',
    '示例操作：無需輸入真實密碼，不影響真實組織。',
    'Example only: no real password is needed and no real organization is affected.',
  ),
  'cancel': ('保留组织', '保留組織', 'Keep organization'),
  'close': ('关闭', '關閉', 'Close'),
  'reload': ('重新读取确认', '重新讀取確認', 'Reload confirmation'),
  'passwordInvalid': (
    '原账号密码未通过验证，请重新读取确认后再输入。',
    '原帳號密碼未通過驗證，請重新讀取確認後再輸入。',
    'The original account password was not verified. Reload the confirmation and enter it again.',
  ),
  'refreshRequired': (
    '组织或权限已变化，请重新读取确认；若仍无法读取，请关闭后刷新组织。',
    '組織或權限已變更，請重新讀取確認；若仍無法讀取，請關閉後重新整理組織。',
    'The organization or permissions changed. Reload the confirmation; if unavailable, close and refresh the organization.',
  ),
  'outcomeUnknown': (
    '尚未确认解散结果，不会自动重试。请关闭后刷新组织，核对最新状态。',
    '尚未確認解散結果，不會自動重試。請關閉後重新整理組織，核對最新狀態。',
    'Disbanding is not confirmed and will not be retried automatically. Close and refresh the organization to check its status.',
  ),
  'identityUnavailable': (
    '账号或组织已切换，请关闭此窗口。',
    '帳號或組織已切換，請關閉此視窗。',
    'The account or organization changed. Close this window.',
  ),
  'notAllowed': (
    '当前账号无权解散此组织，请关闭后刷新。',
    '目前帳號無權解散此組織，請關閉後重新整理。',
    'This account cannot disband the organization. Close and refresh.',
  ),
  'unavailable': (
    '暂时无法读取组织确认，请稍后重试。',
    '暫時無法讀取組織確認，請稍後重試。',
    'The confirmation is unavailable. Try again shortly.',
  ),
  'dataInvalid': (
    '组织确认暂时无法读取，请重新读取。',
    '組織確認暫時無法讀取，請重新讀取。',
    'The confirmation could not be read. Try reloading.',
  ),
  'busy': (
    '正在处理其他组织操作，请稍后重新读取确认。',
    '正在處理其他組織操作，請稍後重新讀取確認。',
    'Another organization action is in progress. Reload the confirmation shortly.',
  ),
};
String disbandText(BuildContext context, String key) {
  final value =
      communityDisbandCopy[key] ?? communityDisbandCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
