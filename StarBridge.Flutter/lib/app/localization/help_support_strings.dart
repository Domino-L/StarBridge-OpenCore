import 'package:flutter/widgets.dart';

import 'overlay_workspace_en_strings.dart'
    show windowsSystemHotkeyApi, windowsSystemHotkeyApiCjk;

const _menuFocusCall = 'AttachThreadInput';

const helpSupportZhCn = <String, String>{
  'help.scm.openFailed': '未能打开浏览器，可手动访问 {host}。',
  'help.website.tooltip': '星海舰桥官网',
  'help.title': '帮助与支持',
  'help.description': '了解游戏识别、隐私与使用规则，并查找更新和反馈方式。',
  'help.topic.log': '游戏日志识别',
  'help.topic.log.description': 'Game.log、身份、舰船与地点',
  'help.topic.legal': '说明与声明',
  'help.topic.legal.description': '数据、游戏安全与素材说明',
  'help.topic.version': '更新与版本',
  'help.topic.version.description': '版本状态与更新方式',
  'help.topic.feedback': '反馈与建议',
  'help.topic.feedback.description': '反馈问题、提出建议或功能需求',
  'help.log.title': '游戏日志识别说明',
  'help.log.description': '了解游戏内行为如何变成应用中的状态，以及信息没有及时更新时可以怎么处理。',
  'help.log.scope.title': '只读取你选择的 Game.log',
  'help.log.scope.body':
      '星海舰桥不会读取游戏内存、注入游戏或修改游戏文件。只有日志写出新的有效信息时，应用才会更新对应状态；没有新信息时会保留最近一次可靠结果。',
  'help.log.troubleshoot.title': '信息没有更新时',
  'help.log.troubleshoot.body': '先确认 Game.log 路径和最后更新时间。飞船未识别时可在船内按 F2 打开星图；离船状态未清除时请等待离开飞船频道事件。仍有问题，可前往“诊断与维护”查看本地状态。',
  'help.log.catalog': '分类说明',
  'help.log.session.title': '日志读取与游戏会话',
  'help.log.session.body':
      '• 读取你在“账号与识别”中选定游戏版本的 Game.log。\n'
      '• 启动时只读取末尾的近期内容来恢复状态，不会把旧事件当作刚刚发生。\n'
      '• 游戏运行中只处理文件末尾新增的完整行；普通调试信息和未知内容会被忽略。\n'
      '• 日志被清空或重新生成后会从新文件开头继续读取，暂时缺失时会等待文件恢复。\n'
      '• 游戏启动与退出由本机进程确认；相隔超过 30 秒的未知时段不会补记为游玩时间。',
  'help.log.identity.title': '身份识别、账号绑定与在线状态',
  'help.log.identity.body':
      '• 游戏身份来自 Game.log，账号身份来自当前登录的旧账号或 SCM 账号，两者会在同步前分别核对。\n'
      '• 首次识别的游戏 ID 需要与当前账号绑定；不一致时停止账号同步，避免资料串号。\n'
      '• 切换账号后只读取新账号自己的资料、好友、舰队、房间和本机记录。\n'
      '• “应用在线”和“游戏中”是两种状态；仅打开应用不会被显示为游戏在线。\n'
      '• 手动离线或隐身不会被 Game.log 覆盖，隐身时对外按离线处理。',
  'help.log.server.title': '服务器与分线识别',
  'help.log.server.body':
      '• 进入 PU 或分线更新后，应用会识别当前服务器区域和分线。\n'
      '• 主动断开、远程断开或返回主菜单后会清除旧服务器信息。\n'
      '• 应用启动时仅在确认游戏仍运行后回扫最近一次进入或离开记录。\n'
      '• 同服人数与进出服务器提醒只会使用双方允许共享的信息。',
  'help.log.ship.title': '飞船识别与状态保留',
  'help.log.ship.body':
      '• 加入飞船频道是最可靠的进入信号；明确离开频道后才清除多座飞船。\n'
      '• 获得驾驶控制属于强信号，打开星图或设置路线只作为辅助识别。\n'
      '• 对允许在内部活动的飞船，离开驾驶位不会直接被当作下船。\n'
      '• 进入明确地面区域、离线或出现新的可靠飞船信号会结束旧状态。\n'
      '• 舰船名称优先使用已验证中文对照，未知型号保留可识别原名，不会猜测。',
  'help.log.location.title': '地点、导航与量子航行',
  'help.log.location.body':
      '• 当前位置、导航目标和量子抵达是三种独立信息，设置目标不会直接改变当前位置。\n'
      '• 明确区域事件优先；抵达前后 15 秒内取得的明确地点不会被迟到的量子日志覆盖。\n'
      '• 量子抵达只认你自己驾驶或导航的飞船；附近别人的船跳跃、你坐别人的船当乘客，都不会弹出“量子抵达”。\n'
      '• “等待位置确认”“地点待确认”这类占位文字不算认得的地点，不会进地点分组、面罩上的当前位置和共享活动卡；只有真的换了地点才会弹出抵达提醒。\n'
      '• 未收录地点保留可识别代码，不会自动上传地点代码。',
  'help.log.health.title': '倒地、死亡、救起与重生',
  'help.log.health.body':
      '• 倒地、死亡、救起和重生使用连续事件确认，避免把加载或网络波动误判。\n'
      '• 死亡需要近期倒地作为前置；普通解绑不会被单独计为死亡。\n'
      '• 救起需要恢复后的活动，重生需要新的绑定和后续恢复事件共同确认。\n'
      '• 重复事件会合并；是否对外显示由你的事件共享设置决定。\n'
      '• 游玩时长只有在允许记录后才会在本机累计。',
  'help.log.contracts.title': '合约与任务记录',
  'help.log.contracts.body':
      '• 接单、阶段目标、完成、失败和放弃从游戏通知和任务日志里识别，汉化客户端的提示也能读到。\n'
      '• 这些记录会进入“诊断与维护 › 本地事件日志”的“合约”类别，只存在本机。\n'
      '• 工具里的“任务库”只记完成的合约：每种合约完成了几次、最快用了多久。\n'
      '• 最快用时分单人、组队和加入他人：自己接的单从接单算起，加入他人的单从你加入那一刻算起。\n'
      '• 可以从以前的游戏日志导入任务记录，重复导入不会重复计数；旧日志里没有接单提示时，用任务开始的时间补上。',
  'help.log.achievements.title': '成就与日志确认',
  'help.log.achievements.body':
      '• 城市、空间站这类旅程成就，要由游戏日志确认你到了那个地点才会解锁；只设置导航目标不算。\n'
      '• 以前到过、但当时星海舰桥没有记录的地点不会补发。\n'
      '• 合约成就按本机的合约记录判断，例如“开张大吉”要你本人完成一整单，只完成阶段目标不算。\n'
      '• 确认到的地点先保存在本机，网络断开也不会丢，恢复后再同步。\n'
      '• 切换账号后，新的确认只记给当时登录的账号。',
  'help.log.records.title': '记录、同步、隐私与历史导入',
  'help.log.records.body':
      '• 日志识别、本地留存、账号同步和公开展示是四个独立环节。\n'
      '• 本地事件日志只保存整理后的摘要、时间和分类，不复制完整 Game.log。\n'
      '• 只有登录、身份匹配且共享开关允许时，才会发送即时协作状态。\n'
      '• 低可信度位置可限制为仅在本机显示；关闭事件共享不会停止本机识别。\n'
      '• 历史导入有两种：游玩时长只导入 LIVE 记录，需由你确认，重置时长后可再导入一次；任务记录可以反复导入，同一份日志不会重复计数。',
  'help.log.confidence.title': '进阶：飞船与地点可信度',
  'help.log.confidence.body':
      '• 可信度用于处理同时出现的矛盾日志，不是玩家评分，也不影响游玩时长。\n'
      '• 80–100 为高、45–79 为中、15–44 为低，低于 15 视为未知。\n'
      '• 飞船频道与明确地点属于强证据；导航上下文、路线和抵达属于辅助证据。\n'
      '• 证据会随时间降低可信度，新证据只在符合当前会话时更新结果。\n'
      '• 离线后仅以低可信度恢复最后已知值，等待新的游戏日志确认。',
  'help.legal.title': '隐私与使用说明',
  'help.legal.description': '查看星海舰桥如何使用信息，以及使用时需要了解的事项。',
  'help.legal.operation.title': '星海舰桥如何工作',
  'help.legal.operation.body': '星海舰桥帮助你管理舰队与房间、查看成员状态、舰船和地点信息，并通过游戏浮层提供协作信息。这些内容用于玩家之间的组织和沟通，不属于游戏官方数据。选择 Game.log 后，应用会在本机识别相关状态；登录后，仅有必要且获准的信息会用于协作同步。',
  'help.legal.data.title': '你的数据与隐私',
  'help.legal.data.body': '应用会在这台设备上保存设置、登录状态、日志路径、浮层布局和必要缓存。游玩时长只有在你允许后才会记录。提交反馈时请勿填写密码、验证码、恢复码、支付信息或其他敏感内容。',
  'help.legal.safety.title': '游戏安全与信息准确性',
  'help.legal.safety.body': rsiToolNoticeZhCnBody,
  'help.legal.unofficial.title': '非官方说明',
  'help.legal.unofficial.body': '星海舰桥是玩家独立开发的非官方社区工具，与 Cloud Imperium 集团及其关联公司不存在隶属、合作、授权、赞助或认可关系。相关名称、商标、标志、图像、舰船设计和游戏素材的权利归其各自权利人所有。',
  'help.legal.use.title': '使用须知',
  'help.legal.use.body': '应用可能因游戏更新、网络波动或兼容性问题出现中断、延迟或识别错误。请遵守游戏、平台和所在社区的规则，不得用于违法、侵权、骚扰、作弊或干扰他人正常使用的行为。',
  'help.legal.licenses.title': '开源软件许可',
  'help.legal.licenses.body': '浏览当前客户端包含的 Flutter、依赖包和内置字体许可。显示内容来自本次安装包，不会联网。',
  'help.legal.licenses.open': '查看开源软件许可',
  'help.legal.licenses.legalese': '各项目仍由其原始许可条款约束。',
  'help.version.title': '应用更新',
  'help.version.description': '在这里查看版本状态并检查安装器与完整安装包更新。更新安装中途中断时，请直接用完整安装包安装最新版，不要装回旧版本。从 0.7.3 起，下次准备更新时会自动挪开与当前版本不符的旧的未完成更新，并保留其中的文件，让后续更新可以继续准备。',
  'help.version.status.title': '版本状态',
  'help.version.status.unavailable': '暂时无法读取版本与更新状态。请通过当前安装来源获取新版本。',
  'help.version.check': '检查更新',
  'help.version.notice': '更新期间应用可能暂时锁定，完成后可能自动关闭并重新启动。',
  'help.feedback.title': '反馈与建议',
  'help.feedback.description': '遇到了问题、有改进建议，或希望添加新功能，都可以告诉我们。',
  'help.feedback.inApp.title': '应用内反馈',
  'help.feedback.inApp.unavailable': '应用内反馈暂时不可用，你可以先通过下面的 QQ 群或邮箱联系我们。',
  'help.feedback.group.title': 'SCM 星海舰桥反馈群',
  'help.feedback.group.body': '用于问题交流、使用建议和版本反馈。群内信息依照 QQ 平台及群管理规则处理。',
  'help.feedback.group.number': '群号：534268220',
  'help.feedback.group.copy': '复制群号',
  'help.feedback.group.copied': '星海舰桥反馈群号已复制。',
  'help.feedback.teamGroup.title': 'SCM 团队 QQ 反馈群',
  'help.feedback.teamGroup.body': 'SCM 团队的反馈群。如果希望加入我们，也请进入此群。群内信息依照 QQ 平台及群管理规则处理。',
  'help.feedback.teamGroup.number': '群号：588620092',
  'help.feedback.teamGroup.copy': '复制群号',
  'help.feedback.teamGroup.copied': 'SCM 团队群号已复制。',
  'help.feedback.email.title': '邮件联系',
  'help.feedback.email.body': '可以发邮件联系我们。请不要在邮件里写密码、验证码或其他敏感信息。',
  'help.feedback.email.number': '邮箱：scstarbridge.app@gmail.com',
  'help.feedback.email.copy': '复制邮箱',
  'help.feedback.email.copied': '邮箱地址已复制。',
};

