import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityAnnouncementsCopy = <String, (String, String, String)>{
  'center': ('组织公告', '組織公告', 'Organization announcements'),
  'current': ('当前公告', '目前公告', 'Current announcement'),
  'history': ('公告历史', '公告歷史', 'Announcement history'),
  'empty': ('暂无当前公告', '暫無目前公告', 'No current announcement'),
  'emptyHistory': ('还没有历史公告。', '還沒有歷史公告。', 'No announcement history yet.'),
  'emptyBody': (
    '本公告没有补充正文。',
    '本公告沒有補充正文。',
    'This announcement has no additional text.',
  ),
  'create': ('发布新公告', '發布新公告', 'New announcement'),
  'edit': ('编辑当前公告', '編輯目前公告', 'Edit current announcement'),
  'publish': ('发布公告', '發布公告', 'Publish announcement'),
  'save': ('保存修订', '儲存修訂', 'Save changes'),
  'withdraw': ('撤下公告', '撤下公告', 'Withdraw announcement'),
  'withdrawBody': (
    '撤下后不再显示为当前公告，历史记录仍会保留。',
    '撤下後不再顯示為目前公告，歷史紀錄仍會保留。',
    'It will no longer be current. Its history will be kept.',
  ),
  'publishBody': (
    '新公告发布后，原当前公告将移入历史。',
    '新公告發布後，原目前公告將移入歷史。',
    'Publishing moves the previous announcement into history.',
  ),
  'title': ('公告标题', '公告標題', 'Announcement title'),
  'content': ('正文（可留空）', '正文（可留空）', 'Content (optional)'),
  'details': ('查看详情', '查看詳情', 'View details'),
  'back': ('返回公告中心', '返回公告中心', 'Back to announcements'),
  'refresh': ('刷新公告', '重新整理公告', 'Refresh announcements'),
  'more': ('查看更多历史', '查看更多歷史', 'Load more history'),
  'close': ('关闭', '關閉', 'Close'),
  'cancel': ('取消', '取消', 'Cancel'),
  'discard': ('丢弃草稿', '捨棄草稿', 'Discard draft'),
  'stay': ('继续编辑', '繼續編輯', 'Keep editing'),
  'leaveTitle': (
    '丢弃未保存的公告草稿？',
    '捨棄未儲存的公告草稿？',
    'Discard the unsaved announcement?',
  ),
  'leaveBody': (
    '草稿不会保存。结果尚未确认的操作可能已经生效，请先刷新检查，避免重复发布。',
    '草稿不會儲存。結果尚未確認的操作可能已經生效，請先重新整理檢查，避免重複發布。',
    'The draft will not be kept. An unconfirmed action may already have succeeded; refresh and check before publishing again.',
  ),
  'published': ('已发布', '已發布', 'Published'),
  'archived': ('已归档', '已封存', 'Archived'),
  'withdrawn': ('已撤下', '已撤下', 'Withdrawn'),
  'saved': ('公告修订已保存。', '公告修訂已儲存。', 'Announcement changes saved.'),
  'withdrawnSuccess': (
    '公告已撤下，历史已保留。',
    '公告已撤下，歷史已保留。',
    'Announcement withdrawn. History is kept.',
  ),
  'author': ('发布者', '發布者', 'Published by'),
  'editor': ('最后编辑者', '最後編輯者', 'Last edited by'),
  'publishedAt': ('发布时间', '發布時間', 'Published'),
  'updatedAt': ('更新时间', '更新時間', 'Updated'),
  'archivedAt': ('归档时间', '封存時間', 'Archived'),
  'withdrawnAt': ('撤下时间', '撤下時間', 'Withdrawn'),
  'loading': ('正在读取公告…', '正在讀取公告…', 'Loading announcements…'),
  'saving': ('正在保存…', '正在儲存…', 'Saving…'),
  'imageFailed': (
    '头像未能加载，点击重试。',
    '頭像未能載入，點擊重試。',
    'Avatars could not load. Retry.',
  ),
  'unavailable': (
    '公告暂时无法读取，请刷新重试。',
    '公告暫時無法讀取，請重新整理。',
    'Announcements are unavailable. Refresh to retry.',
  ),
  'dataInvalid': (
    '内容不完整或超出限制，请检查标题和正文。',
    '內容不完整或超出限制，請檢查標題與正文。',
    'Content is incomplete or exceeds its limit. Check the title and text.',
  ),
  'announcementsChanged': (
    '公告已发生变化。草稿已保留，请刷新检查；编辑旧公告前需重新打开当前公告。',
    '公告已變更。草稿已保留，請重新整理檢查；編輯舊公告前需重新開啟目前公告。',
    'Announcements changed. Your draft is kept. Refresh and reopen the current announcement before editing it.',
  ),
  'notAllowed': (
    '你已没有此公告的访问或管理权限。',
    '你已沒有此公告的存取或管理權限。',
    'You no longer have permission to view or manage this announcement.',
  ),
  'identityUnavailable': (
    '账号状态已变化，请重新打开组织。',
    '帳號狀態已變更，請重新開啟組織。',
    'Your account changed. Open the organization again.',
  ),
  'refreshRequired': (
    '此页面已过期，请返回组织列表后重新打开。',
    '此頁面已過期，請返回組織清單後重新開啟。',
    'This page expired. Reopen it from the organization list.',
  ),
  'notFound': (
    '此组织或公告已不可用，请刷新检查。',
    '此組織或公告已無法使用，請重新整理檢查。',
    'The organization or announcement is unavailable. Refresh to check.',
  ),
  'outcomeUnknown': (
    '尚未确认是否保存成功。草稿已保留，请刷新公告核对，避免重复发布。',
    '尚未確認是否儲存成功。草稿已保留，請重新整理公告核對，避免重複發布。',
    'Saving is unconfirmed. Your draft is kept. Refresh announcements and check before publishing again.',
  ),
  'reviewed': ('已核对，继续处理', '已核對，繼續處理', 'Checked, continue'),
  'reviewBody': (
    '请确认已检查最新公告和历史。继续不会自动重发，草稿仍保留。',
    '請確認已檢查最新公告與歷史。繼續不會自動重送，草稿仍保留。',
    'Confirm you checked the latest announcement and history. Continuing does not resend anything. Your draft is kept.',
  ),
  'busy': (
    '正在处理上一项操作，请稍后重试。',
    '正在處理上一項操作，請稍後重試。',
    'Another action is in progress. Try again shortly.',
  ),
  'rateLimited': (
    '操作过于频繁，请稍后再试。',
    '操作過於頻繁，請稍後再試。',
    'Too many requests. Try again shortly.',
  ),
  'intentConflict': (
    '操作内容已变化，请刷新核对后重试。',
    '操作內容已變更，請重新整理核對後重試。',
    'The action changed. Refresh and check before trying again.',
  ),
};

String communityAnnouncementText(BuildContext context, String key) {
  final row =
      communityAnnouncementsCopy[key] ??
      communityAnnouncementsCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? row.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? row.$2
      : row.$1;
}
