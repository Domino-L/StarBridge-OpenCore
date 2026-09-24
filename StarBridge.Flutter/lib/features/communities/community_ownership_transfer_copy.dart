import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityOwnershipTransferCopy = <String, (String, String, String)>{
  'transfer': ('移交负责人', '移交負責人', 'Transfer ownership'),
  'confirm': ('确认移交', '確認移交', 'Confirm transfer'),
  'cancel': ('取消', '取消', 'Cancel'),
  'close': ('关闭', '關閉', 'Close'),
  'reload': ('重新读取', '重新讀取', 'Reload'),
  'retry': ('确认再次移交', '確認再次移交', 'Confirm transfer retry'),
  'consequence': (
    '对方将成为此组织唯一负责人，拥有全部管理权限。立即生效，不能在本机撤销。',
    '對方將成為此組織唯一負責人，擁有全部管理權限。立即生效，不能在本機撤銷。',
    'This member becomes the sole owner with full management rights. The transfer takes effect immediately and cannot be undone locally.',
  ),
  'formerRole': (
    '你将变为「{role}」。其他组织不受影响。',
    '你將變為「{role}」。其他組織不受影響。',
    'Your new role: {role}. Other organizations are unaffected.',
  ),
  'protected': (
    '当前不能移交给此成员。',
    '目前不能移交給此成員。',
    'Ownership cannot be transferred to this member now.',
  ),
  'outcomeUnknown': (
    '尚未确认移交结果，请先重新读取。',
    '尚未確認移交結果，請先重新讀取。',
    'The transfer is not confirmed. Reload first.',
  ),
  'retryHelp': (
    '上次移交可能已生效。核对最新权限后，再决定是否重试。',
    '上次移交可能已生效。核對最新權限後，再決定是否重試。',
    'The previous transfer may have succeeded. Check current permissions before retrying.',
  ),
  'conflict': (
    '成员或权限已变化，或旧资料无法区分。请重新读取。',
    '成員或權限已變更，或舊資料無法區分。請重新讀取。',
    'Membership or permissions changed, or older data is ambiguous. Reload to retry.',
  ),
  'identityUnavailable': (
    '账号或组织已切换，请关闭后重新打开。',
    '帳號或組織已切換，請關閉後重新開啟。',
    'The account or organization changed. Close and reopen this dialog.',
  ),
  'notAllowed': (
    '你已不是负责人，或此成员不能接任。请关闭并刷新组织。',
    '你已不是負責人，或此成員不能接任。請關閉並重新整理組織。',
    'You are no longer the owner, or this member cannot take ownership. Close and refresh the organization.',
  ),
  'notFound': (
    '组织或成员已不可用，请关闭并刷新。',
    '組織或成員已不可用，請關閉並重新整理。',
    'The organization or member is no longer available. Close and refresh.',
  ),
  'refreshRequired': (
    '确认资料已过期，请关闭并刷新成员列表。',
    '確認資料已過期，請關閉並重新整理成員清單。',
    'This confirmation expired. Close and refresh the member list.',
  ),
  'unavailable': (
    '暂时无法读取移交资料，请重试。',
    '暫時無法讀取移交資料，請重試。',
    'Transfer details are unavailable. Try again.',
  ),
  'dataInvalid': (
    '移交资料不完整，请重新读取。',
    '移交資料不完整，請重新讀取。',
    'Transfer details are incomplete. Reload to retry.',
  ),
  'busy': (
    '另一项组织操作正在处理，请稍后重新读取。',
    '另一項組織操作正在處理，請稍後重新讀取。',
    'Another organization action is running. Reload shortly.',
  ),
  'invalidDraft': (
    '移交请求已失效，请关闭后重新打开。',
    '移交請求已失效，請關閉後重新開啟。',
    'This transfer request is invalid. Close and reopen this dialog.',
  ),
  'requestChanged': (
    '请求内容已变化，请关闭后重新打开。',
    '請求內容已變更，請關閉後重新開啟。',
    'The request changed. Close and reopen this dialog.',
  ),
};

String ownershipTransferText(BuildContext context, String key) {
  final value =
      communityOwnershipTransferCopy[key] ??
      communityOwnershipTransferCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