const helpSupportZhTw = <String, String>{
  'help.scm.openFailed': '未能開啟瀏覽器，可手動前往 {host}。',
  'help.website.tooltip': '星海艦橋官網',
  'help.title': '幫助與支援',
  'help.description': '瞭解遊戲辨識、隱私與使用規則，並查找更新和意見回饋方式。',
  'help.topic.log': '遊戲日誌辨識',
  'help.topic.log.description': 'Game.log、身分、艦船與地點',
  'help.topic.legal': '說明與聲明',
  'help.topic.legal.description': '資料、遊戲安全與素材說明',
  'help.topic.version': '更新與版本',
  'help.topic.version.description': '版本狀態與更新方式',
  'help.topic.feedback': '回饋與建議',
  'help.topic.feedback.description': '回報問題、提出建議或功能需求',
  'help.log.title': '遊戲日誌辨識說明',
  'help.log.description': '瞭解遊戲內行為如何成為應用程式狀態，以及資訊沒有及時更新時可以怎麼處理。',
  'help.log.scope.title': '只讀取你選擇的 Game.log',
  'help.log.scope.body':
      '星海艦橋不會讀取遊戲記憶體、注入遊戲或修改遊戲檔案。只有日誌寫出新的有效資訊時，應用程式才會更新對應狀態；沒有新資訊時會保留最近一次可靠結果。',
  'help.log.troubleshoot.title': '資訊沒有更新時',
  'help.log.troubleshoot.body': '先確認 Game.log 路徑和最後更新時間。艦船未辨識時可在船內按 F2 開啟星圖；離船狀態未清除時請等待離開艦船頻道事件。仍有問題，可前往「診斷與維護」查看本機狀態。',
  'help.log.catalog': '分類說明',
  'help.log.session.title': '日誌讀取與遊戲工作階段',
  'help.log.session.body': '• 讀取你在「帳號與識別」中選定遊戲版本的 Game.log。\n• 啟動時只讀取末尾的近期內容來恢復狀態，不會把舊事件當作剛剛發生。\n• 遊戲執行中只處理檔案末尾新增的完整行；普通偵錯資訊和未知內容會被忽略。\n• 日誌被清空或重新產生後會從新檔案開頭繼續讀取，暫時缺失時會等待檔案恢復。\n• 遊戲啟動與退出由本機程序確認；相隔超過 30 秒的未知時段不會補記為遊玩時間。',
  'help.log.identity.title': '身分辨識、帳號綁定與線上狀態',
  'help.log.identity.body': '• 遊戲身分來自 Game.log，帳號身分來自目前登入的舊帳號或 SCM 帳號，兩者會在同步前分別核對。\n• 首次辨識的遊戲 ID 需要與目前帳號綁定；不一致時停止帳號同步，避免資料串號。\n• 切換帳號後只讀取新帳號自己的資料、好友、艦隊、房間和本機記錄。\n• 「應用程式線上」和「遊戲中」是兩種狀態；僅開啟應用程式不會被顯示為遊戲線上。\n• 手動離線或隱身不會被 Game.log 覆蓋，隱身時對外按離線處理。',
  'help.log.server.title': '伺服器與分線辨識',
  'help.log.server.body': '• 進入 PU 或分線更新後，應用程式會辨識目前伺服器區域和分線。\n• 主動中斷、遠端中斷或返回主選單後會清除舊伺服器資訊。\n• 應用程式啟動時僅在確認遊戲仍執行後回掃最近一次進入或離開記錄。\n• 同服人數與進出伺服器提醒只會使用雙方允許分享的資訊。',
  'help.log.ship.title': '艦船辨識與狀態保留',
  'help.log.ship.body': '• 加入艦船頻道是最可靠的進入訊號；明確離開頻道後才清除多座艦船。\n• 取得駕駛控制屬於強訊號，開啟星圖或設定路線只作為輔助辨識。\n• 對允許在內部活動的艦船，離開駕駛位不會直接被當作下船。\n• 進入明確地面區域、離線或出現新的可靠艦船訊號會結束舊狀態。\n• 艦船名稱優先使用已驗證中文對照，未知型號保留可辨識原名，不會猜測。',
  'help.log.location.title': '地點、導航與量子航行',
  'help.log.location.body': '• 目前位置、導航目標和量子抵達是三種獨立資訊，設定目標不會直接改變目前位置。\n• 明確區域事件優先；抵達前後 15 秒內取得的明確地點不會被遲到的量子日誌覆蓋。\n• 量子抵達只認你自己駕駛或導航的艦船；附近別人的船跳躍、你搭別人的船當乘客，都不會彈出「量子抵達」。\n• 「等待位置確認」「地點待確認」這類佔位文字不算已辨識的地點，不會進入地點分組、面罩上的目前位置和共享活動卡；只有真的換了地點才會彈出抵達提醒。\n• 未收錄地點保留可辨識代碼，不會自動上傳地點代碼。',
  'help.log.health.title': '倒地、死亡、救起與重生',
  'help.log.health.body': '• 倒地、死亡、救起和重生使用連續事件確認，避免把載入或網路波動誤判。\n• 死亡需要近期倒地作為前置；普通解除綁定不會被單獨計為死亡。\n• 救起需要恢復後的活動，重生需要新的綁定和後續恢復事件共同確認。\n• 重複事件會合併；是否對外顯示由你的事件分享設定決定。\n• 遊玩時間只有在允許記錄後才會在本機累計。',
  'help.log.contracts.title': '合約與任務記錄',
  'help.log.contracts.body': '• 接單、階段目標、完成、失敗和放棄從遊戲通知和任務日誌裡辨識，中文化用戶端的提示也能讀到。\n• 這些記錄會進入「診斷與維護 › 本機事件記錄」的「合約」類別，只存在本機。\n• 工具裡的「任務庫」只記完成的合約：每種合約完成了幾次、最快用了多久。\n• 最快用時分單人、組隊和加入他人：自己接的單從接單算起，加入他人的單從你加入那一刻算起。\n• 可以從以前的遊戲日誌匯入任務記錄，重複匯入不會重複計數；舊日誌裡沒有接單提示時，用任務開始的時間補上。',
  'help.log.achievements.title': '成就與日誌確認',
  'help.log.achievements.body': '• 城市、太空站這類旅程成就，要由遊戲日誌確認你到了那個地點才會解鎖；只設定導航目標不算。\n• 以前到過、但當時星海艦橋沒有記錄的地點不會補發。\n• 合約成就按本機的合約記錄判斷，例如「開張大吉」要你本人完成一整單，只完成階段目標不算。\n• 確認到的地點先保存在本機，網路斷開也不會遺失，恢復後再同步。\n• 切換帳號後，新的確認只記給當時登入的帳號。',
  'help.log.records.title': '記錄、同步、隱私與歷史匯入',
  'help.log.records.body': '• 日誌辨識、本機留存、帳號同步和公開展示是四個獨立環節。\n• 本機事件日誌只儲存整理後的摘要、時間和分類，不複製完整 Game.log。\n• 只有登入、身分符合且分享開關允許時，才會傳送即時協作狀態。\n• 低可信度位置可限制為僅在本機顯示；關閉事件分享不會停止本機辨識。\n• 歷史匯入有兩種：遊玩時間只匯入 LIVE 記錄，需由你確認，重設時間後可再匯入一次；任務記錄可以反覆匯入，同一份日誌不會重複計數。',
  'help.log.confidence.title': '進階：艦船與地點可信度',
  'help.log.confidence.body': '• 可信度用於處理同時出現的矛盾日誌，不是玩家評分，也不影響遊玩時間。\n• 80–100 為高、45–79 為中、15–44 為低，低於 15 視為未知。\n• 艦船頻道與明確地點屬於強證據；導航內容、路線和抵達屬於輔助證據。\n• 證據會隨時間降低可信度，新證據只在符合目前工作階段時更新結果。\n• 離線後僅以低可信度恢復最後已知值，等待新的遊戲日誌確認。',
  'help.legal.title': '隱私與使用說明',
  'help.legal.description': '查看星海艦橋如何使用資訊，以及使用時需要瞭解的事項。',
  'help.legal.operation.title': '星海艦橋如何運作',
  'help.legal.operation.body': '星海艦橋幫助你管理艦隊與房間、查看成員狀態、艦船和地點資訊，並透過遊戲浮層提供協作資訊。這些內容用於玩家之間的組織和溝通，不屬於遊戲官方資料。選擇 Game.log 後，應用程式會在本機辨識相關狀態；登入後，僅有必要且獲准的資訊會用於協作同步。',
  'help.legal.data.title': '你的資料與隱私',
  'help.legal.data.body': '應用程式會在這台裝置上儲存設定、登入狀態、日誌路徑、浮層配置和必要快取。遊玩時間只有在你允許後才會記錄。提交回饋時請勿填寫密碼、驗證碼、復原碼、付款資訊或其他敏感內容。',
  'help.legal.safety.title': '遊戲安全與資訊準確性',
  'help.legal.safety.body': rsiToolNoticeZhTwBody,
  'help.legal.unofficial.title': '非官方說明',
  'help.legal.unofficial.body': '星海艦橋是玩家獨立開發的非官方社群工具，與 Cloud Imperium 集團及其關聯公司不存在隸屬、合作、授權、贊助或認可關係。相關名稱、商標、標誌、圖像、艦船設計和遊戲素材的權利歸其各自權利人所有。',
  'help.legal.use.title': '使用須知',
  'help.legal.use.body': '應用程式可能因遊戲更新、網路波動或相容性問題出現中斷、延遲或辨識錯誤。請遵守遊戲、平台和所在社群的規則，不得用於違法、侵權、騷擾、作弊或干擾他人正常使用的行為。',
  'help.legal.licenses.title': '開源軟體授權',
  'help.legal.licenses.body':
      '瀏覽目前客戶端包含的 Flutter、相依套件和內建字型授權。顯示內容來自本次安裝包，不會連線。',
  'help.legal.licenses.open': '查看開源軟體授權',
  'help.legal.licenses.legalese': '各項目仍受其原始授權條款約束。',
  'help.version.title': '應用程式更新',
  'help.version.description': '在這裡查看版本狀態並檢查安裝程式與完整安裝包更新。更新安裝中途中斷時，請直接用完整安裝包安裝最新版，不要裝回舊版本。從 0.7.3 起，下次準備更新時會自動移開與目前版本不符的舊的未完成更新，並保留其中的檔案，讓後續更新可以繼續準備。',
  'help.version.status.title': '版本狀態',
  'help.version.status.unavailable': '暫時無法讀取版本與更新狀態。請透過目前安裝來源取得新版本。',
  'help.version.check': '檢查更新',
  'help.version.notice': '更新期間應用程式可能暫時鎖定，完成後可能自動關閉並重新啟動。',
  'help.feedback.title': '回饋與建議',
  'help.feedback.description': '遇到了問題、有改進建議，或希望新增功能，都可以告訴我們。',
  'help.feedback.inApp.title': '應用程式內回饋',
  'help.feedback.inApp.unavailable': '應用程式內回饋暫時無法使用，你可以先透過下面的 QQ 群或電子郵件聯絡我們。',
  'help.feedback.group.title': 'SCM 星海艦橋回饋群',
  'help.feedback.group.body': '用於問題交流、使用建議和版本回饋。群內資訊依照 QQ 平台及群管理規則處理。',
  'help.feedback.group.number': '群號：534268220',
  'help.feedback.group.copy': '複製群號',
  'help.feedback.group.copied': '星海艦橋回饋群號已複製。',
  'help.feedback.teamGroup.title': 'SCM 團隊 QQ 回饋群',
  'help.feedback.teamGroup.body': 'SCM 團隊的回饋群。如果希望加入我們，也請進入此群。群內資訊依照 QQ 平台及群管理規則處理。',
  'help.feedback.teamGroup.number': '群號：588620092',
  'help.feedback.teamGroup.copy': '複製群號',
  'help.feedback.teamGroup.copied': 'SCM 團隊群號已複製。',
  'help.feedback.email.title': '電子郵件聯絡',
  'help.feedback.email.body': '可以寄電子郵件聯絡我們。請不要在郵件中填寫密碼、驗證碼或其他敏感資訊。',
  'help.feedback.email.number': '電子郵件：scstarbridge.app@gmail.com',
  'help.feedback.email.copy': '複製電子郵件',
  'help.feedback.email.copied': '電子郵件地址已複製。',
};

