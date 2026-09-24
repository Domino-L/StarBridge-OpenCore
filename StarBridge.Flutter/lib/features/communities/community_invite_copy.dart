import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityInviteCopy = <String, (String, String, String)>{
  'administrators': ('组织管理员', '組織管理員', 'Organization administrators'),
  'example': (
    '示例邀请码：EXAMPLE-ORG。只用于预览，不会加入真实组织或修改真实共享设置。',
    '示例邀請碼：EXAMPLE-ORG。僅供預覽，不會加入真實組織或修改真實共享設定。',
    'Example code: EXAMPLE-ORG. Preview only; real memberships and sharing settings stay unchanged.',
  ),
  'reloadPrivacy': (
    '重新读取设置，保留当前选择',
    '重新讀取設定，保留目前選擇',
    'Reload settings and keep my choices',
  ),
  'title': ('使用邀请码加入组织', '使用邀請碼加入組織', 'Join an organization by invite'),
  'code': ('邀请码', '邀請碼', 'Invite code'),
  'enterCode': ('请输入有效的邀请码。', '請輸入有效的邀請碼。', 'Enter a valid invite code.'),
  'verify': ('验证邀请码', '驗證邀請碼', 'Verify invite'),
  'cancel': ('取消', '取消', 'Cancel'),
  'close': ('关闭', '關閉', 'Close'),
  'review': ('确认共享设置', '確認共享設定', 'Review sharing settings'),
  'join': ('保存选择并加入', '儲存選擇並加入', 'Save choices and join'),
  'working': ('正在处理…', '正在處理…', 'Working…'),
  'owner': ('负责人', '負責人', 'Owner'),
  'members': ('成员', '成員', 'Members'),
  'expires': ('有效期至', '有效期至', 'Expires'),
  'uses': ('剩余次数', '剩餘次數', 'Uses left'),
  'unlimited': ('不限', '不限', 'Unlimited'),
  'noExpiry': ('长期有效', '長期有效', 'No expiry'),
  'direct': (
    '确认后直接加入，不会退出其它组织。',
    '確認後直接加入，不會退出其他組織。',
    'Join directly after confirming. Your other memberships stay unchanged.',
  ),
  'already': (
    '你已在这个组织中，无需再次加入。',
    '你已在這個組織中，無需再次加入。',
    'You already belong to this organization.',
  ),
  'membershipConflict': (
    '当前服务暂只支持加入一个组织。你已有组织，本次不会退出原组织或接受邀请。',
    '目前服務暫只支援加入一個組織。你已有組織，本次不會退出原組織或接受邀請。',
    'The current service supports one organization membership. You already have one; this invite will not leave it or join another.',
  ),
  'inviteInvalid': (
    '邀请码不存在、已过期、已撤销或次数已用完，请联系邀请人。',
    '邀請碼不存在、已過期、已撤銷或次數已用完，請聯絡邀請人。',
    'This invite is invalid, expired, revoked or used up. Contact the inviter.',
  ),
  'unavailable': (
    '暂时无法验证，请检查连接后重试。',
    '暫時無法驗證，請檢查連線後重試。',
    'Cannot verify the invite. Check your connection and retry.',
  ),
  'dataInvalid': (
    '收到的邀请信息不完整，请重新验证。',
    '收到的邀請資訊不完整，請重新驗證。',
    'The invite information is incomplete. Verify it again.',
  ),
  'identityUnavailable': (
    '账号状态已变化，请重新登录后验证。',
    '帳號狀態已變更，請重新登入後驗證。',
    'Your account changed. Sign in and verify again.',
  ),
  'notAllowed': (
    '当前账号无权使用这份邀请。',
    '目前帳號無權使用這份邀請。',
    'Your account cannot use this invite.',
  ),
  'refreshRequired': (
    '组织或邀请状态已变化，请重新验证后再操作。',
    '組織或邀請狀態已變更，請重新驗證後再操作。',
    'The organization or invite changed. Verify it again.',
  ),
  'requestChanged': (
    '请重新验证邀请码，再确认加入。',
    '請重新驗證邀請碼，再確認加入。',
    'Verify the invite again before joining.',
  ),
  'busy': (
    '另一个操作正在处理，请稍后重试。',
    '另一個操作正在處理，請稍後重試。',
    'Another operation is running. Try again shortly.',
  ),
  'outcomeUnknown': (
    '尚未确认是否加入。请关闭此窗口并刷新“我的组织”，不要重复提交。',
    '尚未確認是否加入。請關閉此視窗並重新整理「我的組織」，不要重複提交。',
    'Joining is not confirmed. Close this window and refresh My organizations. Do not submit again.',
  ),
  'privacyUnavailable': (
    '暂时无法读取共享设置。为避免使用未知设置，请读取成功后再加入。',
    '暫時無法讀取共享設定。為避免使用未知設定，請讀取成功後再加入。',
    'Sharing settings are unavailable. Load them before joining.',
  ),
  'privacySaveFailed': (
    '共享设置尚未确认保存，未发送加入请求。请重试或取消。',
    '共享設定尚未確認儲存，未傳送加入請求。請重試或取消。',
    'Sharing choices were not confirmed saved. No join request was sent. Retry or cancel.',
  ),
  'savedChoices': (
    '共享选择已保存；加入失败或关闭窗口不会撤销这次保存。',
    '共享選擇已儲存；加入失敗或關閉視窗不會撤銷這次儲存。',
    'Sharing choices are saved. Closing or failing to join will not undo this save.',
  ),
  'sharing': ('加入前确认共享设置', '加入前確認共享設定', 'Review sharing before joining'),
  'scopeWarning': (
    '这里修改当前账号的既有共享设置，并非这个组织的独立设置。房间字段保持原值；共享总开关也影响房间。若当前已应用实时共享，保存会更新其策略。',
    '這裡修改目前帳號的既有共享設定，並非這個組織的獨立設定。房間欄位保持原值；共享總開關也影響房間。若目前已套用即時共享，儲存會更新其策略。',
    'These are your existing account sharing settings, not settings just for this organization. Room fields stay unchanged; the master switch also affects rooms. Saving updates an already-active sharing policy.',
  ),
  'publicationWarning': (
    '本次不会自动启动实时共享或把其它组织的共享关系迁入这里。机库和事件暂只保存选择。',
    '本次不會自動啟動即時共享或把其他組織的共享關係遷入這裡。機庫和事件暫只儲存選擇。',
    'This does not start realtime sharing or move sharing relationships from other organizations. Hangar and event choices are currently saved only.',
  ),
  'acknowledge': (
    '我已确认以上共享选择及影响范围',
    '我已確認以上共享選擇及影響範圍',
    'I have reviewed these choices and their scope',
  ),
  'groups': (
    '已有指定身份组：{count} 个，保留原值，不自动迁移。',
    '已有指定身分組：{count} 個，保留原值，不自動遷移。',
    '{count} existing selected groups retained; no automatic migration.',
  ),
};

String inviteText(BuildContext context, String key) {
  final value = communityInviteCopy[key] ?? communityInviteCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
