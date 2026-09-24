import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityWorkspaceCopy = <String, (String, String, String)>{
  'notInGame': ('未进入游戏', '未進入遊戲', 'Not in game'),
  'notInServer': ('未进入服务器', '未進入伺服器', 'Not in a server'),
  'waitingRecognition': ('等待识别', '等待識別', 'Waiting for recognition'),
  'waitingServerSync': ('等待服务器同步', '等待伺服器同步', 'Waiting for server sync'),
  'locationPending': ('地点待确认', '地點待確認', 'Location pending confirmation'),
  'timeZoneUnavailable': ('时区待确认', '時區待確認', 'Time zone unconfirmed'),
  'standardTime': ('标准时', '標準時間', 'standard time'),
  'refreshFailed': (
    '更新未完成，显示上次读取的资料。',
    '更新未完成，顯示上次讀取的資料。',
    'Update incomplete. Showing previously loaded data.',
  ),
  'renewing': ('正在更新组织资料…', '正在更新組織資料…', 'Refreshing organization details…'),
  'loading': ('正在加载组织资料…', '正在載入組織資料…', 'Loading organization details…'),
  'imageLoading': ('正在加载图片…', '正在載入圖片…', 'Loading image…'),
  'imageFailed': ('图片加载失败', '圖片載入失敗', 'Image could not be loaded'),
  'section.members': ('成员', '成員', 'Members'),
  'section.chat': ('聊天', '聊天', 'Chat'),
  'section.ships': ('舰船', '艦船', 'Ships'),
  'section.broadcast': ('广播', '廣播', 'Broadcast'),
  'section.manage': ('管理', '管理', 'Manage'),
  'details': ('组织资料与公告', '組織資料與公告', 'Details and announcements'),
  'viewDetails': ('详情', '詳情', 'Details'),
  'currentPage': ('当前页', '目前頁', 'This page'),
  'sectionUnavailable': (
    '此功能尚未接入当前客户端。',
    '此功能尚未接入目前用戶端。',
    'This feature is not connected in this client yet.',
  ),
  'paused': ('共享已暂停', '分享已暫停', 'Sharing paused'),
  'members': ('组织成员', '組織成員', 'Members'),
  'member': ('成员', '成員', 'Member'),
  'role': ('角色', '角色', 'Role'),
  'status': ('状态', '狀態', 'Status'),
  'actions': ('操作', '操作', 'Actions'),
  'onlineInfo': ('在线信息', '線上資訊', 'Presence'),
  'onlineMembers': ('在线成员', '線上成員', 'Online members'),
  'hideOnlineMembers': ('收起在线成员', '收起線上成員', 'Hide online members'),
  'allMembers': ('全部成员', '全部成員', 'All members'),
  'membersRead': ('已读取成员', '已讀取成員', 'Members checked'),
  'loadMoreMembers': ('继续读取成员', '繼續讀取成員', 'Load more members'),
  'noOnlineMembers': ('暂无可见在线成员', '暫無可見線上成員', 'No visible online members'),
  'noOnlineLoaded': (
    '已读取范围内暂无在线成员',
    '已讀取範圍內暫無線上成員',
    'No online members in the loaded range',
  ),
  'away': ('暂离', '暫離', 'Away'),
  'announcements': ('公告', '公告', 'Announcements'),
  'presencePageScope': (
    '在线与游戏人数仅统计当前页',
    '線上與遊戲人數僅統計目前頁面',
    'Online and in-game counts cover this page only',
  ),
  'refresh': ('刷新资料', '重新整理資料', 'Refresh'),
  'search': ('搜索成员、呼号或职务', '搜尋成員、呼號或職務', 'Search members, callsigns or roles'),
  'searchButton': ('搜索', '搜尋', 'Search'),
  'previous': ('上一页', '上一頁', 'Previous'),
  'next': ('下一页', '下一頁', 'Next'),
  'empty': (
    '没有匹配的成员，请换个关键词。',
    '沒有符合的成員，請換個關鍵字。',
    'No matching members. Try another search.',
  ),
  'unavailable': (
    '暂时无法读取组织资料，请重试。',
    '暫時無法讀取組織資料，請重試。',
    'Organization details are unavailable. Try again.',
  ),
  'identityUnavailable': (
    '账号状态已变化，请返回组织列表重新打开。',
    '帳號狀態已變更，請返回組織清單重新開啟。',
    'Your account has changed. Open the organization again from the list.',
  ),
  'notAllowed': (
    '当前无法访问此组织，请返回组织列表刷新。',
    '目前無法存取此組織，請返回組織清單重新整理。',
    'This organization is no longer accessible. Refresh the organization list.',
  ),
  'refreshRequired': (
    '资料已过期，请刷新组织后重试。',
    '資料已過期，請重新整理組織後再試。',
    'These details have expired. Refresh the organization and try again.',
  ),
  'dataInvalid': (
    '组织资料读取不完整，请刷新重试。',
    '組織資料讀取不完整，請重新整理。',
    'Organization details could not be read completely. Refresh to retry.',
  ),
  'mediaFailed': (
    '部分图片未能加载，可刷新重试。',
    '部分圖片未能載入，可重新整理。',
    'Some images could not be loaded. Refresh to retry.',
  ),
  'contacts': ('组织联系方式', '組織聯絡方式', 'Organization contacts'),
  'website': ('网站', '網站', 'Website'),
  'copy': ('复制', '複製', 'Copy'),
  'copyAll': ('复制全部', '複製全部', 'Copy all'),
  'copiedAll': ('全部联系方式已复制。', '全部聯絡方式已複製。', 'All contacts copied.'),
  'copied': ('已复制', '已複製', 'Copied'),
  'copyFailed': ('复制失败，请重试。', '複製失敗，請重試。', 'Could not copy. Try again.'),
  'contactCopyFailed': (
    '无法访问剪贴板，请选中文字手动复制。',
    '無法存取剪貼簿，請選取文字手動複製。',
    'Clipboard unavailable. Select the text to copy it manually.',
  ),
  'language': ('交流语言', '交流語言', 'Language'),
  'activity': ('活跃时间', '活躍時間', 'Active hours'),
  'systems': ('活动星系', '活動星系', 'Systems'),
  'server': ('服务器', '伺服器', 'Server'),
  'ship': ('飞船', '飛船', 'Ship'),
  'location': ('位置', '位置', 'Location'),
  'hidden': ('暂无可见信息', '暫無可見資訊', 'No visible information'),
  'online': ('应用在线', '應用程式線上', 'App online'),
  'offline': ('离线', '離線', 'Offline'),
  'gaming': ('游戏中', '遊戲中', 'In game'),
  'owner': ('组织所有者', '組織擁有者', 'Owner'),
  'self': ('你', '你', 'You'),
  'arrival': ('到达待确认', '抵達待確認', 'Arrival awaiting confirmation'),
  'joined': ('加入时间', '加入時間', 'Joined'),
  'updated': ('资料更新', '資料更新', 'Updated'),
  'nextDay': ('次日', '翌日', 'next day'),
};

