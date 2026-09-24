const helpSupportZhCn = <String, String>{
  'help.scm.openFailed': '未能打开浏览器，可手动访问 scm.flowcld.com。',
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
  'help.log.catalog': '8 类说明',
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
      '• 明确区域事件优先；仅有抵达信号时，近期有效目标最多作为“未确认”结果。\n'
      '• 抵达前后 15 秒内取得的明确地点不会被迟到的量子日志覆盖。\n'
      '• 中途取消、任务点或信标信息不足时，会保留最近可靠地点或显示待确认。\n'
      '• 未收录地点保留可识别代码，不会自动上传地点代码。',
  'help.log.health.title': '倒地、死亡、救起与重生',
  'help.log.health.body':
      '• 倒地、死亡、救起和重生使用连续事件确认，避免把加载或网络波动误判。\n'
      '• 死亡需要近期倒地作为前置；普通解绑不会被单独计为死亡。\n'
      '• 救起需要恢复后的活动，重生需要新的绑定和后续恢复事件共同确认。\n'
      '• 重复事件会合并；是否对外显示由你的事件共享设置决定。\n'
      '• 游玩时长只有在允许记录后才会在本机累计。',
  'help.log.records.title': '记录、同步、隐私与历史导入',
  'help.log.records.body':
      '• 日志识别、本地留存、账号同步和公开展示是四个独立环节。\n'
      '• 本地事件日志只保存整理后的摘要、时间和分类，不复制完整 Game.log。\n'
      '• 只有登录、身份匹配且共享开关允许时，才会发送即时协作状态。\n'
      '• 低可信度位置可限制为仅在本机显示；关闭事件共享不会停止本机识别。\n'
      '• 历史时长只导入 LIVE 游玩记录，需由你确认；重置时长后可重新导入一次。',
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
  'help.legal.safety.body': '星海舰桥只读取你选择的 Game.log，不会进入或修改游戏进程、内存或文件，也不会替玩家完成游戏操作。游戏更新、日志不完整或网络波动可能造成延迟和识别错误；重要信息请以游戏客户端和官方服务为准。',
  'help.legal.unofficial.title': '非官方说明',
  'help.legal.unofficial.body': '星海舰桥是玩家独立开发的非官方社区工具，与 Cloud Imperium 集团及其关联公司不存在隶属、合作、授权、赞助或认可关系。相关名称、商标、标志、图像、舰船设计和游戏素材的权利归其各自权利人所有。',
  'help.legal.use.title': '使用须知',
  'help.legal.use.body': '应用可能因游戏更新、网络波动或兼容性问题出现中断、延迟或识别错误。请遵守游戏、平台和所在社区的规则，不得用于违法、侵权、骚扰、作弊或干扰他人正常使用的行为。',
  'help.legal.licenses.title': '开源软件许可',
  'help.legal.licenses.body': '浏览当前客户端包含的 Flutter、依赖包和内置字体许可。显示内容来自本次安装包，不会联网。',
  'help.legal.licenses.open': '查看开源软件许可',
  'help.legal.licenses.legalese': '各项目仍由其原始许可条款约束。',
  'help.version.title': '应用更新',
  'help.version.description': '在这里查看版本状态并检查安装器与完整安装包更新。',
  'help.version.status.title': '版本状态',
  'help.version.status.unavailable': '暂时无法读取版本与更新状态。请通过当前安装来源获取新版本。',
  'help.version.check': '检查更新',
  'help.version.notice': '更新期间应用可能暂时锁定，完成后可能自动关闭并重新启动。',
  'help.feedback.title': '反馈与建议',
  'help.feedback.description': '遇到了问题、有改进建议，或希望添加新功能，都可以告诉我们。',
  'help.feedback.inApp.title': '应用内反馈',
  'help.feedback.inApp.unavailable': '应用内反馈暂时不可用，你可以先通过 QQ 反馈群联系我们。',
  'help.feedback.group.title': 'QQ 反馈群',
  'help.feedback.group.body': '用于问题交流、使用建议和版本反馈。群内信息依照 QQ 平台及群管理规则处理。',
  'help.feedback.group.number': '群号：534268220',
  'help.feedback.group.copy': '复制群号',
  'help.feedback.group.copied': '反馈群号已复制。',
};

