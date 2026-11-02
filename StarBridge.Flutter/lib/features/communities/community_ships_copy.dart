import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import '../../shared/ships/ship_reviewed_display.dart';

const communityShipsCopy = <String, (String, String, String)>{
  'sharedImageCount': (
    '已共享 {count} 张自定义图片',
    '已共享 {count} 張自訂圖片',
    '{count} custom images shared',
  ),
  'clearSharedImages': (
    '清除共享图片，保留舰船',
    '清除共享圖片，保留艦船',
    'Remove shared images; keep ships',
  ),
  'customImage': ('成员共享图片', '成員共享圖片', 'Member-shared image'),
  'customImageUnavailable': (
    '共享图片暂时不可用。',
    '共享圖片暫時無法使用。',
    'The shared image is unavailable.',
  ),
  'reportSourceRetired': (
    '原舰队内容已关闭。仍可查询本人已提交的举报结果。',
    '原艦隊內容已關閉。仍可查詢本人已提交的檢舉結果。',
    'Fleet content is closed. You can still check your submitted report.',
  ),
  'reportCheckUnavailable': (
    '当前无法查询举报结果。连接恢复后可再次查询，请勿重复提交。',
    '目前無法查詢檢舉結果。連線恢復後可再次查詢，請勿重複提交。',
    'The result is unavailable right now. Check again when connected; do not submit again.',
  ),
  "ownSharingTitle": ("我的共享设置", "我的共享設定", "My sharing settings"),
  "ownSharingScope": (
    "选择共享方式和允许舰队查看的舰船。未选择的舰船不会公开。",
    "選擇共享方式與允許艦隊查看的艦船。未選擇的艦船不會公開。",
    "Choose how to share and which ships fleet members may view. Unselected ships remain private.",
  ),
  "ownSharingFleet": ("舰队共享范围", "艦隊共享範圍", "Fleet sharing scope"),
  "ownSharingStrategy": ("共享方式", "共享方式", "Sharing mode"),
  "notShared": ("不共享", "不共享", "Not shared"),
  "organizationPool": (
    "加入舰队共享库",
    "加入艦隊共享庫",
    "Share selected ships with the fleet",
  ),
  "operationOnly": ("仅行动中共享", "僅行動中共享", "Share only during operations"),
  "ownSharingChoose": ("请选择共享方式", "請選擇共享方式", "Choose a sharing mode"),
  "ownSharingSelectionRequired": (
    "尚未为当前舰队设置共享方式。",
    "尚未為目前艦隊設定共享方式。",
    "No sharing choice has been saved for this fleet.",
  ),
  "ownSharingStale": (
    "舰队资格资料需要更新。仍可撤回已有共享。",
    "艦隊資格資料需要更新。仍可撤回現有共享。",
    "Fleet membership needs an update. You can still withdraw existing sharing.",
  ),
  "ownSharingForbidden": (
    "目前不能新增共享。仍可撤回已有共享。",
    "目前不能新增共享。仍可撤回現有共享。",
    "New sharing is not allowed right now. You can still withdraw existing sharing.",
  ),
  "ownSharingUnavailable": (
    "暂时无法读取完整共享资料。仍可撤回已有共享。",
    "暫時無法讀取完整共享資料。仍可撤回現有共享。",
    "Complete sharing details are unavailable right now. You can still withdraw existing sharing.",
  ),
  "ownSharingCurrent": (
    "共享只对所选舰队有效。",
    "共享只對所選艦隊有效。",
    "Sharing applies only to the selected fleet.",
  ),
  "ownSharingPreviousSelected": (
    "此前共享的舰船数：",
    "先前共享的艦船數：",
    "Previously selected ships:",
  ),
  "ownSharingOperationHint": (
    "此设置不会加入舰队共享库，也不会自动授权任何行动查看舰船。",
    "此設定不會加入艦隊共享庫，也不會自動授權任何行動查看艦船。",
    "This keeps your ships out of the fleet pool. It does not give any operation access to them.",
  ),
  "ownSharingEmpty": (
    "没有可选的已保存舰船。",
    "沒有可選的已儲存艦船。",
    "No saved ships are available to select.",
  ),
  "ownSharingMissing": (
    "本机机库中已找不到此舰船",
    "本機機庫中已找不到此艦船",
    "This ship is no longer in the local hangar",
  ),
  "ownSharingRevoke": ("停止此舰队共享", "停止此艦隊共享", "Stop sharing with this fleet"),
  "ownSharingSave": ("保存共享设置", "儲存共享設定", "Save sharing settings"),

  'sharingImages': ('同时分享自定义图片', '同時分享自訂圖片', 'Include custom images'),
  'sharingImagesHint': (
    '本次保存会上传本机自定义图片，供所选组织成员查看。请确认图片中没有隐私信息。',
    '本次儲存會上傳本機自訂圖片，供所選組織成員查看。請確認圖片中沒有隱私資訊。',
    'This save uploads local custom images for members of the selected organizations. Check that the images contain no private information.',
  ),
  'refreshFailed': (
    '更新未完成，显示上次读取的资料。',
    '更新未完成，顯示上次讀取的資料。',
    'Update incomplete. Showing previously loaded data.',
  ),
  ...shipGroundSizeLabels,
  'fleetSummary': ('舰船汇总', '艦船彙總', 'Fleet summary'),
  'crossDistribution': ('规格 × 类型', '規格 × 類型', 'Size × category'),
  'crossHint': (
    '按舰船数量比较；颜色表示类型。',
    '按艦船數量比較；顏色表示類型。',
    'Compare ship counts; colors identify categories.',
  ),
  'crossTable': ('查看精确数量表', '查看精確數量表', 'View exact counts'),
  'chartHint': (
    '悬停或点击色块，查看数量与占比。',
    '懸停或點擊色塊，查看數量與佔比。',
    'Hover or select a segment for counts and shares.',
  ),
  'shipsUnit': ('艘', '艘', 'ships'),
  'ofSize': ('占该规格', '佔該規格', 'of this size'),
  'ofFleet': ('占全库', '佔全庫', 'of the fleet'),
  'total': ('合计', '合計', 'Total'),
  'noSharedShips': ('暂无可见共享舰船', '暫無可見共享艦船', 'No visible shared ships'),
  'knownValueHint': (
    '仅计入有价格资料的舰船。',
    '僅計入有價格資料的艦船。',
    'Includes only ships with known prices.',
  ),
  'amongKnownPrices': ('在已知价格舰船中', '在已知價格艦船中', 'Among ships with known prices'),
  'modelCount': ('型号', '型號', 'Models'),
  'sharingMembers': ('共享成员', '共享成員', 'Sharing members'),
  'noPriceData': ('暂无价格资料', '暫無價格資料', 'No price data'),
  'offlineShips': ('持有人离线的舰船', '持有人離線的艦船', 'Ships with offline owners'),
  'shipColumn': ('舰船', '艦船', 'Ship'),
  'priceColumn': ('参考价', '參考價', 'Price'),
  'specRole': ('规格与类别', '規格與類別', 'Size and category'),
  'dispatchSummary': ('持有人在线情况', '持有人在線情況', 'Owners online'),
  'viewDistribution': ('查看分布', '查看分布', 'View distribution'),
  'viewDispatch': ('查看持有人在线的舰船', '查看持有人在線的艦船', 'View ships with owner online'),
  'dispatchScope': (
    '按持有人在线状态、可飞状态与替代船资料统计，不代表已安排出动。',
    '按持有人上線狀態、可飛狀態與替代船資料統計，不代表已安排出動。',
    'Counted from owner presence, flight status and loaner data. Not a dispatch plan.',
  ),
  'noneDispatchable': (
    '暂无持有人在线的可飞舰船',
    '暫無持有人在線的可飛艦船',
    'No flyable ships with owner online',
  ),
  'pendingAvailability': ('资料不足', '資料不足', 'Incomplete data'),
  'availabilityShare': ('持有人在线比例', '持有人在線比例', 'Owner online share'),
  'dispatchTypes': ('持有人在线的类型', '持有人在線的類型', 'Categories with owner online'),
  'dispatchTypesLoaners': (
    '持有人在线的类型 · 含替代船',
    '持有人在線的類型 · 含替代船',
    'Categories with owner online · including loaners',
  ),
  'dispatchCandidateHint': (
    '替代船按各自类型计数，不增加拥有数量，也不代表可同时出动。',
    '替代船按各自類型計數，不增加擁有數量，也不代表可同時出動。',
    'Loaners count by their own category, not as additional owned ships or guaranteed simultaneous deployments.',
  ),
  'sharingTitle': ('共享我的机库', '共享我的機庫', 'Share my hangar'),
  'sharingScope': (
    '选择可以查看你机库的组织。新加入的组织不会自动勾选；不会共享实时位置或游戏状态。',
    '選擇可以查看你機庫的組織。新加入的組織不會自動勾選；不會共享即時位置或遊戲狀態。',
    'Choose organizations that can view your hangar. New memberships are not selected automatically. Live location and game status are not shared.',
  ),
  'sharingLegacy': (
    '保存后以本次选择为准，替换旧版的组织共享范围。',
    '儲存後以本次選擇為準，取代舊版的組織共享範圍。',
    'Saving replaces your legacy organization sharing choices.',
  ),
  'sharingSelected': ('已选择', '已選擇', 'Selected'),
  'sharingEmpty': (
    '还没有可共享的组织。',
    '還沒有可共享的組織。',
    'No joined organizations available.',
  ),
  'sharingPublish': ('保存并同步机库', '儲存並同步機庫', 'Save and sync hangar'),
  'sharingSave': ('保存共享范围', '儲存共享範圍', 'Save sharing choices'),
  'sharingUseLocal': ('同时更新为本机机库', '同時更新為本機機庫', 'Also update from this device'),
  'sharingKeepSaved': (
    '保留已保存的舰船，只更改共享组织。',
    '保留已儲存的艦船，只變更共享組織。',
    'Keep saved ships and change only the sharing audience.',
  ),
  'sharingReplaceSaved': (
    '使用本机完整机库替换已保存的舰船资料。',
    '使用本機完整機庫取代已儲存的艦船資料。',
    'Replace saved ship details with this device’s complete hangar.',
  ),
  'sharingRevoke': ('停止组织共享', '停止組織共享', 'Stop organization sharing'),
  'sharingCurrentNone': (
    '当前未向任何组织共享机库。',
    '目前未向任何組織共享機庫。',
    'Your hangar is not currently shared with any organization.',
  ),
  'sharingCurrentSelected': (
    '当前共享组织数：',
    '目前共享組織數：',
    'Currently shared with organizations:',
  ),
  'sharingCurrentLegacy': (
    '当前沿用旧版共享规则，尚未设置明确的组织范围。',
    '目前沿用舊版共享規則，尚未設定明確的組織範圍。',
    'Legacy sharing rules still apply; an explicit organization audience has not been set.',
  ),
  'sharingSetNone': ('设为不向组织共享', '設為不向組織共享', 'Set to no organization sharing'),
  'sharingChanged': (
    '账号或组织已变化，请关闭后重新打开。',
    '帳號或組織已變更，請關閉後重新開啟。',
    'Your account or memberships changed. Close and reopen this window.',
  ),
  'sharingUnavailable': (
    '暂时无法读取共享设置，请刷新重试。',
    '暫時無法讀取共享設定，請重新整理。',
    'Sharing settings are unavailable. Refresh to try again.',
  ),
  'sharingScanRequired': (
    '请先在个人机库完成一次完整扫描，再回来同步。仍可取消已有共享。',
    '請先在個人機庫完成一次完整掃描，再回來同步。仍可取消現有共享。',
    'Complete a full scan in your personal hangar before syncing. You can still revoke existing sharing.',
  ),
  'sharingUpgrade': (
    '机库共享暂未开放，请稍后再试。现有共享设置未改变。',
    '機庫共享暫未開放，請稍後再試。現有共享設定未變更。',
    'Hangar sharing is not available yet. Try again later. Your existing sharing settings are unchanged.',
  ),
  'sharingUnknown': (
    '暂时无法确认是否保存成功。请刷新核对，不要重复提交。',
    '暫時無法確認是否儲存成功。請重新整理核對，不要重複提交。',
    'The save result could not be confirmed. Refresh to check before trying again.',
  ),
  'sharingSaveFailed': (
    '未能保存，请刷新共享设置后重试。',
    '未能儲存，請重新整理共享設定後再試。',
    'Could not save. Refresh sharing settings and try again.',
  ),
  'title': ('组织舰船库', '組織艦船庫', 'Shared fleet'),
  'details': ('查看档案', '查看檔案', 'View details'),
  'view': ('查看', '查看', 'View'),
  'count': ('数量', '數量', 'Ships'),
  'loaners': ('替代船', '替代船', 'Loaners'),
  'loanerHint': (
    '临时替代船，不计入拥有数量与总价值。',
    '臨時替代船，不計入擁有數量與總價值。',
    'Temporary replacements; excluded from owned count and value.',
  ),
  'notFlyable': ('当前不可飞', '目前不可飛', 'Not flyable'),
  'totalValue': ('已知总价值', '已知總價值', 'Known value'),
  'topOwner': ('舰船最多成员', '艦船最多成員', 'Largest hangar'),
  'mostValuable': ('最高价舰船', '最高價艦船', 'Most valuable'),
  'pricedCoverage': ('已公布价格', '已公布價格', 'Known prices'),
  'distribution': ('规格与用途分布', '規格與用途分布', 'Size and role distribution'),
  'dispatchable': ('持有人在线', '持有人在線', 'Owner online'),
  'preferred': ('首选舰船', '首選艦船', 'Preferred ship'),
  'ownerOffline': ('持有人离线', '持有人離線', 'Owner offline'),
  'availabilityUnknown': (
    '资料不足，未计入持有人在线统计',
    '資料不足，未計入持有人在線統計',
    'Not counted: incomplete catalog data',
  ),
  'statisticsLoading': (
    '正在读取全库统计…',
    '正在讀取全庫統計…',
    'Loading full-library statistics…',
  ),
  'statisticsUnavailable': (
    '暂时无法完成全库统计，请重试。',
    '暫時無法完成全庫統計，請重試。',
    'Full-library statistics could not be completed. Retry.',
  ),
  'combat': ('战斗', '戰鬥', 'Combat'),
  'transport': ('运输', '運輸', 'Transport'),
  'industrial': ('工业', '工業', 'Industry'),
  'exploration': ('探索', '探索', 'Exploration'),
  'support': ('支援', '支援', 'Support'),
  'utility': ('其他', '其他', 'Utility'),
  'detailTitle': ('舰船档案', '艦船檔案', 'Ship details'),
  'reportTitle': ('举报舰船图片', '檢舉艦船圖片', 'Report ship image'),
  'reportIntro': (
    '请选择图片存在的问题。举报会附带当前图片标识，供审核人员核对。',
    '請選擇圖片存在的問題。檢舉會附帶目前圖片識別資料，供審核人員核對。',
    'Choose the issue with this image. Its reference will be included for review.',
  ),
  'reportReason': ('举报原因', '檢舉原因', 'Reason'),
  'reportDetails': ('补充说明（可选）', '補充說明（選填）', 'Additional details (optional)'),
  'reportReason_harassment': ('骚扰或辱骂', '騷擾或辱罵', 'Harassment or abuse'),
  'reportReason_spam': ('垃圾信息', '垃圾資訊', 'Spam'),
  'reportReason_impersonation': ('冒充他人', '冒充他人', 'Impersonation'),
  'reportReason_hate_or_threat': ('仇恨或威胁', '仇恨或威脅', 'Hate or threats'),
  'reportReason_inappropriate_content': (
    '不当内容',
    '不當內容',
    'Inappropriate content',
  ),
  'reportReason_fraud_or_scam': ('欺诈或诈骗', '欺詐或詐騙', 'Fraud or scams'),
  'reportReason_privacy': ('侵犯隐私', '侵犯隱私', 'Privacy violation'),
  'reportReason_other': ('其他问题', '其他問題', 'Other issue'),
  'reportSubmit': ('提交举报', '提交檢舉', 'Submit report'),
  'reportCheck': ('查询结果', '查詢結果', 'Check result'),
  'reportBusy': ('正在处理…', '正在處理…', 'Working…'),
  'reportAccepted': (
    '举报已提交，等待审核。',
    '檢舉已提交，等待審核。',
    'Report submitted for review.',
  ),
  'reportUnknown': (
    '暂时无法确认是否提交成功。请查询结果，避免重复举报。',
    '暫時無法確認是否提交成功。請查詢結果，避免重複檢舉。',
    'Submission could not be confirmed. Check the result before reporting again.',
  ),
  'reportDiscardBody': (
    '尚未提交的举报内容将被丢弃。',
    '尚未提交的檢舉內容將被捨棄。',
    'Your unsubmitted report will be discarded.',
  ),
  'reportCloseUnknown': (
    '提交可能已成功。建议先查询结果，避免重复举报。',
    '提交可能已成功。建議先查詢結果，避免重複檢舉。',
    'The report may have been submitted. Check the result before closing to avoid duplicate reports.',
  ),
  'reportKeepQuery': ('继续查询', '繼續查詢', 'Keep checking'),
  'reportKeepEditing': ('继续填写', '繼續填寫', 'Keep editing'),
  'reportDiscard': ('放弃填写', '放棄填寫', 'Discard draft'),
  'reportBack': ('返回档案', '返回檔案', 'Back to details'),
  'reportError_dataInvalid': (
    '内容未通过校验，请检查后重试。',
    '內容未通過驗證，請檢查後重試。',
    'Check the report details and try again.',
  ),
  'reportError_unavailable': (
    '当前无法提交举报，请稍后重试。',
    '目前無法提交檢舉，請稍後重試。',
    'Reporting is unavailable. Try again later.',
  ),
  'reportError_notAllowed': (
    '当前无权举报这张图片，请关闭并刷新档案。',
    '目前無權檢舉這張圖片，請關閉並重新整理檔案。',
    'You can no longer report this image. Close and reload the details.',
  ),
  'reportError_refreshRequired': (
    '图片或共享状态已改变，请关闭并刷新档案。',
    '圖片或分享狀態已改變，請關閉並重新整理檔案。',
    'The image or sharing changed. Close and reload the details.',
  ),
  'reportError_mediaChanged': (
    '图片已更换，请关闭并查看新图片。',
    '圖片已更換，請關閉並查看新圖片。',
    'The image changed. Close and view the new image.',
  ),
  'reportError_identityUnavailable': (
    '登录状态已改变，请重新登录。',
    '登入狀態已改變，請重新登入。',
    'Your session changed. Sign in again.',
  ),
  'reportError_rateLimited': (
    '提交过于频繁，请稍后重试。',
    '提交過於頻繁，請稍後重試。',
    'Too many submissions. Try again later.',
  ),
  'reportError_busy': (
    '另一项操作正在处理，请稍后重试。',
    '另一項操作正在處理，請稍後重試。',
    'Another operation is in progress. Try again shortly.',
  ),
  'reportError_intentConflict': (
    '这次提交的内容已改变，请重新确认。',
    '這次提交的內容已改變，請重新確認。',
    'The submission changed. Review it before trying again.',
  ),
  'close': ('关闭', '關閉', 'Close'),
  'sharedAt': ('共享时间', '分享時間', 'Shared on'),
  'importedAt': ('机库导入时间', '機庫匯入時間', 'Hangar imported on'),
  'notRecorded': ('未记录', '未記錄', 'Not recorded'),
  'originalImage': ('共享原图', '分享原圖', 'Shared original image'),
  'catalogImage': ('舰船目录图', '艦船目錄圖', 'Catalog artwork'),
  'noImage': ('尚无可用舰船图片。', '尚無可用艦船圖片。', 'No ship image is available yet.'),
  'imageLoading': ('正在读取原图…', '正在讀取原圖…', 'Loading original image…'),
  'imageUnavailable': (
    '当前无法读取原图，请更新客户端后重试。',
    '目前無法讀取原圖，請更新用戶端後重試。',
    'Image loading is unavailable. Update the client and try again.',
  ),
  'imageInvalid': (
    '图片无法读取，请重试。',
    '圖片無法讀取，請重試。',
    'The image could not be read. Try again.',
  ),
  'imageRetry': ('重新读取', '重新讀取', 'Reload'),
  'notFound': (
    '图片已不可用，可能已被移除或不再共享。',
    '圖片已不可用，可能已被移除或不再分享。',
    'The image is no longer available. It may have been removed or unshared.',
  ),
  'mediaChanged': (
    '图片已更换，请重新读取。',
    '圖片已更換，請重新讀取。',
    'The image changed. Reload to view it.',
  ),
  'refreshLibrary': ('返回并刷新舰船库', '返回並重新整理艦船庫', 'Back and refresh shared fleet'),
  'back': ('返回组织', '返回組織', 'Back to organization'),
  'scope': (
    '仅展示成员向本组织共享且允许你查看的舰船。',
    '僅展示成員向本組織分享且允許你查看的艦船。',
    'Only ships shared with this organization and visible to you are shown.',
  ),
  'search': ('搜索舰船、所有者或用途', '搜尋艦船、擁有者或用途', 'Search ships, owners or roles'),
  'searchButton': ('搜索', '搜尋', 'Search'),
  'refresh': ('刷新舰船库', '重新整理艦船庫', 'Refresh shared fleet'),
  'clear': ('清除筛选', '清除篩選', 'Clear filters'),
  'viewCards': ('按舰船', '按艦船', 'By ship'),
  'viewOwners': ('按持有人', '按持有人', 'By owner'),
  'viewList': ('列表', '列表', 'List'),
  'more': ('加载更多', '載入更多', 'Load more'),
  'shown': (
    '已显示 {shown} / {total} 艘',
    '已顯示 {shown} / {total} 艘',
    'Showing {shown} / {total}',
  ),
  'viewStatistics': ('查看统计', '查看統計', 'View statistics'),
  'notSharedHint': (
    '你还没有共享机库',
    '你還沒有共享機庫',
    'You have not shared your hangar yet',
  ),
  'sidePick': (
    '点一艘舰船，在这里查看详情。',
    '點一艘艦船，在這裡查看詳情。',
    'Pick a ship to see its details here.',
  ),
  'membersSharing': ('位成员共享', '位成員分享', 'members sharing'),
  'arrowHint': (
    '← → 切换上一艘 / 下一艘',
    '← → 切換上一艘 / 下一艘',
    '← → previous / next ship',
  ),
  'ownerShips': ('{count} 艘', '{count} 艘', '{count} ships'),
  'ownersTooMany': (
    '舰船太多，按持有人视图不可用，请用按舰船或列表。',
    '艦船太多，按持有人檢視不可用，請用按艦船或列表。',
    'Too many ships for the owner view; use the ship or list view.',
  ),
  'ownersNoMatches': (
    '没有符合筛选的舰船。',
    '沒有符合篩選的艦船。',
    'No ships match the filters.',
  ),
  'filter': ('筛选', '篩選', 'Filter'),
  'sort': ('排序', '排序', 'Sort by'),
  'ascending': ('升序', '升冪', 'Ascending'),
  'descending': ('降序', '降冪', 'Descending'),
  'all': ('全部舰船', '全部艦船', 'All ships'),
  'capital': ('旗舰级', '旗艦級', 'Capital'),
  'large': ('大型', '大型', 'Large'),
  'medium': ('中型', '中型', 'Medium'),
  'small': ('小型', '小型', 'Small'),
  'flyable': ('可飞', '可飛', 'Flyable'),
  'concept': ('概念', '概念', 'Concept'),
  'unknown': ('未知', '未知', 'Unknown'),
  'name': ('舰船名称', '艦船名稱', 'Ship name'),
  'spec': ('规格', '規格', 'Size'),
  'status': ('状态', '狀態', 'Status'),
  'price': ('参考价格（USD）', '參考價格（USD）', 'Reference price (USD)'),
  'role': ('用途', '用途', 'Role'),
  'owner': ('所有者', '擁有者', 'Owner'),
  'unpublished': ('未公布', '未公布', 'Unannounced'),
  'self': ('你', '你', 'You'),
  'previous': ('上一页', '上一頁', 'Previous'),
  'next': ('下一页', '下一頁', 'Next'),
  'loading': ('正在读取共享舰船…', '正在讀取分享艦船…', 'Loading shared ships…'),
  'empty': (
    '暂无可见的共享舰船。成员共享并允许你查看后，会显示在这里。',
    '暫無可見的分享艦船。成員分享並允許你查看後，會顯示在這裡。',
    'No shared ships are visible yet. They appear here when members share them with you.',
  ),
  'noMatches': (
    '没有匹配的舰船，试试其他关键词或清除筛选。',
    '沒有符合的艦船，試試其他關鍵字或清除篩選。',
    'No matching ships. Try another search or clear the filters.',
  ),
  'shipsChanged': (
    '舰船库已更新，请重新读取后继续。',
    '艦船庫已更新，請重新讀取後繼續。',
    'The shared fleet has changed. Refresh before continuing.',
  ),
  'refreshRequired': (
    '组织信息已过期，请刷新组织后重试。',
    '組織資訊已過期，請重新整理組織後再試。',
    'Organization information has expired. Refresh the organization and try again.',
  ),
  'identityUnavailable': (
    '账号状态已改变，请返回组织重新打开。',
    '帳號狀態已改變，請返回組織重新開啟。',
    'Your account state has changed. Return to the organization and reopen this page.',
  ),
  'notAllowed': (
    '目前无法查看此组织的舰船，请返回组织确认成员资格。',
    '目前無法查看此組織的艦船，請返回組織確認成員資格。',
    'You cannot view this organization’s ships. Return and check your membership.',
  ),
  'upgradeRequired': (
    '当前服务暂不支持舰船库查询，请稍后重试。',
    '目前服務暫不支援艦船庫查詢，請稍後再試。',
    'This service does not support shared fleet queries yet. Try again later.',
  ),
  'dataInvalid': (
    '舰船资料读取不完整，请重新读取。',
    '艦船資料讀取不完整，請重新讀取。',
    'Ship information could not be read completely. Refresh to try again.',
  ),
  'unavailable': (
    '暂时无法读取舰船库，请稍后重试。',
    '暫時無法讀取艦船庫，請稍後再試。',
    'The shared fleet is unavailable. Try again shortly.',
  ),
  'mediaFailed': (
    '部分头像未能加载，可刷新重试。',
    '部分頭像未能載入，可重新整理再試。',
    'Some avatars could not load. Refresh to retry.',
  ),
};
String communityShipsText(BuildContext context, String key) {
  final locale = AppStrings.of(context).locale;
  final value =
      shipCategoryLabels[key] ??
      shipGroundSizeLabels[key] ??
      communityShipsCopy[key] ??
      communityShipsCopy['unavailable']!;
  if (locale.languageCode == 'en') return value.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}

String communityShipDisplayText(BuildContext context, String? value) =>
    value == null || value.isEmpty
    ? communityShipsText(context, 'unknown')
    : shipCategoryLabels.containsKey(value) ||
          shipGroundSizeLabels.containsKey(value) ||
          communityShipsCopy.containsKey(value)
    ? communityShipsText(context, value)
    : value;

String communityShipsCulture(BuildContext context) {
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? 'en-US'
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? 'zh-TW'
      : 'zh-CN';
}