const helpSupportEnUs = <String, String>{
  'help.scm.openFailed':
      'Could not open your browser. Visit {host} manually.',
  'help.website.tooltip': 'StarBridge website',
  'help.title': 'Help & support',
  'help.description': 'Learn how game detection works, review privacy and usage notes, and find update or feedback options.',
  'help.topic.log': 'Game log detection',
  'help.topic.log.description': 'Game.log, identity, ships, and location',
  'help.topic.legal': 'Notices & terms',
  'help.topic.legal.description': 'Data, game safety, and asset notices',
  'help.topic.version': 'Updates & version',
  'help.topic.version.description': 'Version status and update options',
  'help.topic.feedback': 'Feedback & suggestions',
  'help.topic.feedback.description':
      'Report problems, suggest improvements, or request features',
  'help.log.title': 'Game log detection',
  'help.log.description': 'See how in-game activity becomes app status and what to do when information has not updated.',
  'help.log.scope.title': 'Only the Game.log you select is read',
  'help.log.scope.body': 'StarBridge does not read game memory, inject into the game, or modify game files. Status changes only when the log contains new, valid information. Otherwise, the latest reliable result is kept.',
  'help.log.troubleshoot.title': 'When information does not update',
  'help.log.troubleshoot.body': 'Check the Game.log path and its last modified time. If your ship is missing, press F2 while aboard to open the star map. After leaving a ship, wait for the leave-channel event. If the issue continues, open Diagnostics & maintenance.',
  'help.log.catalog': 'Topics',
  'help.log.session.title': 'Log reading and game sessions',
  'help.log.session.body': '• Reads Game.log for the game version selected in Account and identity.\n• Startup reads only recent lines near the end to restore state; old entries are not treated as new events.\n• While the game runs, only newly appended complete lines are processed; debug and unknown content is ignored.\n• If the log is replaced or truncated, reading resumes from the new file. Temporary absence is tolerated.\n• Game start and exit come from the local process; unknown sampling gaps over 30 seconds are not counted as play time.',
  'help.log.identity.title': 'Identity, account binding, and presence',
  'help.log.identity.body': '• Game identity comes from Game.log and account identity comes from your signed-in legacy or SCM account; both are checked before sync.\n• A newly detected game ID must match the current account. A mismatch stops account sync to prevent cross-account data.\n• Switching accounts loads only that account’s profile, friends, fleet, rooms, and local records.\n• “App online” and “in game” are separate states; opening the app alone does not make you game-online.\n• Manual offline and invisible modes are privacy choices and are not overridden by Game.log.',
  'help.log.server.title': 'Server and shard detection',
  'help.log.server.body': '• Entering the PU or receiving a shard update identifies the current server region and shard.\n• Disconnecting or returning to the main menu clears old server details.\n• Startup scans recent server entries only after confirming that the game is still running.\n• Same-server counts and join or leave alerts use only information both players allow to be shared.',
  'help.log.ship.title': 'Ship detection and retained state',
  'help.log.ship.body': '• Joining a vehicle channel is the strongest boarding signal; multi-crew ships clear after an explicit leave event.\n• Taking control is strong evidence, while opening the star map or planning a route is supporting evidence.\n• Leaving the pilot seat does not mean leaving a ship that supports interior movement.\n• A confirmed ground area, going offline, or stronger evidence for another ship ends the old state.\n• Verified Chinese names are preferred; unknown models keep a recognizable original name and are never guessed.',
  'help.log.location.title': 'Location, navigation, and quantum travel',
  'help.log.location.body': '• Current location, navigation target, and quantum arrival are separate facts. Choosing a target does not move your location.\n• Confirmed area events take priority, and a confirmed location within 15 seconds of arrival is protected from late quantum log entries.\n• Quantum arrival counts only for a ship you fly or navigate. Another ship jumping nearby, or riding as a passenger, never shows “Quantum arrival”.\n• Placeholder text such as “Location pending” never counts as a known place: it stays out of location groups, the current location on the visor, and shared activity cards. Arrival alerts appear only when you actually move to another place.\n• Unknown location codes remain local and are not uploaded automatically.',
  'help.log.health.title': 'Incapacitation, death, rescue, and respawn',
  'help.log.health.body': '• Related events are combined so loading and network interruptions are not mistaken for player state.\n• Death requires a recent incapacitation; an ordinary unbind does not count by itself.\n• Rescue requires activity after recovery, while respawn requires a new bind followed by recovery activity.\n• Duplicate events are merged. External visibility follows your event-sharing choices.\n• Play time is recorded locally only after you allow it.',
  'help.log.contracts.title': 'Contracts and mission records',
  'help.log.contracts.body': '• Accepting, objectives, completion, failure, and abandonment are read from game notifications and mission log lines, including those of the Chinese-language client.\n• These records go to Diagnostics & maintenance › Local event log under the Contracts category and stay on this device.\n• The Mission library in Tools records completed contracts only: how many times you finished each one and your fastest time.\n• Fastest times are split into solo, team, and joined: your own contracts count from acceptance, joined ones from the moment you joined.\n• Mission records can be imported from earlier game logs without double counting. When an old log has no acceptance notice, the mission start time is used.',
  'help.log.achievements.title': 'Achievements confirmed by the log',
  'help.log.achievements.body': '• Journey achievements such as cities and stations unlock only after the game log confirms you reached the place. Setting a navigation target is not enough.\n• Places you visited before StarBridge recorded them are not awarded retroactively.\n• Contract achievements follow your local contract records. For example, Open for Business needs you to complete a whole contract yourself; objectives alone do not count.\n• A confirmed place is saved on this device first, so a network outage cannot lose it; it syncs once the connection returns.\n• After switching accounts, new confirmations are credited only to the account signed in at that time.',
  'help.log.records.title': 'Records, sync, privacy, and history import',
  'help.log.records.body': '• Detection, local retention, account sync, and public visibility are four separate stages.\n• The local event log stores normalized summaries, time, and category—not a copy of the full Game.log.\n• Live collaboration status is sent only while signed in, identity-matched, and allowed by your sharing choices.\n• Low-confidence locations can stay local. Disabling event sharing does not stop local detection.\n• There are two history imports: play time imports LIVE records only, after your confirmation, and resetting play time restores one import; mission records can be imported repeatedly and the same log is never counted twice.',
  'help.log.confidence.title': 'Advanced: ship and location confidence',
  'help.log.confidence.body': '• Confidence resolves conflicting log evidence. It is not a player rating and does not affect play time.\n• 80–100 is high, 45–79 medium, 15–44 low, and below 15 unknown.\n• Vehicle channels and confirmed areas are strong evidence; navigation context, routes, and arrivals are supporting evidence.\n• Evidence decays over time, and new evidence updates the result only when it belongs to the current session.\n• After reconnecting, last-known values return only at low confidence until fresh game evidence confirms them.',
  'help.legal.title': 'Privacy and usage notes',
  'help.legal.description': 'Review how StarBridge uses information and what you should know while using it.',
  'help.legal.operation.title': 'How StarBridge works',
  'help.legal.operation.body': 'StarBridge helps players coordinate fleets and rooms, view member, ship, and location status, and use an in-game overlay. This is community coordination information, not official game data. After you select Game.log, relevant state is detected locally; after sign-in, only necessary and permitted information is used for collaboration sync.',
  'help.legal.data.title': 'Your data and privacy',
  'help.legal.data.body': 'The app stores settings, sign-in state, selected log paths, overlay layouts, and required caches on this device. Play time is recorded only after you allow it. Never include passwords, verification or recovery codes, payment details, or other sensitive information in feedback.',
  'help.legal.safety.title': 'Game safety and accuracy',
  'help.legal.safety.body': rsiToolNoticeEnUsBody,
  'help.legal.unofficial.title': 'Unofficial project notice',
  'help.legal.unofficial.body': 'StarBridge is an independently developed community tool. It is not affiliated with, authorized, sponsored, or endorsed by Cloud Imperium or its related companies. Related names, trademarks, logos, images, ship designs, and game materials belong to their respective rights holders.',
  'help.legal.use.title': 'Usage notice',
  'help.legal.use.body': 'Game updates, network conditions, and compatibility changes may interrupt or delay the app or produce incorrect detections. Follow the rules of the game, platform, and your communities. Do not use StarBridge for unlawful conduct, infringement, harassment, cheating, or disruption.',
  'help.legal.licenses.title': 'Open-source licenses',
  'help.legal.licenses.body': 'Browse licenses for Flutter, dependency packages, and bundled fonts in this client. The content comes from this installation and does not require a network connection.',
  'help.legal.licenses.open': 'View open-source licenses',
  'help.legal.licenses.legalese':
      'Each project remains governed by its original license terms.',
  'help.version.title': 'Application updates',
  'help.version.description': 'View version status and check for installer or full-package updates here. If an update installation is interrupted, use the full installer to install the latest version. Do not reinstall an older version. Starting with 0.7.3, preparing another update automatically moves aside unfinished updates that no longer match the installed version, keeping their files so the next update can proceed.',
  'help.version.status.title': 'Version status',
  'help.version.status.unavailable': 'Version and update status is temporarily unavailable. Use your current installation source to get a newer version.',
  'help.version.check': 'Check for updates',
  'help.version.notice': 'The app may be briefly locked during an update and may close and restart when it finishes.',
  'help.feedback.title': 'Feedback & suggestions',
  'help.feedback.description': 'Tell us about a problem, an improvement you would like, or a new feature you need.',
  'help.feedback.inApp.title': 'In-app feedback',
  'help.feedback.inApp.unavailable': 'In-app feedback is temporarily unavailable. You can contact us through a QQ group or by email below.',
  'help.feedback.group.title': 'SCM StarBridge feedback group',
  'help.feedback.group.body': 'Use the group for troubleshooting, suggestions, and release feedback. Messages and profiles follow QQ and group moderation rules.',
  'help.feedback.group.number': 'Group: 534268220',
  'help.feedback.group.copy': 'Copy group number',
  'help.feedback.group.copied': 'StarBridge feedback group number copied.',
  'help.feedback.teamGroup.title': 'SCM team QQ feedback group',
  'help.feedback.teamGroup.body': 'The SCM team feedback group. If you would like to join us, please join this group too. Messages and profiles follow QQ and group moderation rules.',
  'help.feedback.teamGroup.number': 'Group: 588620092',
  'help.feedback.teamGroup.copy': 'Copy group number',
  'help.feedback.teamGroup.copied': 'SCM team group number copied.',
  'help.feedback.email.title': 'Email',
  'help.feedback.email.body': 'You can email us. Do not include passwords, verification codes, or other sensitive information.',
  'help.feedback.email.number': 'Email: scstarbridge.app@gmail.com',
  'help.feedback.email.copy': 'Copy email address',
  'help.feedback.email.copied': 'Email address copied.',
};