const helpSupportZhTw = <String, String>{
  'help.scm.openFailed': '未能開啟瀏覽器，可手動前往 scm.flowcld.com。',
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
  'help.log.catalog': '8 類說明',
  'help.log.session.title': '日誌讀取與遊戲工作階段',
  'help.log.session.body': '• 讀取你在「帳號與識別」中選定遊戲版本的 Game.log。\n• 啟動時只讀取末尾的近期內容來恢復狀態，不會把舊事件當作剛剛發生。\n• 遊戲執行中只處理檔案末尾新增的完整行；普通偵錯資訊和未知內容會被忽略。\n• 日誌被清空或重新產生後會從新檔案開頭繼續讀取，暫時缺失時會等待檔案恢復。\n• 遊戲啟動與退出由本機程序確認；相隔超過 30 秒的未知時段不會補記為遊玩時間。',
  'help.log.identity.title': '身分辨識、帳號綁定與線上狀態',
  'help.log.identity.body': '• 遊戲身分來自 Game.log，帳號身分來自目前登入的舊帳號或 SCM 帳號，兩者會在同步前分別核對。\n• 首次辨識的遊戲 ID 需要與目前帳號綁定；不一致時停止帳號同步，避免資料串號。\n• 切換帳號後只讀取新帳號自己的資料、好友、艦隊、房間和本機記錄。\n• 「應用程式線上」和「遊戲中」是兩種狀態；僅開啟應用程式不會被顯示為遊戲線上。\n• 手動離線或隱身不會被 Game.log 覆蓋，隱身時對外按離線處理。',
  'help.log.server.title': '伺服器與分線辨識',
  'help.log.server.body': '• 進入 PU 或分線更新後，應用程式會辨識目前伺服器區域和分線。\n• 主動中斷、遠端中斷或返回主選單後會清除舊伺服器資訊。\n• 應用程式啟動時僅在確認遊戲仍執行後回掃最近一次進入或離開記錄。\n• 同服人數與進出伺服器提醒只會使用雙方允許分享的資訊。',
  'help.log.ship.title': '艦船辨識與狀態保留',
  'help.log.ship.body': '• 加入艦船頻道是最可靠的進入訊號；明確離開頻道後才清除多座艦船。\n• 取得駕駛控制屬於強訊號，開啟星圖或設定路線只作為輔助辨識。\n• 對允許在內部活動的艦船，離開駕駛位不會直接被當作下船。\n• 進入明確地面區域、離線或出現新的可靠艦船訊號會結束舊狀態。\n• 艦船名稱優先使用已驗證中文對照，未知型號保留可辨識原名，不會猜測。',
  'help.log.location.title': '地點、導航與量子航行',
  'help.log.location.body': '• 目前位置、導航目標和量子抵達是三種獨立資訊，設定目標不會直接改變目前位置。\n• 明確區域事件優先；僅有抵達訊號時，近期有效目標最多作為「未確認」結果。\n• 抵達前後 15 秒內取得的明確地點不會被遲到的量子日誌覆蓋。\n• 中途取消、任務點或信標資訊不足時，會保留最近可靠地點或顯示待確認。\n• 未收錄地點保留可辨識代碼，不會自動上傳地點代碼。',
  'help.log.health.title': '倒地、死亡、救起與重生',
  'help.log.health.body': '• 倒地、死亡、救起和重生使用連續事件確認，避免把載入或網路波動誤判。\n• 死亡需要近期倒地作為前置；普通解除綁定不會被單獨計為死亡。\n• 救起需要恢復後的活動，重生需要新的綁定和後續恢復事件共同確認。\n• 重複事件會合併；是否對外顯示由你的事件分享設定決定。\n• 遊玩時間只有在允許記錄後才會在本機累計。',
  'help.log.records.title': '記錄、同步、隱私與歷史匯入',
  'help.log.records.body': '• 日誌辨識、本機留存、帳號同步和公開展示是四個獨立環節。\n• 本機事件日誌只儲存整理後的摘要、時間和分類，不複製完整 Game.log。\n• 只有登入、身分符合且分享開關允許時，才會傳送即時協作狀態。\n• 低可信度位置可限制為僅在本機顯示；關閉事件分享不會停止本機辨識。\n• 歷史時長只匯入 LIVE 遊玩記錄，需由你確認；重設時長後可重新匯入一次。',
  'help.log.confidence.title': '進階：艦船與地點可信度',
  'help.log.confidence.body': '• 可信度用於處理同時出現的矛盾日誌，不是玩家評分，也不影響遊玩時間。\n• 80–100 為高、45–79 為中、15–44 為低，低於 15 視為未知。\n• 艦船頻道與明確地點屬於強證據；導航內容、路線和抵達屬於輔助證據。\n• 證據會隨時間降低可信度，新證據只在符合目前工作階段時更新結果。\n• 離線後僅以低可信度恢復最後已知值，等待新的遊戲日誌確認。',
  'help.legal.title': '隱私與使用說明',
  'help.legal.description': '查看星海艦橋如何使用資訊，以及使用時需要瞭解的事項。',
  'help.legal.operation.title': '星海艦橋如何運作',
  'help.legal.operation.body': '星海艦橋幫助你管理艦隊與房間、查看成員狀態、艦船和地點資訊，並透過遊戲浮層提供協作資訊。這些內容用於玩家之間的組織和溝通，不屬於遊戲官方資料。選擇 Game.log 後，應用程式會在本機辨識相關狀態；登入後，僅有必要且獲准的資訊會用於協作同步。',
  'help.legal.data.title': '你的資料與隱私',
  'help.legal.data.body': '應用程式會在這台裝置上儲存設定、登入狀態、日誌路徑、浮層配置和必要快取。遊玩時間只有在你允許後才會記錄。提交回饋時請勿填寫密碼、驗證碼、復原碼、付款資訊或其他敏感內容。',
  'help.legal.safety.title': '遊戲安全與資訊準確性',
  'help.legal.safety.body': '星海艦橋只讀取你選擇的 Game.log，不會進入或修改遊戲程序、記憶體或檔案，也不會替玩家完成遊戲操作。遊戲更新、日誌不完整或網路波動可能造成延遲和辨識錯誤；重要資訊請以遊戲客戶端和官方服務為準。',
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
  'help.version.description': '在這裡查看版本狀態並檢查安裝程式與完整安裝包更新。',
  'help.version.status.title': '版本狀態',
  'help.version.status.unavailable': '暫時無法讀取版本與更新狀態。請透過目前安裝來源取得新版本。',
  'help.version.check': '檢查更新',
  'help.version.notice': '更新期間應用程式可能暫時鎖定，完成後可能自動關閉並重新啟動。',
  'help.feedback.title': '回饋與建議',
  'help.feedback.description': '遇到了問題、有改進建議，或希望新增功能，都可以告訴我們。',
  'help.feedback.inApp.title': '應用程式內回饋',
  'help.feedback.inApp.unavailable': '應用程式內回饋暫時無法使用，你可以先透過 QQ 回饋群聯絡我們。',
  'help.feedback.group.title': 'QQ 回饋群',
  'help.feedback.group.body': '用於問題交流、使用建議和版本回饋。群內資訊依照 QQ 平台及群管理規則處理。',
  'help.feedback.group.number': '群號：534268220',
  'help.feedback.group.copy': '複製群號',
  'help.feedback.group.copied': '回饋群號已複製。',
};

