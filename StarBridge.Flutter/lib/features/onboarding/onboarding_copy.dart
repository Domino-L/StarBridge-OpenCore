import 'package:flutter/widgets.dart';

import 'onboarding_models.dart';
import 'onboarding_copy_behavior_prompt.dart';
import 'onboarding_copy_profile.dart';
import 'onboarding_copy_setup.dart';
import 'onboarding_copy_verify.dart';

/// Localized copy stays with this first-use Module, not Host error messages.
final class OnboardingCopy {
  const OnboardingCopy(this.locale);
  final Locale locale;

  String text(String key) {
    final words =
        _words[key] ??
        onboardingSetupWords[key] ??
        onboardingProfileWords[key] ??
        onboardingVerifyWords[key] ??
        onboardingBehaviorPromptWords[key]!;
    if (locale.languageCode == 'en') return words.$3;
    if (locale.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(locale.countryCode)) {
      return words.$2;
    }
    return words.$1;
  }

  String step(OnboardingStep step) => text('step.${step.name}');
  String title(OnboardingStep step) => text('title.${step.name}');
  String description(OnboardingStep step) => text('description.${step.name}');

  static const _words = <String, (String, String, String)>{
    'onlineRestore.title': ('恢复在线', '恢復線上', 'Resume online'),
    'onlineRestore.install': (
      '确认并恢复在线',
      '確認並恢復線上',
      'Confirm and resume online',
    ),
    'onlineRestore.working': (
      '正在恢复在线，请稍候。',
      '正在恢復線上，請稍候。',
      'Resuming online. Please wait.',
    ),
    'onlineRestore.unconfirmed': (
      '尚未确认恢复结果。请重新检查；不会重复执行恢复。',
      '尚未確認恢復結果。請重新檢查；不會重複執行恢復。',
      'The result is not confirmed. Check again without repeating the resume operation.',
    ),
    'onlineRestore.local': (
      '未能恢复在线，已返回本机模式。可以关闭后重新尝试。',
      '未能恢復線上，已返回本機模式。可以關閉後重新嘗試。',
      'Online mode was not restored. Local mode is available. Close this window and try again.',
    ),
    'onlineRestore.recovery': (
      '切换尚未完成。请重新检查状态或查看诊断信息。',
      '切換尚未完成。請重新檢查狀態或查看診斷資訊。',
      'The switch has not finished. Check the status or diagnostics.',
    ),
    'onlineRestore.recheck': ('重新检查', '重新檢查', 'Check again'),
    'onlineRestore.diagnostic': ('诊断代码', '診斷代碼', 'Diagnostic code'),
    'onlineRestore.close': ('关闭', '關閉', 'Close'),
    'onlineReview.title': ('核对联网账号', '核對連線帳號', 'Check your online account'),
    'onlineReview.resume': ('恢复在线', '恢復線上', 'Resume online'),
    'onlineReview.reauthorize': ('重新授权原账号', '重新授權原帳號', 'Authorize again'),
    'onlineReview.resumeRequired': (
      '登录会话已保留。恢复在线时先核对账号和 Handle，本机档案不会自动合并。',
      '登入工作階段已保留。恢復線上時先核對帳號與 Handle，本機檔案不會自動合併。',
      'Your sign-in is retained. Check your account and Handle before resuming online. Local profiles stay separate.',
    ),
    'onlineReview.restoring': (
      '正在核对已保留的登录会话。取消后继续使用离线功能。',
      '正在核對保留的登入工作階段。取消後繼續使用離線功能。',
      'Checking your retained sign-in. You can cancel and keep using offline features.',
    ),
    'onlineReview.cancelResume': (
      '取消恢复，保持离线',
      '取消恢復，保持離線',
      'Cancel and stay offline',
    ),
    'onlineReview.cancellingResume': (
      '正在结束本次恢复。完成后保持离线，不注销登录。',
      '正在結束此次恢復。完成後保持離線，不登出帳號。',
      'Ending this resume attempt. You will stay offline without signing out.',
    ),
    'onlineReview.confirmLocal': (
      '确认这个日志中的 Handle',
      '確認此日誌中的 Handle',
      'Confirm this log Handle',
    ),
    'onlineReview.localHandle': (
      '本机日志 Handle',
      '本機日誌 Handle',
      'Local log Handle',
    ),
    'onlineReview.scmHandle': (
      'SCM 已验证的 Handle',
      'SCM 已驗證的 Handle',
      'SCM-verified Handle',
    ),
    'onlineReview.confirm': (
      '确认这两个 Handle',
      '確認這兩個 Handle',
      'Confirm these Handles',
    ),
    'onlineReview.confirmAccount': ('恢复此账号', '恢復此帳號', 'Restore this account'),
    'onlineReview.accountReviewRequired': (
      '原登录会话已复核。恢复账号后，可继续设置游戏日志和身份。',
      '原登入工作階段已複核。恢復帳號後，可繼續設定遊戲日誌與身分。',
      'Your saved session has been verified. Restore the account, then set up your game log and identity.',
    ),
    'onlineReview.accountConfirmedForHandoff': (
      '正在恢复账号。游戏身份将在后续步骤单独确认。',
      '正在恢復帳號。遊戲身分將在後續步驟單獨確認。',
      'Restoring your account. Game identity will be confirmed separately.',
    ),
    'onlineReview.installedReviewRequired': (
      '账号已恢复在线。请核对两个 Handle，再确认游戏身份。',
      '帳號已恢復連線。請核對兩個 Handle，再確認遊戲身分。',
      'Your account is online. Compare the Handles to confirm your game identity.',
    ),
    'onlineReview.boundOnlineIdentity': (
      '账号已在线，游戏身份已确认。可以继续本机设置。',
      '帳號已連線，遊戲身分已確認。可以繼續本機設定。',
      'Your account is online and your game identity is confirmed. Continue with device settings.',
    ),
    'onlineReview.check': ('核对 SCM 身份', '核對 SCM 身分', 'Check SCM identity'),
    'onlineReview.cancel': (
      '取消登录，保留本机模式',
      '取消登入，保留本機模式',
      'Cancel sign-in and stay local',
    ),
    'onlineReview.signInRequired': (
      '登录 SCM 后再核对游戏身份。本机档案保持独立。',
      '登入 SCM 後再核對遊戲身分。本機檔案保持獨立。',
      'Sign in to SCM, then check your game identity. Local profiles stay separate.',
    ),
    'onlineReview.authorizing': (
      '请在浏览器中完成登录，也可以取消并继续使用本机功能。',
      '請在瀏覽器中完成登入，也可以取消並繼續使用本機功能。',
      'Finish signing in in your browser, or cancel and keep using local features.',
    ),
    'onlineReview.cancelling': (
      '正在结束登录。结束后保留本机档案和设置。',
      '正在結束登入。結束後保留本機檔案和設定。',
      'Ending sign-in. Your local profiles and settings will be kept.',
    ),
    'onlineReview.checking': (
      '正在核对，请稍候。',
      '正在核對，請稍候。',
      'Checking. Please wait.',
    ),
    'onlineReview.needsLocalIdentity': (
      '先确认日志中的 Handle；若日志中没有可用身份，请进入一次游戏。',
      '先確認日誌中的 Handle；若日誌沒有可用身分，請進入一次遊戲。',
      'Confirm the log Handle first. If no usable identity is found, enter the game once.',
    ),
    'onlineReview.checkRequired': (
      '请核对 SCM 身份，确认它与本机日志中的 Handle 一致。',
      '請核對 SCM 身分，確認它與本機日誌中的 Handle 一致。',
      'Check that your SCM identity matches the local log Handle.',
    ),
    'onlineReview.reviewRequired': (
      '请查看两个 Handle，再确认是否使用这个联网账号。',
      '請查看兩個 Handle，再確認是否使用此連線帳號。',
      'Compare the two Handles, then confirm this online account.',
    ),
    'onlineReview.confirmedForHandoff': (
      '身份已核对。继续完成设置后才能使用在线功能；共享尚未开启。',
      '身分已核對。繼續完成設定後才能使用線上功能；共享尚未開啟。',
      'Identity checked. Finish setup before using online features. Sharing is still off.',
    ),
    'onlineReview.mismatch': (
      '两个 Handle 不一致。请登录对应的 SCM 账号，或返回日志步骤核对本机身份。',
      '兩個 Handle 不一致。請登入對應的 SCM 帳號，或返回日誌步驟核對本機身分。',
      'The Handles do not match. Use the matching SCM account, or return to the log step to check your local identity.',
    ),
    'onlineReview.verificationRequired': (
      '这个 SCM 账号还没有验证游戏身份，验证后才能使用在线功能。不想验证可以取消登录，继续用本机模式。',
      '這個 SCM 帳號還沒有驗證遊戲身分，驗證後才能使用線上功能。不想驗證可以取消登入，繼續用本機模式。',
      'This SCM account has not verified a game identity, and online features need it. If you would rather not, cancel sign-in and keep using local mode.',
    ),
    'onlineReview.verifyGameIdentity': (
      '验证游戏身份',
      '驗證遊戲身分',
      'Verify game identity',
    ),
    'onlineReview.verificationPending': (
      'SCM 身份验证仍在处理中。完成后再重新核对。',
      'SCM 身分驗證仍在處理中。完成後再重新核對。',
      'SCM identity verification is pending. Check again when it finishes.',
    ),
    'onlineReview.reauthorizationRequired': (
      '需要重新授权后才能继续。请在浏览器授权原 SCM 账号，再核对 Handle；本机档案不会合并。',
      '需要重新授權後才能繼續。請在瀏覽器授權原 SCM 帳號，再核對 Handle；本機檔案不會合併。',
      'Reauthorization is needed to continue. Authorize your original SCM account in the browser, then check your Handle. Local profiles stay separate.',
    ),
    'onlineReview.recoveryRequired': (
      '上次切换尚未完成，暂时无法确认功能是否可用。请重新检查状态或查看诊断信息。',
      '上次切換尚未完成，暫時無法確認功能是否可用。請重新檢查狀態或查看診斷資訊。',
      'The previous switch has not finished, so feature availability is not confirmed. Check the status or diagnostics.',
    ),
    'onlineReview.unavailable': (
      '尚未确认联网账号状态。请重新检查。',
      '尚未確認連線帳號狀態。請重新檢查。',
      'Online account status is not confirmed. Check again.',
    ),
    'onlineReview.error': (
      '本次操作未得到确认。请重新检查状态，不必改动共享设置。',
      '本次操作未得到確認。請重新檢查狀態，無須更改共享設定。',
      'This operation was not confirmed. Check the status again; no sharing changes are needed.',
    ),
    'native.title': ('浮层与快捷键', '浮層與快速鍵', 'Overlay and shortcut'),
    'native.intro': (
      '先看浮层，再按自己的快捷键试一次。预览期间不响应浮层快捷键。',
      '先看浮層，再按自己的快速鍵試一次。預覽期間不回應浮層快速鍵。',
      'Inspect the overlay, then try your shortcut. Overlay shortcuts are paused during preview.',
    ),
    'native.previewTitle': ('看浮层', '查看浮層', 'Inspect the overlay'),
    'native.openPreview': ('打开浮层预览', '開啟浮層預覽', 'Open overlay preview'),
    'native.preview.notStarted': (
      '查看已保存的浮层，设置保持不变。普通浮层会暂时暂停，退出预览后恢复。',
      '查看已儲存的浮層，設定保持不變。一般浮層會暫時暫停，結束預覽後恢復。',
      'Inspect your saved overlay without changing settings. The normal overlay pauses and resumes when preview closes.',
    ),
    'native.preview.opening': ('正在打开预览…', '正在開啟預覽…', 'Opening preview…'),
    'native.preview.returned': (
      '已返回设置。若未看到浮层，请再次打开预览。',
      '已返回設定。若未看到浮層，請再次開啟預覽。',
      'Back in setup. If you did not see the overlay, open preview again.',
    ),
    'native.preview.blocked': (
      '暂时无法打开预览。请先退出其他浮层预览，并检查浮层设置。',
      '暫時無法開啟預覽。請先結束其他浮層預覽，並檢查浮層設定。',
      'Preview is unavailable. Exit any other overlay preview and check overlay settings.',
    ),
    'native.preview.failed': (
      '预览未能完成。请检查浮层设置并重试。',
      '預覽未能完成。請檢查浮層設定並重試。',
      'Preview could not finish. Check overlay settings and try again.',
    ),
    'native.hotkeyTitle': ('试快捷键', '測試快速鍵', 'Try the shortcut'),
    'native.startCheck': ('开始快捷键检查', '開始快速鍵檢查', 'Start shortcut check'),
    'native.stopCheck': ('停止检查', '停止檢查', 'Stop checking'),
    'native.hotkeyHelp': (
      '开始后按上方快捷键一次，再回到这里查看结果。检查最多持续 30 秒。若快捷键仅在游戏中可用，请在游戏前台按下。',
      '開始後按上方快速鍵一次，再回到這裡查看結果。檢查最多持續 30 秒。若快速鍵僅在遊戲中可用，請在遊戲前景按下。',
      'Start, press the shortcut shown above once, then return to see the result. The check lasts up to 30 seconds. Game-only shortcuts need the game in the foreground.',
    ),
    'native.unavailable': (
      '尚未读取浮层状态。请重新检查。',
      '尚未讀取浮層狀態。請重新檢查。',
      'Overlay status is unavailable. Check again.',
    ),
    'native.hotkey.registered': (
      '快捷键已启用，尚未测试。',
      '快速鍵已啟用，尚未測試。',
      'Shortcut enabled; not tested yet.',
    ),
    'native.hotkey.gameCompatibleOnly': (
      '游戏内快捷键已启用，尚未测试。',
      '遊戲內快速鍵已啟用，尚未測試。',
      'Game-compatible shortcut enabled; not tested yet.',
    ),
    'native.hotkey.desktopOnly': (
      '桌面快捷键已启用，尚未测试。',
      '桌面快速鍵已啟用，尚未測試。',
      'Desktop shortcut enabled; not tested yet.',
    ),
    'native.hotkey.disabled': (
      '快捷键已关闭，可以保持此选择。',
      '快速鍵已關閉，可以保持此選擇。',
      'Shortcut is disabled. You can keep this choice.',
    ),
    'native.hotkey.unavailable': (
      '快捷键状态不可用，请检查浮层设置。',
      '快速鍵狀態無法使用，請檢查浮層設定。',
      'Shortcut status is unavailable. Check overlay settings.',
    ),
    'native.hotkey.invalid': (
      '快捷键无效，请在浮层设置中重新选择。',
      '快速鍵無效，請在浮層設定中重新選擇。',
      'Shortcut is invalid. Choose another in overlay settings.',
    ),
    'native.hotkey.conflict': (
      '快捷键被占用，请在浮层设置中更换。',
      '快速鍵已被占用，請在浮層設定中更換。',
      'Shortcut is in use. Choose another in overlay settings.',
    ),
    'native.hotkey.failed': (
      '快捷键未能启用，请检查浮层设置。',
      '快速鍵未能啟用，請檢查浮層設定。',
      'Shortcut could not be enabled. Check overlay settings.',
    ),
    'native.check.waiting': (
      '正在等待本次快捷键输入…',
      '正在等待本次快速鍵輸入…',
      'Waiting for a new shortcut input…',
    ),
    'native.check.observed': (
      '已收到本次快捷键输入。',
      '已收到本次快速鍵輸入。',
      'Received a new shortcut input.',
    ),
    'native.check.timedOut': (
      '30 秒内未收到快捷键输入，可以重新检查。',
      '30 秒內未收到快速鍵輸入，可以重新檢查。',
      'No shortcut input received within 30 seconds. You can try again.',
    ),
    'native.check.interrupted': (
      '检查已中断，请重新开始。',
      '檢查已中斷，請重新開始。',
      'The check was interrupted. Start again.',
    ),
    'native.outcome.open': (
      '本次操作返回：浮层已打开。',
      '本次操作傳回：浮層已開啟。',
      'The shortcut returned: overlay open.',
    ),
    'native.outcome.closed': (
      '本次操作返回：浮层已关闭。',
      '本次操作傳回：浮層已關閉。',
      'The shortcut returned: overlay closed.',
    ),
    'native.outcome.opening': (
      '本次操作返回：浮层正在打开，请查看实际显示。',
      '本次操作傳回：浮層正在開啟，請查看實際顯示。',
      'The shortcut returned: overlay opening. Check the actual display.',
    ),
    'native.outcome.suppressed': (
      '本次操作返回：浮层被暂时隐藏。',
      '本次操作傳回：浮層暫時隱藏。',
      'The shortcut returned: overlay temporarily hidden.',
    ),
    'native.outcome.failed': (
      '收到输入，但浮层操作失败。请检查浮层设置。',
      '收到輸入，但浮層操作失敗。請檢查浮層設定。',
      'Input received, but the overlay action failed. Check overlay settings.',
    ),
    'native.outcome.unavailable': (
      '收到输入，但浮层暂不可用。',
      '收到輸入，但浮層暫時無法使用。',
      'Input received, but the overlay is unavailable.',
    ),
    'native.readError': (
      '未能读取本次浮层状态，请重新检查。',
      '未能讀取本次浮層狀態，請重新檢查。',
      'Could not read the current overlay status. Check again.',
    ),
    'native.optional': (
      '可以保持快捷键关闭，稍后在浮层设置中开启。高级布局不影响基础设置。',
      '可以保持快速鍵關閉，稍後在浮層設定中開啟。進階配置不影響基本設定。',
      'You can leave shortcuts disabled and enable them later in overlay settings. Advanced layout is optional.',
    ),
    'statistics.title': ('本机游玩时长', '本機遊玩時長', 'Local play time'),
    'statistics.intro': (
      '为当前已确认的游戏身份选择是否记录时长。此选择只保存在本机。',
      '為目前已確認的遊戲身分選擇是否記錄時長。此選擇只儲存在本機。',
      'Choose whether to record time for the confirmed game identity. This choice stays on this device.',
    ),
    'statistics.allow': ('记录本机游玩时长', '記錄本機遊玩時長', 'Record local play time'),
    'statistics.allowBody': (
      '日志监听开启且游戏身份可确认时，记录之后的游玩时间。',
      '日誌監聽開啟且遊戲身分可確認時，記錄之後的遊玩時間。',
      'Record future play while log listening is enabled and the game identity can be confirmed.',
    ),
    'statistics.decline': ('暂不记录', '暫不記錄', 'Do not record now'),
    'statistics.declineBody': (
      '仍可继续设置。已有本机时长保留，以后可以更改。',
      '仍可繼續設定。已有本機時長保留，以後可以變更。',
      'You can continue setup. Existing local time is kept; you can change this later.',
    ),
    'statistics.confirm': ('保存时长选择', '儲存時長選擇', 'Save recording choice'),
    'statistics.allowed': (
      '已保存：允许记录本机时长。',
      '已儲存：允許記錄本機時長。',
      'Saved: local time recording is allowed.',
    ),
    'statistics.declined': (
      '已保存：不记录新的本机时长。',
      '已儲存：不記錄新的本機時長。',
      'Saved: new local time will not be recorded.',
    ),
    'statistics.savedTime': ('已保存时长', '已儲存時長', 'Saved time'),
    'statistics.minutes': ('分钟', '分鐘', 'minutes'),
    'statistics.state.unavailable': (
      '暂时无法读取时长选择，请重新检查。',
      '暫時無法讀取時長選擇，請重新檢查。',
      'The recording choice is unavailable. Check again.',
    ),
    'statistics.state.inactive': (
      '当前模式尚未启用独立本机时长设置。',
      '目前模式尚未啟用獨立本機時長設定。',
      'Independent local recording settings are not active in this mode.',
    ),
    'statistics.state.needsIdentity': (
      '先确认本机游戏身份，再选择是否记录。',
      '先確認本機遊戲身分，再選擇是否記錄。',
      'Confirm the local game identity before choosing whether to record.',
    ),
    'statistics.state.choiceRequired': (
      '请选择记录或不记录；两种选择都可以继续。',
      '請選擇記錄或不記錄；兩種選擇都可以繼續。',
      'Choose to record or not record. Either choice allows you to continue.',
    ),
    'statistics.state.retryRequired': (
      '上次保存尚未确认。请重新选择并保存。',
      '上次儲存尚未確認。請重新選擇並儲存。',
      'The last save is unconfirmed. Choose again and save.',
    ),
    'statistics.error': (
      '尚未确认保存此选择。请重新检查后再选择。',
      '尚未確認儲存此選擇。請重新檢查後再選擇。',
      'This choice has not been confirmed as saved. Check again, then choose.',
    ),
    'statistics.separate': (
      '此选择不会自动导入历史时长、合并其他档案或开启共享。历史时长需在下方单独预览并确认。',
      '此選擇不會自動匯入歷史時長、合併其他檔案或開啟共享。歷史時長需在下方另外預覽並確認。',
      'This choice does not import past time, merge profiles or turn on sharing. Past time needs its own preview and confirmation below.',
    ),
    'brand': ('星海舰桥', '星海艦橋', 'StarBridge'),
    'entry': ('首次使用设置', '首次使用設定', 'First-use setup'),
    'entryBody': (
      '继续之前的设置，不清除已保存的选择。设置完成后，在线功能与共享仍按各自的选择启用。',
      '繼續先前的設定，不清除已儲存的選擇。設定完成後，線上功能與共享仍按各自的選擇啟用。',
      'Continue setup without clearing saved choices. Online features and sharing remain controlled by their own choices.',
    ),
    'back': ('返回', '返回', 'Back'),
    'next': ('继续', '繼續', 'Continue'),
    'confirm': ('确认此 Handle', '確認此 Handle', 'Confirm this Handle'),
    'finish': ('保存并完成设置', '儲存並完成設定', 'Save and finish setup'),
    'close': ('保存进度并关闭', '儲存進度並關閉', 'Save progress and close'),
    'closePlain': ('关闭设置', '關閉設定', 'Close setup'),
    'keep': ('继续设置', '繼續設定', 'Keep setting up'),
    'discard': ('不保存并关闭', '不儲存並關閉', 'Close without saving'),
    'notSaved': ('进度尚未保存', '進度尚未儲存', 'Progress has not been saved'),
    'notSavedBody': (
      '现在关闭，下次可能需要重新完成本次步骤。已保存的功能设置不会被清除。',
      '現在關閉，下次可能需要重新完成本次步驟。已儲存的功能設定不會被清除。',
      'Closing now may require repeating these steps. Existing saved settings will not be cleared.',
    ),
    'busy': ('正在检查，请稍候。', '正在檢查，請稍候。', 'Checking. Please wait.'),
    'error': (
      '本次操作尚未确认完成。请重新检查后重试。',
      '本次操作尚未確認完成。請重新檢查後重試。',
      'This action has not been confirmed. Check the status and try again.',
    ),
    'unavailable': (
      '暂时无法读取设置状态。请重新检查或稍后继续。',
      '暫時無法讀取設定狀態。請重新檢查或稍後繼續。',
      'Setup status is unavailable. Check again or continue later.',
    ),
    'retry': ('重新检查', '重新檢查', 'Check again'),
    'online': ('登录 SCM', '登入 SCM', 'Sign in to SCM'),
    'onlineDescription': (
      '使用账号资料、好友与协作功能。仍需连接本机游戏日志。',
      '使用帳號資料、好友與協作功能。仍需連接本機遊戲日誌。',
      'Use your profile, friends and collaboration. Your local game log is still required.',
    ),
    'local': ('暂不联网', '暫不連線', 'Use local features for now'),
    'localDescription': (
      '先设置本机功能，以后从账号入口登录，无需重做基础设置。',
      '先設定本機功能，以後從帳號入口登入，無需重做基礎設定。',
      'Set up local features now. Sign in later from Account without repeating the basics.',
    ),
    'login': ('打开 SCM 登录', '開啟 SCM 登入', 'Open SCM sign-in'),
    'cancelLogin': ('取消登录', '取消登入', 'Cancel sign-in'),
    'signedIn': ('SCM 已登录', 'SCM 已登入', 'Signed in to SCM'),
    'pickLog': ('选择 Game.log', '選擇 Game.log', 'Choose Game.log'),
    'logReady': ('日志已连接', '日誌已連接', 'Game log connected'),
    'version': ('游戏版本', '遊戲版本', 'Game version'),
    'unknown': ('尚未确认', '尚未確認', 'Not confirmed yet'),
    'current': ('当前日志', '目前日誌', 'Current log'),
    'history': ('历史日志', '歷史日誌', 'Historical log'),
    'freshSession': (
      '本次游戏的新记录',
      '本次遊戲的新記錄',
      'New record from this game session',
    ),
    'confirmedLocal': ('已确认的本机档案', '已確認的本機檔案', 'Confirmed local profile'),
    'confirmedLocalBody': (
      '游戏退出后，档案仍会保留。这不是当前游戏状态，也不会开启共享。',
      '遊戲結束後，檔案仍會保留。這不是目前遊戲狀態，也不會開啟分享。',
      'Your profile is kept after the game closes. This is not live game status and does not enable sharing.',
    ),
    'evidenceTime': ('记录时间', '記錄時間', 'Record time'),
    'localOnly': (
      '这是本机游戏身份关联，不代表 SCM 账号已验证。',
      '這是本機遊戲身分關聯，不代表 SCM 帳號已驗證。',
      'This associates your local game identity; it does not verify your SCM account.',
    ),
    'checking': (
      '正在检查当前与允许读取的历史日志。',
      '正在檢查目前與允許讀取的歷史日誌。',
      'Checking the current log and permitted historical logs.',
    ),
    'missing': (
      '没有找到可用 Handle，请进入一次游戏',
      '沒有找到可用 Handle，請進入一次遊戲',
      'No usable Handle found. Enter the game once',
    ),
    'enterGame': (
      '进入所选版本的游戏，直到产生有效身份记录。仅打开 Launcher 不足以完成。你可以保存进度，稍后继续。',
      '進入所選版本的遊戲，直到產生有效身分記錄。僅開啟 Launcher 不足以完成。你可以儲存進度，稍後繼續。',
      'Enter the selected game version until a valid identity record is detected. Opening the Launcher is not enough. You can save progress and return later.',
    ),
    'freshRequired': (
      '请等待本次游戏的身份记录',
      '請等待本次遊戲的身分記錄',
      'Waiting for an identity record from this game session',
    ),
    'notChecked': (
      '日志检查尚未完成，请重新检查。',
      '日誌檢查尚未完成，請重新檢查。',
      'Log checks are incomplete. Check again.',
    ),
    'conflict': (
      '发现不同的游戏身份。请核对日志来源后重新检查。',
      '發現不同的遊戲身分。請核對日誌來源後重新檢查。',
      'Different game identities were found. Check the log source and try again.',
    ),
    'failed': (
      '无法读取日志。请检查文件位置与读取权限后重试。',
      '無法讀取日誌。請檢查檔案位置與讀取權限後重試。',
      'The log could not be read. Check its location and read permissions, then retry.',
    ),
    'mismatch': (
      'SCM 与本机游戏身份尚未核对一致。请在账号设置中检查验证状态。',
      'SCM 與本機遊戲身分尚未核對一致。請在帳號設定中檢查驗證狀態。',
      'SCM and local game identity are not yet matched. Check verification in Account settings.',
    ),
    'reviewLocal': ('查看本机设置', '查看本機設定', 'Review local settings'),
    'device.intro': (
      '核对这台设备上的选择，需要调整时打开原设置页。',
      '核對這台裝置上的選擇，需要調整時開啟原設定頁。',
      'Review the choices on this device. Open the settings page to adjust them.',
    ),
    'device.separate': (
      '这次确认只记录你已核对设备设置。本机统计、日志监听和共享仍需分别选择；浮层还需检查预览和快捷键。',
      '這次確認只記錄你已核對裝置設定。本機統計、日誌監聽和分享仍需分別選擇；浮層還需檢查預覽和快速鍵。',
      'This confirms your device choices only. Statistics, log listening and sharing need separate choices. Overlay preview and shortcuts still need checking.',
    ),
    'device.edit': ('调整设置', '調整設定', 'Adjust settings'),
    'device.checked': ('我已核对这些选择', '我已核對這些選擇', 'I have reviewed these choices'),
    'device.confirm': (
      '确认这四项设备选择',
      '確認這四項裝置選擇',
      'Confirm these four device choices',
    ),
    'device.enabled': ('开启', '開啟', 'On'),
    'device.disabled': ('关闭', '關閉', 'Off'),
    'device.minutes': ('分钟', '分鐘', 'minutes'),
    'device.section.application': ('启动与关闭', '啟動與關閉', 'Startup and closing'),
    'device.section.overlay': ('浮层行为', '浮層行為', 'Overlay behavior'),
    'device.section.notifications': ('通知显示', '通知顯示', 'Notification display'),
    'device.section.playReminder': ('连续游玩提醒', '連續遊玩提醒', 'Play reminders'),
    'device.state.unavailable': (
      '暂时无法读取设备设置，请重新检查。',
      '暫時無法讀取裝置設定，請重新檢查。',
      'Device settings are unavailable. Check again.',
    ),
    'device.state.needsIdentity': (
      '先完成游戏日志和 Handle 确认。',
      '先完成遊戲日誌和 Handle 確認。',
      'Connect your game log and confirm your Handle first.',
    ),
    'device.state.contextChanged': (
      '游戏身份或日志来源已变化，请重新检查。',
      '遊戲身分或日誌來源已變更，請重新檢查。',
      'Game identity or log source changed. Check again.',
    ),
    'device.state.settingsChanged': (
      '设置正在变化，请重新读取后核对。',
      '設定正在變更，請重新讀取後核對。',
      'Settings are changing. Read them again before reviewing.',
    ),
    'device.state.choicesRequired': (
      '请先在上方选择启动与关闭方式并保存。',
      '請先在上方選擇啟動與關閉方式並儲存。',
      'Choose and save startup and closing above first.',
    ),
    'device.state.reviewRequired': (
      '请逐项核对并勾选，之后确认。',
      '請逐項核對並勾選，之後確認。',
      'Review and check each section, then confirm.',
    ),
    'device.state.reviewed': (
      '当前设备选择已确认；其余本机步骤仍需完成。',
      '目前裝置選擇已確認；其餘本機步驟仍需完成。',
      'Current device choices are confirmed. Other local setup steps still need completing.',
    ),
    'device.field.launchAtStartup': (
      '随 Windows 启动',
      '隨 Windows 啟動',
      'Launch with Windows',
    ),
    'device.field.keepRunningInBackground': (
      '关闭窗口后留在托盘',
      '關閉視窗後留在系統匣',
      'Keep running in the tray after closing',
    ),
    'device.field.startMinimized': ('启动后最小化', '啟動後最小化', 'Start minimized'),
    'device.field.hotkeyBinding': ('浮层快捷键', '浮層快速鍵', 'Overlay shortcut'),
    'device.field.hotkeyEnabled': ('启用快捷键', '啟用快速鍵', 'Enable shortcut'),
    'device.field.opacity': ('浮层不透明度', '浮層不透明度', 'Overlay opacity'),
    'device.field.autoOpenOnGameStart': (
      '游戏启动后打开',
      '遊戲啟動後開啟',
      'Open when the game starts',
    ),
    'device.field.autoOpenOnGameForeground': (
      '游戏切到前台时打开',
      '遊戲切到前景時開啟',
      'Open when the game is foreground',
    ),
    'device.field.autoCloseOnGameBackground': (
      '游戏切到后台时关闭',
      '遊戲切到背景時關閉',
      'Close when the game is background',
    ),
    'device.field.showEventNotifications': (
      '浮层事件提醒',
      '浮層事件提醒',
      'Overlay event notices',
    ),
    'device.field.inAppEnabled': ('应用内通知', '應用程式內通知', 'In-app notifications'),
    'device.field.windowsEnabled': (
      'Windows 通知',
      'Windows 通知',
      'Windows notifications',
    ),
    'device.field.overlayEnabled': ('浮层通知', '浮層通知', 'Overlay notifications'),
    'device.field.directMessageWindowsEnabled': (
      '私聊 Windows 通知',
      '私訊 Windows 通知',
      'Windows notices for direct messages',
    ),
    'device.field.position': (
      '应用内通知位置',
      '應用程式內通知位置',
      'In-app notification position',
    ),
    'device.field.preview': (
      '通知内容预览',
      '通知內容預覽',
      'Notification content preview',
    ),
    'device.field.enabled': ('连续游玩提醒', '連續遊玩提醒', 'Play reminders'),
    'device.field.firstReminderMinutes': (
      '首次提醒时间',
      '首次提醒時間',
      'First reminder after',
    ),
    'device.field.repeatReminderMinutes': (
      '之后提醒间隔',
      '之後提醒間隔',
      'Repeat reminder interval',
    ),
    'device.value.topLeft': ('左上', '左上', 'Top left'),
    'device.value.topRight': ('右上', '右上', 'Top right'),
    'device.value.bottomLeft': ('左下', '左下', 'Bottom left'),
    'device.value.bottomRight': ('右下', '右下', 'Bottom right'),
    'device.value.fullContent': ('显示内容', '顯示內容', 'Show content'),
    'device.value.sourceOnly': ('仅显示来源', '僅顯示來源', 'Source only'),
    'device.value.hiddenDetails': ('隐藏详情', '隱藏詳情', 'Hide details'),
    'localReady': (
      '必要本机设置已确认',
      '必要本機設定已確認',
      'Required local settings confirmed',
    ),
    'localPending': (
      '还有本机设置需要确认',
      '還有本機設定需要確認',
      'Local settings still need confirmation',
    ),
    'recognition': ('游戏识别', '遊戲識別', 'Game recognition'),
    'overlay': ('基础浮层与快捷键', '基礎浮層與快速鍵', 'Basic overlay and shortcuts'),
    'reminders': (
      '通知、提醒与本机数据选择',
      '通知、提醒與本機資料選擇',
      'Notifications, reminders and local data choices',
    ),
    'exitHelp': ('托盘、退出与帮助入口', '系統匣、結束與說明入口', 'Tray, exit and help'),
    'reviewOnline': ('查看在线设置', '查看線上設定', 'Review online settings'),
    'onlineReady': ('在线选择已确认', '線上選擇已確認', 'Online choices confirmed'),
    'onlinePending': (
      '尚未确认在线选择',
      '尚未確認線上選擇',
      'Online choices not confirmed yet',
    ),
    'sharing': (
      '共享由你决定，暂不开启也可以完成设置。',
      '共享由你決定，暫不開啟也可以完成設定。',
      'Sharing is your choice. You can finish setup without enabling it.',
    ),
    'inherit': (
      '资料继承需单独预览和确认，不会自动合并或覆盖。',
      '資料繼承需另外預覽和確認，不會自動合併或覆寫。',
      'Profile inheritance needs a separate preview and confirmation. Nothing is merged or overwritten automatically.',
    ),
    'localSummary': (
      '本机功能准备就绪；在线功能尚未启用。以后从账号入口继续。',
      '本機功能準備就緒；線上功能尚未啟用。以後從帳號入口繼續。',
      'Local features are ready. Online features are not enabled; continue later from Account.',
    ),
    'onlineSummary': (
      '基础设置已就绪。在线功能按账号权限与已确认的选择提供。',
      '基礎設定已就緒。線上功能依帳號權限與已確認的選擇提供。',
      'Basic setup is ready. Online features follow your account permissions and confirmed choices.',
    ),
    'done': ('首次设置已保存', '首次設定已儲存', 'First-use setup saved'),
    'finishPending': (
      '设置尚未满足完成条件，请返回检查未就绪的步骤。',
      '設定尚未滿足完成條件，請返回檢查未就緒的步驟。',
      'Setup is not ready to finish. Go back and check the remaining steps.',
    ),
    'step.welcome': ('欢迎', '歡迎', 'Welcome'),
    'step.mode': ('使用模式', '使用模式', 'Mode'),
    'step.log': ('游戏日志', '遊戲日誌', 'Game log'),
    'step.identity': ('游戏身份', '遊戲身分', 'Game identity'),
    'step.local': ('本机设置', '本機設定', 'Local setup'),
    'step.online': ('在线设置', '線上設定', 'Online setup'),
    'step.summary': ('完成', '完成', 'Finish'),
    'title.welcome': ('使用条款与声明', '使用條款與聲明', 'Terms and notices'),
    'description.welcome': (
      '使用前的许可确认独立于后续设置；同意条款不会自动开启统计或共享。',
      '使用前的授權確認獨立於後續設定；同意條款不會自動開啟統計或分享。',
      'License acceptance is separate from setup. It does not enable recording or sharing.',
    ),
    'title.mode': ('你想怎样开始？', '你想怎樣開始？', 'How would you like to start?'),
    'description.mode': (
      '两种模式都需要连接日志和确认游戏身份。',
      '兩種模式都需要連接日誌和確認遊戲身分。',
      'Both modes need a game log and a confirmed game identity.',
    ),
    'title.log': ('连接你的游戏日志', '連接你的遊戲日誌', 'Connect your game log'),
    'description.log': (
      '确认要使用的游戏版本，自动查找或选择该版本的 Game.log。',
      '確認要使用的遊戲版本，自動尋找或選擇該版本的 Game.log。',
      'Choose your game version, then find or select its Game.log.',
    ),
    'title.identity': ('确认你的游戏身份', '確認你的遊戲身分', 'Confirm your game identity'),
    'description.identity': (
      'Handle 来自有效游戏日志，不是展示呼号。请确认它是你使用的游戏账号。',
      'Handle 來自有效遊戲日誌，不是展示呼號。請確認它是你使用的遊戲帳號。',
      'The Handle comes from a valid game log, not your display callsign. Confirm it is your game account.',
    ),
    'title.local': ('准备本机功能', '準備本機功能', 'Set up local features'),
    'description.local': (
      '确认必要设置，并了解以后在哪里调整。每项功能保留自己的选择。',
      '確認必要設定，並了解以後在哪裡調整。每項功能保留自己的選擇。',
      'Confirm essential settings and where to adjust them later. Each feature keeps its own choices.',
    ),
    'title.online': (
      '按你的选择连接在线功能',
      '依你的選擇連接線上功能',
      'Connect online features on your terms',
    ),
    'description.online': (
      '登录和身份核对不代表同意共享或继承资料。',
      '登入和身分核對不代表同意共享或繼承資料。',
      'Signing in and matching identity do not consent to sharing or profile inheritance.',
    ),
    'title.summary': ('检查你的设置', '檢查你的設定', 'Review your setup'),
    'description.summary': (
      '这里只列出实际已确认的内容。保存成功后才会完成首次设置。',
      '這裡只列出實際已確認的內容。儲存成功後才會完成首次設定。',
      'Only confirmed items are listed. First-use setup finishes only after a successful save.',
    ),
  };
}