/// Approved copy from RSI_NOTICE_FINAL.md. The receipt is separate from terms.
class RsiToolNoticeCopy {
  const RsiToolNoticeCopy(this.title, this.body, this.button);
  final String title, body, button;
}

RsiToolNoticeCopy rsiToolNoticeCopy(Locale locale) =>
    locale.languageCode == 'en'
    ? rsiToolNoticeEnUs
    : locale.scriptCode == 'Hant' ||
          const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
    ? rsiToolNoticeZhTw
    : rsiToolNoticeZhCn;
const rsiToolNoticeEnUsBody =
    '''Here is what StarBridge does and does not do on your computer. Whether this complies with the RSI terms is for CIG to decide. We cannot decide that for them, so please assess it yourself.

What it does

1. Reads Game.log for the game version you choose. When it detects your local identity or imports past play time, it also reads older logs in the logbackups folder next to it. Read only, never modified.
2. Key bindings: only when you open the Key bindings page, switch the game version or language on it, or press Read again, it reads actionmaps.xml in the selected game version's folder to show your keys. The official build also reads the global.ini for the selected language under data\\Localization in that folder, if there is one, and takes only action names from it. So that you can choose the language, it also lists the languages installed in that folder. These files are read on this computer only. They are not written to, and your keys and localization files are not changed.
3. Checks the Windows process list to see whether the game is running, and opens the game process with limited query rights to read only its program path, start time and whether it has exited.
4. Receives your shortcuts through Raw Input without blocking keys, so the game still gets them. You can switch to Windows system hotkeys $windowsSystemHotkeyApi in Settings (off by default); when they are on, other programs usually do not receive these key combinations, but testing shows Star Citizen still receives them when it is in front.
5. Shows the overlay, in-game menu, reference images and alerts in StarBridge's own separate windows.
6. When you open the menu with its shortcut (Alt+M by default) and Windows refuses to switch focus, it briefly attaches the menu window's thread to the game window's input queue ($_menuFocusCall) and detaches right after the switch.
7. When you click Screenshot, it captures the whole display the menu is on, including any other visible windows. Screenshots stay on this device or go to the clipboard; they are not uploaded automatically.
8. Hangar reading: opens the official RSI hangar page inside StarBridge, where you sign in to RSI yourself; StarBridge reads the Handle and ships shown on the page. When you read your hangar, you can choose whether this computer remembers your RSI sign-in; if it does not (the default), StarBridge clears that sign-in after the read. StarBridge does not read or save your RSI password, and the sign-in is never saved to your account. The hangar read from RSI is saved to your account.
9. Online, it connects to StarBridge servers and SCM, downloads RSI avatars directly from the RSI website, visits the RSI website for hangar reading, visits sites you open in the menu browser, loads images from their own sources, and visits the update address when checking for updates.
10. When online access is allowed, it regularly sends usage statistics without account information to StarBridge servers (a client ID generated at random on this device, version, whether the overlay is on and usage time), and syncs game status according to your sharing settings.
11. Saves settings and records on this device. You can export data, move the data folder and turn on start with Windows (an entry for the current Windows user).
12. Shows alerts and plays sounds according to your notification settings, and checks for and installs StarBridge updates.

What it does not do

- It does not read or change the game process's memory.
- It does not inject code or DLLs into the game, and installs no keyboard or mouse hooks.
- It does not send keystrokes, mouse actions or chat to the game for you.
- It does not take screenshots on its own or run OCR text recognition.
- It does not change game logs or game settings, start or close the game or the RSI Launcher, or move, resize or pin the game window.

RSI notice

RSI says it may support add-ons and a public API in the future, but the current Alpha supports neither. In RSI's words, "Fan-created custom code projects are not endorsed or authorized by RSI"; you install and use them at your own risk. Using unauthorized tools may violate the RSI Terms of Service and may lead to action against your account, up to suspension or termination. If a website or app asks for your RSI login name or password, do not give it. StarBridge is also a fan-made tool, so this notice applies to it too.

Source: RSI Support, "Fandom FAQ - Videos, writing, and more"
https://support.robertsspaceindustries.com/hc/en-us/articles/115013196127-Fandom-FAQ-Videos-writing-and-more''';

