import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'community_creation_copy.dart';

const communityProfileCopy = <String, (String, String, String)>{
  'nameHint': (
    '支持各种语言，1–32 个字符。改名后将通知组织成员。',
    '支援各種語言，1–32 個字元。更名後將通知組織成員。',
    'Use 1–32 characters in any language. Members will be notified of the change.',
  ),
  'nameInvalid': (
    '请输入 1–32 个字符的组织名称，不可包含换行或控制字符。',
    '請輸入 1–32 個字元的組織名稱，不可包含換行或控制字元。',
    'Enter an organization name of 1–32 characters without line breaks or control characters.',
  ),
  'expandHeader': ('展开信息栏', '展開資訊欄', 'Expand information'),
  'collapseHeader': ('收起信息栏', '收起資訊欄', 'Collapse information'),
  'description': ('组织介绍（对外展示）', '組織介紹（對外展示）', 'Description (public-facing)'),
  'quotaCore': ('玩法主轴', '玩法主軸', 'Core gameplay'),
  'quotaStyle': ('风格与规模', '風格與規模', 'Style & scale'),
  'quotaShared': ('共享名额', '共用名額', 'Shared slots'),
  'quotaHelp': (
    '主轴必选 1–3 项；风格与行动规模合用 2 个专属名额，超出后与其他标签共享 5 项。',
    '主軸必選 1–3 項；風格與行動規模合用 2 個專屬名額，超出後與其他標籤共用 5 項。',
    'Choose 1–3 core tags. Style and operation scale share 2 reserved slots; extras and other tags share 5 slots.',
  ),
  'shortTextHint': (
    '中文计 2，英文计 1；中英混排合并计算。',
    '中文計 2，英文計 1；中英混排合併計算。',
    'ASCII characters count as 1; other characters count as 2.',
  ),
  'textTooLong': (
    '已超出字数上限，请缩短后保存。',
    '已超出字數上限，請縮短後儲存。',
    'Over the limit. Shorten this text before saving.',
  ),
  'recruitmentGroup': ('招募', '招募', 'Recruitment'),
  'joiningGroup': ('加入方式', '加入方式', 'Joining'),
  'visibilityGroup': ('公开展示', '公開展示', 'Public visibility'),
  'recruitingLock': (
    '招募期间保持公开展示，加入方式不能设为仅邀请。',
    '招募期間保持公開展示，加入方式不能設為僅邀請。',
    'Recruiting keeps discovery enabled and excludes invite-only joining.',
  ),
  'languagesHint': (
    '可选择多种交流语言。',
    '可選擇多種交流語言。',
    'Select one or more communication languages.',
  ),
  'legacySchedule': (
    '原活动说明（选择时段后更新）',
    '原活動說明（選擇時段後更新）',
    'Previous activity notes (updated when scheduling)',
  ),
  'hour': ('时', '時', 'Hour'),
  'minute': ('分', '分', 'Minute'),
  'durationHour': ('小时', '小時', 'h'),
  'durationMinute': ('分钟', '分鐘', 'min'),
  'activeFrom': ('开始时间', '開始時間', 'Start time'),
  'activeTo': ('结束时间', '結束時間', 'End time'),
  'timeZoneId': ('时区', '時區', 'Time zone'),
  'timeInvalid': (
    '请输入 HH:mm 格式的有效时间。',
    '請輸入 HH:mm 格式的有效時間。',
    'Enter a valid time in HH:mm format.',
  ),
  '所有玩家': ('所有玩家', '所有玩家', 'All players'),
  '新手友好': ('新手友好', '新手友善', 'New-player friendly'),
  '战斗玩家': ('战斗玩家', '戰鬥玩家', 'Combat players'),
  '工业玩家': ('工业玩家', '工業玩家', 'Industrial players'),
  '贸易与货运': ('贸易与货运', '貿易與貨運', 'Trade and cargo'),
  '医疗与支援': ('医疗与支援', '醫療與支援', 'Medical and support'),
  '休闲': ('休闲', '休閒', 'Casual'),
  '固定开黑': ('固定开黑', '固定開黑', 'Regular sessions'),
  '周末行动': ('周末行动', '週末行動', 'Weekend sessions'),
  '高频组织': ('高频组织', '高頻組織', 'Frequent sessions'),
  '大型行动前通知': ('大型行动前通知', '大型行動前通知', 'Before major operations'),
  'editProfile': ('编辑组织资料', '編輯組織資料', 'Edit organization profile'),
  'basic': ('基本资料', '基本資料', 'Basic profile'),
  'discovery': ('招募与公开', '招募與公開', 'Recruitment & visibility'),
  'schedule': ('活动安排', '活動安排', 'Activity schedule'),
  'contacts': ('联系方式', '聯絡方式', 'Contact details'),
  'basicHelp': (
    '设置组织标志、简介与特色标签。',
    '設定組織標誌、簡介與特色標籤。',
    'Set your organization logo, description and tags.',
  ),
  'discoveryHelp': (
    '设置招募偏好，以及玩家可以看到哪些资料。',
    '設定招募偏好，以及玩家可以看到哪些資料。',
    'Choose recruitment preferences and which details players can see.',
  ),
  'scheduleHelp': (
    '填写常用时区、活动时段与主要活动星系。',
    '填寫常用時區、活動時段與主要活動星系。',
    'Set your time zone, activity windows and main systems.',
  ),
  'contactsHelp': (
    '这些联系方式会显示在组织内部，方便成员联系。对外展示需另外开启。',
    '這些聯絡方式會顯示在組織內部，方便成員聯絡。對外展示需另外開啟。',
    'These contacts are shown inside your organization for members. Public visibility is enabled separately.',
  ),
  'save': ('保存更改', '儲存變更', 'Save changes'),
  'saveProfileDraft': (
    '一起保存组织资料各分类中的更改。',
    '一起儲存組織資料各分類中的變更。',
    'Save changes from all organization profile categories together.',
  ),
  'saved': ('更改已保存', '變更已儲存', 'Changes saved'),
  'saving': ('正在保存并读取最新资料…', '正在儲存並讀取最新資料…', 'Saving and refreshing profile…'),
  'clean': ('没有未保存的更改', '沒有未儲存的變更', 'No unsaved changes'),
  'dirty': ('有未保存的更改', '有未儲存的變更', 'Unsaved changes'),
  'close': ('关闭', '關閉', 'Close'),
  'discard': ('放弃更改', '放棄變更', 'Discard changes'),
  'leaveTitle': ('保存组织资料的更改？', '儲存組織資料的變更？', 'Save profile changes?'),
  'leaveBody': (
    '离开前可以保存，或放弃本次编辑。',
    '離開前可以儲存，或放棄本次編輯。',
    'Save before leaving, or discard this draft.',
  ),
  'reload': ('重新读取资料', '重新讀取資料', 'Reload profile'),
  'reloadTitle': ('放弃草稿并重新读取？', '放棄草稿並重新讀取？', 'Discard draft and reload?'),
  'reloadBody': (
    '将读取服务器当前资料并替换本次输入。结果未确认的保存不会重复发送。',
    '將讀取伺服器目前資料並取代本次輸入。結果未確認的儲存不會重複傳送。',
    'Replace this draft with the current server profile. Unconfirmed saves will not be sent again.',
  ),
  'unavailable': (
    '资料暂时无法读取，请重试。',
    '資料暫時無法讀取，請重試。',
    'Profile unavailable. Try again.',
  ),
  'invalidDraft': (
    '部分资料不符合要求，请检查输入后再保存。',
    '部分資料不符合要求，請檢查輸入後再儲存。',
    'Some values are invalid. Check the form and save again.',
  ),
  'dataInvalid': (
    '资料格式无法识别，请重新读取或更新客户端。',
    '資料格式無法辨識，請重新讀取或更新用戶端。',
    'Profile format is unsupported. Reload or update the client.',
  ),
  'conflict': (
    '资料已被其他人更新。你的输入仍保留，请重新读取后再编辑。',
    '資料已被其他人更新。你的輸入仍保留，請重新讀取後再編輯。',
    'Someone else updated this profile. Your draft is preserved. Reload before editing again.',
  ),
  'outcomeUnknown': (
    '暂时无法确认保存结果。请重新读取资料，不要重复提交。',
    '暫時無法確認儲存結果。請重新讀取資料，不要重複提交。',
    'Save result is unconfirmed. Reload the profile instead of submitting again.',
  ),
  'refreshAfterSave': (
    '服务器已确认保存，但最新资料尚未读回。请重新读取。',
    '伺服器已確認儲存，但最新資料尚未讀回。請重新讀取。',
    'The server confirmed the save, but refresh failed. Reload the profile.',
  ),
  'refreshRequired': (
    '编辑已过期，请关闭后重新打开组织资料。',
    '編輯已過期，請關閉後重新開啟組織資料。',
    'This editor expired. Close it and reopen the profile.',
  ),
  'identityUnavailable': (
    '账号已变化，请重新打开组织。',
    '帳號已變更，請重新開啟組織。',
    'Your account changed. Reopen the organization.',
  ),
  'notAllowed': (
    '当前账号没有编辑这部分资料的权限。',
    '目前帳號沒有編輯這部分資料的權限。',
    'Your account cannot edit these profile fields.',
  ),
  'busy': (
    '正在处理另一个操作，请稍后重试。',
    '正在處理另一個操作，請稍後重試。',
    'Another operation is in progress. Try again shortly.',
  ),
  'optionsFailed': (
    '选择项暂时无法读取；已有资料会保留。',
    '選項暫時無法讀取；既有資料會保留。',
    'Options could not be loaded. Existing values are preserved.',
  ),
  'logoText': ('标志文字', '標誌文字', 'Logo text'),
  'logoExists': ('已设置组织标志', '已設定組織標誌', 'Organization logo set'),
  'logoEmpty': ('未设置组织标志', '未設定組織標誌', 'No organization logo'),
  'imageHint': (
    '图片在保存更改时上传。',
    '圖片在儲存變更時上傳。',
    'Images upload when you save changes.',
  ),
  'removeBanner': ('移除现有横幅', '移除現有橫幅', 'Remove current banner'),
  'recruitingEnabled': ('开启招募', '開啟招募', 'Recruiting'),
  'recruitingTarget': ('招募对象', '招募對象', 'Recruitment audience'),
  'recruitingNote': ('招募说明', '招募說明', 'Recruitment note'),
  'inviteCodeCreationPolicy': (
    '谁可以生成邀请码',
    '誰可以產生邀請碼',
    'Who can create invite codes',
  ),
  'fleetInvitationCardPolicy': (
    '谁可以分享邀请卡',
    '誰可以分享邀請卡',
    'Who can share invitation cards',
  ),
  'all_members': ('所有成员', '所有成員', 'All members'),
  'management': ('管理成员', '管理成員', 'Management'),
  'commander': ('负责人', '負責人', 'Owner'),
  'publicListingEnabled': (
    '出现在寻找组织中',
    '出現在尋找組織中',
    'List in organization discovery',
  ),
  'publicMemberScaleMode': ('公开成员规模', '公開成員規模', 'Public member count'),
  'publicShipScaleMode': ('公开舰船规模', '公開艦船規模', 'Public ship count'),
  'Exact': ('具体人数', '具體人數', 'Exact count'),
  'Approx': ('规模区间', '規模區間', 'Approximate size'),
  'Hidden': ('不显示', '不顯示', 'Hidden'),
  'TypeSummary': ('舰种概览', '艦種概覽', 'Ship type summary'),
  'TotalOnly': ('仅总数', '僅總數', 'Total only'),
  'publicShowDescription': ('公开组织介绍', '公開組織介紹', 'Show description publicly'),
  'publicShowTags': ('公开玩法标签', '公開玩法標籤', 'Show tags publicly'),
  'publicShowActiveSystems': (
    '公开活跃星系',
    '公開活躍星系',
    'Show active systems publicly',
  ),
  'publicShowActivityTime': (
    '公开活动时间',
    '公開活動時間',
    'Show activity times publicly',
  ),
  'language': ('交流语言', '交流語言', 'Communication language'),
  'activityCadence': ('活动频率', '活動頻率', 'Activity cadence'),
  'activeDaysDescription': ('活动日说明', '活動日說明', 'Activity day notes'),
  'activeTime': ('活动时间摘要', '活動時間摘要', 'Activity time summary'),
  'addWindow': ('增加活动时段', '增加活動時段', 'Add time window'),
  'remove': ('移除', '移除', 'Remove'),
  'nextDay': ('结束于次日', '結束於次日', 'Ends next day'),
  'nextDayShort': ('次日', '次日', 'next day'),
  'windowInvalid': (
    '请调整开始和结束时间：每个时段应大于 0、最多 24 小时，跨日状态需与时间一致。',
    '請調整開始與結束時間：每個時段應大於 0、最多 24 小時，跨日狀態需與時間一致。',
    'Choose a window longer than 0 and no longer than 24 hours, with matching overnight status.',
  ),
  'nextDayHint': (
    '结束时间较早时自动跨日；开始与结束相同时为 24 小时。',
    '結束時間較早時自動跨日；開始與結束相同時為 24 小時。',
    'Earlier end times automatically cross midnight. Equal times mean 24 hours.',
  ),
  'lastMinuteHint': (
    '当天已无更晚时间。如需当天结束，请先调整开始时间。',
    '當天已無更晚時間。如需當天結束，請先調整開始時間。',
    'No later time remains today. Choose an earlier start for a same-day window.',
  ),
  'daysRequired': (
    '每个时段至少选择一天。',
    '每個時段至少選擇一天。',
    'Select at least one day for each window.',
  ),
  'systemsRequired': (
    '至少选择一个活跃星系。',
    '至少選擇一個活躍星系。',
    'Select at least one active system.',
  ),
  'websiteUrl': ('组织网站', '組織網站', 'Organization website'),
  'platform': ('平台', '平台', 'Platform'),
  'contactValue': ('账号、群号或链接', '帳號、群號或連結', 'Account, group ID or link'),
  'addContact': ('增加联系方式', '增加聯絡方式', 'Add contact'),
  'privateContacts': (
    '这些联系方式目前仅组织内部可见。普通保存不会将其公开。',
    '這些聯絡方式目前僅組織內部可見。一般儲存不會將其公開。',
    'These contacts are internal. Saving other changes will not publish them.',
  ),
  'publicContacts': (
    '这些联系方式会公开显示在组织资料中。',
    '這些聯絡方式會公開顯示在組織資料中。',
    'These contacts are displayed publicly on the organization profile.',
  ),
  'publishContacts': ('确认公开联系方式', '確認公開聯絡方式', 'Confirm contact publication'),
  'publishBody': (
    '保存后，组织外的用户也可以看到这些联系方式。是否公开？',
    '儲存後，組織外的使用者也可以看到這些聯絡方式。是否公開？',
    'After saving, people outside this organization can see these contacts. Publish them?',
  ),
  'emailNotificationsEnabled': (
    '接收组织邮件通知',
    '接收組織郵件通知',
    'Receive organization email notifications',
  ),
  'unknownTags': (
    '部分现有标签不在目录中。更换标签会替换当前标签，请先确认。',
    '部分既有標籤不在目錄中。更換標籤會取代目前標籤，請先確認。',
    'Some current tags are not in the catalog. Choosing tags will replace the current list.',
  ),
};

String profileText(BuildContext context, String key) {
  final value = communityProfileCopy[key] ?? communityCreationCopy[key];
  if (value == null) return key;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
