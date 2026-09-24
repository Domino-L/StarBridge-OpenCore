import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityCreationCopy = <String, (String, String, String)>{
  'title': ('创建组织', '建立組織', 'Create organization'),
  'name': ('组织名称', '組織名稱', 'Organization name'),
  'nameHint': (
    '4–32 位英文、数字、空格、短横线或下划线',
    '4–32 位英文、數字、空格、短橫線或底線',
    '4–32 letters, numbers, spaces, hyphens or underscores',
  ),
  'code': ('组织识别码', '組織識別碼', 'Organization code'),
  'codeHint': (
    '3–10 位英文或数字，将自动转为大写',
    '3–10 位英文或數字，將自動轉為大寫',
    '3–10 letters or numbers; converted to uppercase',
  ),
  'description': ('组织介绍', '組織介紹', 'Description'),
  'logo': ('组织标志', '組織標誌', 'Organization logo'),
  'pickLogo': ('选择图片并裁剪', '選擇圖片並裁切', 'Choose and crop image'),
  'removeLogo': ('移除图片', '移除圖片', 'Remove image'),
  'imageHint': (
    'PNG、JPG 或 BMP；确认创建前不会上传。',
    'PNG、JPG 或 BMP；確認建立前不會上傳。',
    'PNG, JPG or BMP. Uploaded only when you create the organization.',
  ),
  'imageUnavailable': (
    '当前版本无法选择图片，请更新客户端。',
    '目前版本無法選擇圖片，請更新用戶端。',
    'Image selection is unavailable. Update the client.',
  ),
  'exampleHint': (
    '仅预览创建流程，不上传图片或创建真实组织；退出示例后清除。',
    '僅預覽建立流程，不上傳圖片或建立真實組織；退出範例後清除。',
    'Preview only. No images are uploaded or real organizations created. Changes clear when you leave the example.',
  ),
  'imageFailed': (
    '图片无法使用，请重新选择。',
    '圖片無法使用，請重新選擇。',
    'This image could not be used. Choose another image.',
  ),
  'crop': ('裁剪组织标志', '裁切組織標誌', 'Crop organization logo'),
  'cropHint': (
    '拖动选框调整位置，使用滑块调整大小。',
    '拖曳選框調整位置，使用滑桿調整大小。',
    'Drag the frame to position it. Use the sliders to adjust the crop.',
  ),
  'size': ('裁剪范围', '裁切範圍', 'Crop size'),
  'horizontal': ('水平位置', '水平位置', 'Horizontal position'),
  'vertical': ('垂直位置', '垂直位置', 'Vertical position'),
  'useImage': ('采用图片', '採用圖片', 'Use image'),
  'tags': ('玩法标签', '玩法標籤', 'Activity tags'),
  'chooseTags': ('选择标签', '選擇標籤', 'Choose tags'),
  'systems': ('活跃星系', '活躍星系', 'Active systems'),
  'joinPolicy': ('加入方式', '加入方式', 'Joining policy'),
  'Open': ('直接加入', '直接加入', 'Open'),
  'Approval': ('申请加入', '申請加入', 'Approval required'),
  'Invite': ('仅邀请加入', '僅邀請加入', 'Invite only'),
  'activity': ('每日活动时间', '每日活動時間', 'Daily activity hours'),
  'from': ('开始时间', '開始時間', 'From'),
  'to': ('结束时间', '結束時間', 'Until'),
  'overnight': (
    '结束时间不晚于开始时间时，按次日结束。',
    '結束時間不晚於開始時間時，按次日結束。',
    'An end time at or before the start time means the following day.',
  ),
  'zone': ('活动时区', '活動時區', 'Activity time zone'),
  'required': ('请填写此项。', '請填寫此項。', 'Complete this field.'),
  'systemRequired': ('请至少选择一个星系。', '請至少選擇一個星系。', 'Choose at least one system.'),
  'cancel': ('取消', '取消', 'Cancel'),
  'continue': ('继续编辑', '繼續編輯', 'Keep editing'),
  'discard': ('放弃草稿', '放棄草稿', 'Discard draft'),
  'leaveTitle': ('放弃创建组织？', '放棄建立組織？', 'Discard this organization draft?'),
  'leaveBody': (
    '尚未提交的资料和图片将被清除。',
    '尚未提交的資料和圖片將被清除。',
    'The unsubmitted details and image will be cleared.',
  ),
  'confirmBody': (
    '创建后你将成为该组织的负责人，已加入的其它组织不受影响。',
    '建立後你將成為此組織的負責人，已加入的其他組織不受影響。',
    'You will own this organization. Your other organization memberships will not change.',
  ),
  'creating': ('正在创建并确认结果…', '正在建立並確認結果…', 'Creating and confirming…'),
  'retry': ('重新读取', '重新讀取', 'Reload'),
  'checkMine': ('检查我的组织', '檢查我的組織', 'Check my organizations'),
  'optionsUnavailable': (
    '暂时无法读取创建选项，请检查登录状态后重试。',
    '暫時無法讀取建立選項，請檢查登入狀態後重試。',
    'Creation options could not be loaded. Check your sign-in status and retry.',
  ),
  'outcomeUnknown': (
    '尚未确认创建结果。请先检查我的组织，避免重复创建。',
    '尚未確認建立結果。請先檢查我的組織，避免重複建立。',
    'Creation is not confirmed. Check your organizations before trying to create another.',
  ),
  'invalidDraft': (
    '资料不符合要求，请检查名称、识别码、活动时间和所选项目。',
    '資料不符合要求，請檢查名稱、識別碼、活動時間和所選項目。',
    'Check the name, code, activity hours and selections before submitting again.',
  ),
  'codeUnavailable': (
    '此识别码已被使用，请更换后重试。',
    '此識別碼已被使用，請更換後重試。',
    'This code is already in use. Choose another code.',
  ),
  'upgradeRequired': (
    '服务暂不支持创建组织，请稍后再试。',
    '服務暫不支援建立組織，請稍後再試。',
    'The service does not support organization creation yet. Try again later.',
  ),
  'rejected': (
    '创建未完成，资料已保留。请检查账号权限与网络后重试。',
    '建立未完成，資料已保留。請檢查帳號權限與網路後重試。',
    'The organization was not created. Your draft is preserved. Check account access and connectivity.',
  ),
};

String creationText(BuildContext context, String key) {
  final locale = AppStrings.of(context).locale;
  final value =
      communityCreationCopy[key] ?? communityCreationCopy['rejected']!;
  if (locale.languageCode == 'en') return value.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