const rsiToolNoticeEnUs = RsiToolNoticeCopy(
  'What StarBridge does and does not do',
  rsiToolNoticeEnUsBody,
  'Got it',
);

const rsiToolNoticeZhTwBody =
    '''以下是星海艦橋在你電腦上做的和不做的事。是否符合 RSI 條款由 CIG 判斷，我們無法代為判定，請你自行評估。

會做的事

1. 讀取你選擇的遊戲版本的 Game.log。辨識本機身分或匯入歷史遊玩時間時，也會讀取同目錄 logbackups 裡的舊日誌。唯讀，不修改。
2. 按鍵查看：只有開啟「按鍵查看」頁面、在頁面裡切換遊戲版本或語言，或點「重新讀取」時，才會讀取所選遊戲版本資料夾裡的 actionmaps.xml，用來顯示你的按鍵。官方版本還會讀取同一資料夾裡 data\\Localization 下所選語言的 global.ini（如果有），只取操作名稱；為了讓你選擇語言，還會列出這個資料夾下已安裝的語言。這些檔案都只在本機讀取，不寫入，不會修改按鍵或本地化檔案。
3. 查詢 Windows 程序清單，判斷遊戲是否在執行；以受限查詢權限開啟遊戲程序，只取程式路徑、啟動時間和是否已結束。
4. 用 Raw Input 接收你設定的快捷鍵，不攔截按鍵，遊戲照常收到。設定裡可以改用 Windows 系統快捷鍵$windowsSystemHotkeyApiCjk，預設關閉；開啟後，其他程式通常收不到這些組合鍵，但《星際公民》在前景時實測仍會收到。
5. 浮層、遊戲內選單、參考圖和提醒都是星海艦橋自己的獨立視窗。
6. 用快捷鍵（預設 Alt+M）開啟選單時，如果 Windows 拒絕切換焦點，會短暫把選單視窗的執行緒接入遊戲視窗的輸入佇列（$_menuFocusCall），切換後立即解除。
7. 你點擊截圖時，擷取選單所在顯示器的整個畫面，螢幕上其他可見視窗也會被擷取進去。截圖只儲存在本機或複製到剪貼簿，不會自動上傳。
8. 機庫讀取：在星海艦橋裡開啟 RSI 官方機庫網頁，由你自己在官方頁面登入 RSI；星海艦橋讀取頁面上顯示的 Handle 和艦船。讀取機庫時，你可以選擇是否在這台電腦上記住 RSI 登入；不記住的話（預設不記住），讀完後星橋會清除這次的登入狀態。星橋不會讀取或儲存你的 RSI 密碼，登入狀態也不會儲存到你的帳號。從 RSI 讀到的機庫會儲存到你的帳號。
9. 連線時會連接星海艦橋伺服器和 SCM；顯示 RSI 頭像時直接從 RSI 網站下載；機庫讀取存取 RSI 網站；選單裡的瀏覽器存取你開啟的網站；圖片從各自的來源位址載入；檢查更新時存取更新位址。
10. 允許連線時，會定時向星海艦橋伺服器傳送不含帳號資訊的使用統計（本機隨機產生的用戶端識別碼、版本、浮層是否開啟和使用時間）；依你的分享設定同步遊戲狀態。
11. 在本機儲存設定和紀錄；你可以匯出資料、更換資料位置、設定開機啟動（寫入目前 Windows 使用者的啟動項目）。
12. 依通知設定顯示提醒、播放聲音；檢查並安裝星海艦橋的更新。

不做的事

- 不讀取或修改遊戲程序的記憶體。
- 不向遊戲注入程式碼或 DLL，不安裝鍵盤或滑鼠掛鉤。
- 不替你向遊戲傳送按鍵、滑鼠操作或聊天內容。
- 不自動截圖，不做 OCR 文字辨識。
- 不修改遊戲日誌和遊戲設定，不啟動或關閉遊戲和 RSI Launcher，不改變遊戲視窗的位置、大小或置頂。

RSI 官方提示

RSI 表示，日後可能會支援外掛和公開介面，但目前的 Alpha 版本不支援外掛，也沒有公開介面。玩家自製的工具都沒有得到 RSI 的認可或授權，安裝和使用風險由你自己承擔。使用未經授權的工具可能違反 RSI 服務條款，並可能導致帳號被處理，最重可能被停權或註銷。如果有網站或應用程式向你索取 RSI 帳號的登入名稱或密碼，不要提供。星海艦橋也是玩家自製的工具，同樣適用這條提示。

出處：RSI 支援中心〈Fandom FAQ - Videos, writing, and more〉
https://support.robertsspaceindustries.com/hc/en-us/articles/115013196127-Fandom-FAQ-Videos-writing-and-more''';

