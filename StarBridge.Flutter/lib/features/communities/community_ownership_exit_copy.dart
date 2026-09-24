import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'community_ownership_transfer_copy.dart';

const communityOwnershipExitCopy = <String, (String, String, String)>{
  'title': ('交接并退出', '交接並退出', 'Hand over and leave'),
  'choose': ('选择接任成员', '選擇接任成員', 'Choose a successor'),
  'help': (
    '先选择接任成员，再确认退出。',
    '先選擇接任成員，再確認退出。',
    'Choose a successor, then confirm that you want to leave.',
  ),
  'search': ('搜索成员', '搜尋成員', 'Search members'),
  'previous': ('上一页', '上一頁', 'Previous'),
  'next': ('下一页', '下一頁', 'Next'),
  'back': ('重新选择', '重新選擇', 'Choose another member'),
  'empty': (
    '暂无可接任成员。可先邀请成员加入，再交接退出。',
    '暫無可接任成員。可先邀請成員加入，再交接退出。',
    'No successor is available. Invite a member before handing over and leaving.',
  ),
  'noMatch': (
    '本页没有可接任成员。请换页或调整搜索。',
    '本頁沒有可接任成員。請換頁或調整搜尋。',
    'No eligible member on this page. Change the search or page.',
  ),
  'consequence': (
    '对方将成为唯一负责人，你将退出此组织并失去访问权限。其他组织不受影响。',
    '對方將成為唯一負責人，你將退出此組織並失去存取權限。其他組織不受影響。',
    'This member becomes the sole owner. You will leave this organization and lose access to it. Other organizations are unaffected.',
  ),
  'outcomeUnknown': (
    '尚未确认退出结果，请先重新读取。',
    '尚未確認退出結果，請先重新讀取。',
    'The exit is not confirmed. Reload first.',
  ),
  'retry': ('确认再次交接并退出', '確認再次交接並退出', 'Confirm handover and exit retry'),
  'retryHelp': (
    '上次操作可能已生效。请先核对最新状态，再决定是否重试。',
    '上次操作可能已生效。請先核對最新狀態，再決定是否重試。',
    'The previous action may have succeeded. Check the current state before retrying.',
  ),
};

String ownershipExitText(BuildContext context, String key) {
  final value = communityOwnershipExitCopy[key];
  if (value == null) return ownershipTransferText(context, key);
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