const helpSupportEnUs = <String, String>{
  'help.scm.openFailed': 'Could not open your browser. Visit scm.flowcld.com manually.',
  'help.title': 'Help & support',
  'help.description': 'Learn how game detection works, review privacy and usage notes, and find update or feedback options.',
  'help.topic.log': 'Game log detection',
  'help.topic.log.description': 'Game.log, identity, ships, and location',
  'help.topic.legal': 'Notices & terms',
  'help.topic.legal.description': 'Data, game safety, and asset notices',
  'help.topic.version': 'Updates & version',
  'help.topic.version.description': 'Version status and update options',
  'help.topic.feedback': 'Feedback & suggestions',
  'help.topic.feedback.description': 'Report problems, suggest improvements, or request features',
  'help.log.title': 'Game log detection',
  'help.log.description': 'See how in-game activity becomes app status and what to do when information has not updated.',
  'help.log.scope.title': 'Only the Game.log you select is read',
  'help.log.scope.body': 'StarBridge does not read game memory, inject into the game, or modify game files. Status changes only when the log contains new, valid information. Otherwise, the latest reliable result is kept.',
  'help.log.troubleshoot.title': 'When information does not update',
  'help.log.troubleshoot.body': 'Check the Game.log path and its last modified time. If your ship is missing, press F2 while aboard to open the star map. After leaving a ship, wait for the leave-channel event. If the issue continues, open Diagnostics & maintenance.',
  'help.log.catalog': '8 topics',
  'help.log.session.title': 'Log reading and game sessions',
  'help.log.session.body': '• Reads Game.log for the game version selected in Account and identity.\n• Startup reads only recent lines near the end to restore state; old entries are not treated as new events.\n• While the game runs, only newly appended complete lines are processed; debug and unknown content is ignored.\n• If the log is replaced or truncated, reading resumes from the new file. Temporary absence is tolerated.\n• Game start and exit come from the local process; unknown sampling gaps over 30 seconds are not counted as play time.',
  'help.log.identity.title': 'Identity, account binding, and presence',
  'help.log.identity.body': '• Game identity comes from Game.log and account identity comes from your signed-in legacy or SCM account; both are checked before sync.\n• A newly detected game ID must match the current account. A mismatch stops account sync to prevent cross-account data.\n• Switching accounts loads only that account’s profile, friends, fleet, rooms, and local records.\n• “App online” and “in game” are separate states; opening the app alone does not make you game-online.\n• Manual offline and invisible modes are privacy choices and are not overridden by Game.log.',
  'help.log.server.title': 'Server and shard detection',
  'help.log.server.body': '• Entering the PU or receiving a shard update identifies the current server region and shard.\n• Disconnecting or returning to the main menu clears old server details.\n• Startup scans recent server entries only after confirming that the game is still running.\n• Same-server counts and join or leave alerts use only information both players allow to be shared.',
  'help.log.ship.title': 'Ship detection and retained state',
  'help.log.ship.body': '• Joining a vehicle channel is the strongest boarding signal; multi-crew ships clear after an explicit leave event.\n• Taking control is strong evidence, while opening the star map or planning a route is supporting evidence.\n• Leaving the pilot seat does not mean leaving a ship that supports interior movement.\n• A confirmed ground area, going offline, or stronger evidence for another ship ends the old state.\n• Verified Chinese names are preferred; unknown models keep a recognizable original name and are never guessed.',
  'help.log.location.title': 'Location, navigation, and quantum travel',
  'help.log.location.body': '• Current location, navigation target, and quantum arrival are separate facts. Choosing a target does not move your location.\n• Confirmed area events take priority. A recent target may be shown only as unconfirmed when arrival evidence is incomplete.\n• A confirmed location within 15 seconds of arrival is protected from late quantum log entries.\n• Cancelled travel, mission points, and incomplete beacon data keep the latest reliable location or show a pending result.\n• Unknown location codes remain local and are not uploaded automatically.',
  'help.log.health.title': 'Incapacitation, death, rescue, and respawn',
  'help.log.health.body': '• Related events are combined so loading and network interruptions are not mistaken for player state.\n• Death requires a recent incapacitation; an ordinary unbind does not count by itself.\n• Rescue requires activity after recovery, while respawn requires a new bind followed by recovery activity.\n• Duplicate events are merged. External visibility follows your event-sharing choices.\n• Play time is recorded locally only after you allow it.',
  'help.log.records.title': 'Records, sync, privacy, and history import',
  'help.log.records.body': '• Detection, local retention, account sync, and public visibility are four separate stages.\n• The local event log stores normalized summaries, time, and category—not a copy of the full Game.log.\n• Live collaboration status is sent only while signed in, identity-matched, and allowed by your sharing choices.\n• Low-confidence locations can stay local. Disabling event sharing does not stop local detection.\n• Only LIVE historical play time is imported, after your confirmation. Resetting play time restores one import opportunity.',
  'help.log.confidence.title': 'Advanced: ship and location confidence',
  'help.log.confidence.body': '• Confidence resolves conflicting log evidence. It is not a player rating and does not affect play time.\n• 80–100 is high, 45–79 medium, 15–44 low, and below 15 unknown.\n• Vehicle channels and confirmed areas are strong evidence; navigation context, routes, and arrivals are supporting evidence.\n• Evidence decays over time, and new evidence updates the result only when it belongs to the current session.\n• After reconnecting, last-known values return only at low confidence until fresh game evidence confirms them.',
  'help.legal.title': 'Privacy and usage notes',
  'help.legal.description': 'Review how StarBridge uses information and what you should know while using it.',
  'help.legal.operation.title': 'How StarBridge works',
  'help.legal.operation.body': 'StarBridge helps players coordinate fleets and rooms, view member, ship, and location status, and use an in-game overlay. This is community coordination information, not official game data. After you select Game.log, relevant state is detected locally; after sign-in, only necessary and permitted information is used for collaboration sync.',
  'help.legal.data.title': 'Your data and privacy',
  'help.legal.data.body': 'The app stores settings, sign-in state, selected log paths, overlay layouts, and required caches on this device. Play time is recorded only after you allow it. Never include passwords, verification or recovery codes, payment details, or other sensitive information in feedback.',
  'help.legal.safety.title': 'Game safety and accuracy',
  'help.legal.safety.body': 'StarBridge only reads the Game.log you select. It does not enter or modify the game process, memory, or files, and it does not perform gameplay for you. Game updates, incomplete logs, and network changes may cause delays or errors. Confirm important information in the game and official services.',
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
  'help.version.description': 'View version status and check for installer or full-package updates here.',
  'help.version.status.title': 'Version status',
  'help.version.status.unavailable': 'Version and update status is temporarily unavailable. Use your current installation source to get a newer version.',
  'help.version.check': 'Check for updates',
  'help.version.notice': 'The app may be briefly locked during an update and may close and restart when it finishes.',
  'help.feedback.title': 'Feedback & suggestions',
  'help.feedback.description': 'Tell us about a problem, an improvement you would like, or a new feature you need.',
  'help.feedback.inApp.title': 'In-app feedback',
  'help.feedback.inApp.unavailable': 'In-app feedback is temporarily unavailable. You can contact us through the QQ feedback group.',
  'help.feedback.group.title': 'QQ feedback group',
  'help.feedback.group.body': 'Use the group for troubleshooting, suggestions, and release feedback. Messages and profiles follow QQ and group moderation rules.',
  'help.feedback.group.number': 'Group: 534268220',
  'help.feedback.group.copy': 'Copy group number',
  'help.feedback.group.copied': 'Feedback group number copied.',
};
