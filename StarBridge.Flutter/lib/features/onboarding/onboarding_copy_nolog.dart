const onboardingNoLogWords = <String, (String, String, String)>{
  'skipLog': (
    '我没有游戏日志，稍后再设置',
    '我沒有遊戲日誌，稍後再設定',
    "I don't have a game log yet, set it up later",
  ),
  'logNeedsLocalBody': (
    '你的账号还没在这台设备上完成在线设置，所以这里暂时不能选游戏日志。改用本机模式后就能继续；以后可以在 设置 › 账号与识别 › 使用模式 切回在线。',
    '你的帳號還沒在這台裝置上完成線上設定，所以這裡暫時無法選擇遊戲日誌。改用本機模式後就能繼續；以後可以在 設定 › 帳號與識別 › 使用模式 切回線上。',
    'Your account has not finished online setup on this device, so a game log cannot be chosen here yet. Switch to local mode to continue; you can switch back to online later in Settings › Account & identity › Usage mode.',
  ),
  'useLocalForLog': ('改用本机模式', '改用本機模式', 'Switch to local mode'),
  'logSearch.blocked': (
    '有个磁盘响应太慢，这次查找没有完成，可能漏掉了日志。请手动选择 Game.log，或稍后再点“重新查找”。',
    '有個磁碟回應太慢，這次尋找沒有完成，可能漏掉了日誌。請手動選擇 Game.log，或稍後再點「重新尋找」。',
    'A disk responded too slowly, so this search did not finish and may have missed your log. Choose Game.log manually, or select "Search again" later.',
  ),
  'storageUnavailable': (
    '这一步没有保存：星海舰桥无法写入它的数据文件夹。请检查磁盘剩余空间，以及数据文件夹是否允许写入，然后再试一次。',
    '這一步沒有儲存：星海艦橋無法寫入它的資料夾。請檢查磁碟剩餘空間，以及資料夾是否允許寫入，然後再試一次。',
    'This step was not saved: StarBridge cannot write to its data folder. Check free disk space and that the data folder can be written to, then try again.',
  ),
  'logDeferredBody': (
    '没关系。没有游戏日志时，在线状态里的游戏信息、游玩时长、按日志解锁的成就和浮层里的游戏数据暂时用不了。以后在 设置 › 账号与识别 › 游戏日志 里选好 Game.log 就能补上。',
    '沒關係。沒有遊戲日誌時，線上狀態裡的遊戲資訊、遊玩時長、按日誌解鎖的成就和浮層裡的遊戲資料暫時無法使用。以後在 設定 › 帳號與識別 › 遊戲日誌 裡選好 Game.log 就能補上。',
    'No problem. Without a game log, game information in online status, play time, log-based achievements, and game data in the overlay are temporarily unavailable. You can add Game.log later in Settings › Account & identity › Game log.',
  ),
  'onlineNeedsLog': (
    '在线模式需要游戏日志来核对你的游戏身份。以后有了日志，可以在 设置 › 账号与识别 › 使用模式 切换到在线。',
    '線上模式需要遊戲日誌來核對你的遊戲身分。以後有了日誌，可以在 設定 › 帳號與識別 › 使用模式 切換到線上。',
    'Online mode needs a game log to check your game identity. When you have a log, you can switch to online in Settings › Account & identity › Usage mode.',
  ),
  'summary.detail.log.deferred': (
    '未设置（可以在 设置 › 账号与识别 › 游戏日志 里补上）',
    '未設定（可以在 設定 › 帳號與識別 › 遊戲日誌 裡補上）',
    'Not set up (you can add it in Settings › Account & identity › Game log)',
  ),
  'sourceInvalid': (
    '这个 Game.log 不在游戏版本文件夹里（例如 LIVE 或 PTU）。请选择游戏安装目录下对应版本文件夹里的 Game.log。',
    '這個 Game.log 不在遊戲版本資料夾裡（例如 LIVE 或 PTU）。請選擇遊戲安裝目錄下對應版本資料夾裡的 Game.log。',
    'This Game.log is not in a game version folder (such as LIVE or PTU). Choose Game.log in the corresponding version folder under the game installation directory.',
  ),
  'accountCard.title': ('已登录 SCM 账号', '已登入 SCM 帳號', 'Signed in to SCM'),
  'accountCard.confirm': (
    '请确认这是你的账号。',
    '請確認這是你的帳號。',
    'Please confirm this is your account.',
  ),
  'accountCard.verified': ('游戏身份已验证', '遊戲身分已驗證', 'Game identity verified'),
  'accountCard.identityPending': (
    '登录成功，游戏身份稍后自动核对',
    '登入成功，遊戲身分稍後自動核對',
    'Signed in. Your game identity will be checked automatically later.',
  ),
  'accountCard.unverified': (
    '还没有验证游戏身份',
    '還沒有驗證遊戲身分',
    'Game identity not verified yet',
  ),
  'accountCard.continue': (
    '是我的账号，继续',
    '是我的帳號，繼續',
    'This is my account, continue',
  ),
  'accountCard.change': ('换一个账号', '換一個帳號', 'Use another account'),
  'accountCard.migrationHint': (
    '已关联旧账号的，请用关联时的 SCM 账号登录，旧账号数据才会迁过来。',
    '已關聯舊帳號的，請用關聯時的 SCM 帳號登入，舊帳號資料才會遷過來。',
    'If you linked an old account, sign in with the SCM account you linked it to, so the old account data can migrate.',
  ),
  'onlineReview.namesMatch': ('游戏名一致', '遊戲名稱一致', 'Game names match'),
};