const rsiToolNoticeZhTw = RsiToolNoticeCopy(
  '星海艦橋做什麼、不做什麼',
  rsiToolNoticeZhTwBody,
  '我已瞭解',
);

const rsiToolNoticeZhCnBody =
    '''下面是星海舰桥在你电脑上做的和不做的事。是否符合 RSI 条款由 CIG 判断，我们无法代为判定，请你自行评估。

会做的事

1. 读取你选择的游戏版本的 Game.log。识别本机身份或导入历史游玩时长时，也会读取同目录 logbackups 里的旧日志。只读，不修改。
2. 按键查看：只有打开“按键查看”页面、在页面里切换游戏版本或语言，或点“重新读取”时，才会读取所选游戏版本文件夹里的 actionmaps.xml，用来显示你的按键。官方版本还会读取同一文件夹里 data\\Localization 下所选语言的 global.ini（如果有），只取操作名称；为了让你选择语言，还会列出这个文件夹下已安装的语言。这些文件都只在本机读取，不写入，不会修改按键或本地化文件。
3. 查询 Windows 进程列表，判断游戏是否在运行；以受限查询权限打开游戏进程，只取程序路径、启动时间和是否已退出。
4. 用 Raw Input 接收你设置的快捷键，不拦截按键，游戏照常收到。设置里可以改用 Windows 系统热键$windowsSystemHotkeyApiCjk，默认关闭；开启后，其他程序通常收不到这些组合键，但《星际公民》在前台时实测仍会收到。
5. 浮层、游戏内菜单、参考图和提醒都是星海舰桥自己的独立窗口。
6. 用快捷键（默认 Alt+M）打开菜单时，如果 Windows 拒绝切换焦点，会短暂把菜单窗口的线程接入游戏窗口的输入队列（$_menuFocusCall），切换后立即解除。
7. 你点击截图时，截取菜单所在显示器的整个画面，屏幕上其他可见窗口也会被截进去。截图只保存在本机或复制到剪贴板，不会自动上传。
8. 机库读取：在星海舰桥里打开 RSI 官方机库网页，由你自己在官方页面登录 RSI；星海舰桥读取页面上显示的 Handle 和舰船。读取机库时，你可以选择是否在这台电脑上记住 RSI 登录；不记住的话（默认不记住），读完后星桥会清除这次的登录状态。星桥不会读取或保存你的 RSI 密码，登录状态也不会保存到你的账号。从 RSI 读到的机库会保存到你的账号。
9. 联网时会连接星海舰桥服务器和 SCM；显示 RSI 头像时直接从 RSI 网站下载；机库读取访问 RSI 网站；菜单里的浏览器访问你打开的网站；图片从各自的来源地址加载；检查更新时访问更新地址。
10. 允许联网时，会定时向星海舰桥服务器发送不含账号信息的使用统计（本机随机生成的客户端标识、版本、浮层是否开启和使用时长）；按你的分享设置同步游戏状态。
11. 在本机保存设置和记录；你可以导出数据、更换数据位置、设置开机启动（写入当前 Windows 用户的启动项）。
12. 按通知设置显示提醒、播放声音；检查并安装星海舰桥的更新。

不做的事

- 不读取或修改游戏进程的内存。
- 不向游戏注入代码或 DLL，不安装键盘或鼠标钩子。
- 不替你向游戏发送按键、鼠标操作或聊天内容。
- 不自动截图，不做 OCR 文字识别。
- 不修改游戏日志和游戏配置，不启动或关闭游戏和 RSI Launcher，不改变游戏窗口的位置、大小或置顶。

RSI 官方提示

RSI 表示，以后可能会支持插件和公开接口，但目前的 Alpha 版本不支持插件，也没有公开接口。玩家自制的工具都没有得到 RSI 的认可或授权，安装和使用风险由你自己承担。使用未经授权的工具可能违反 RSI 服务条款，并可能导致账号被处理，最重可能被封停或注销。如果有网站或应用向你索要 RSI 账号的登录名或密码，不要提供。星海舰桥也是玩家自制的工具，同样适用这条提示。

出处：RSI 支持中心《Fandom FAQ - Videos, writing, and more》
https://support.robertsspaceindustries.com/hc/en-us/articles/115013196127-Fandom-FAQ-Videos-writing-and-more''';

const rsiToolNoticeZhCn = RsiToolNoticeCopy(
  '星海舰桥做什么、不做什么',
  rsiToolNoticeZhCnBody,
  '我已了解',
);