String workspaceText(BuildContext context, String key) {
  final locale = AppStrings.of(context).locale;
  final value =
      communityWorkspaceCopy[key] ?? communityWorkspaceCopy['unavailable']!;
  if (locale.languageCode == 'en') return value.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}

String workspaceDays(BuildContext context, Iterable<String> days) {
  const order = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final normalized = days.map((day) {
    final lower = day.toLowerCase();
    return order.where((id) => lower.startsWith(id)).firstOrNull ?? day;
  }).toSet();
  final locale = AppStrings.of(context).locale;
  final english = locale.languageCode == 'en';
  final traditional = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
  bool exactly(List<String> group) =>
      normalized.length == group.length && normalized.containsAll(group);
  if (exactly(order)) return english ? 'Every day' : '每日';
  if (exactly(order.take(5).toList())) return english ? 'Weekdays' : '工作日';
  if (exactly(order.skip(5).toList())) {
    return english
        ? 'Weekends'
        : traditional
        ? '週末'
        : '周末';
  }
  return [
    ...order.where(normalized.contains),
    ...normalized.where((day) => !order.contains(day)),
  ].map((day) => workspaceDay(context, day)).join(english ? ', ' : '、');
}

String workspaceDay(BuildContext context, String day) {
  final normalized = day.toLowerCase();
  final index = const [
    'sun',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
  ].indexWhere((name) => normalized.startsWith(name));
  if (index < 0) return day;
  final locale = AppStrings.of(context).locale;
  if (locale.languageCode == 'en') {
    return const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][index];
  }
  final traditional = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
  return '${traditional ? '週' : '周'}${const ['日', '一', '二', '三', '四', '五', '六'][index]}';
}
