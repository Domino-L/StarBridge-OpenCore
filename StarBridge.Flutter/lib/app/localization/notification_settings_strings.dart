const simplifiedNotificationSettingsStrings = <String, String>{
  'settings.notification.activationUnavailable':
      '暂时无法打开这条提醒。可从通知页刷新查看；未读状态未改变。',
  'settings.notification.desktopReason.disabled': 'Windows 桌面提醒已关闭，请先开启后再测试。',
  'settings.notification.desktopReason.throttled': '测试过于频繁，请稍等两秒再试。',
  'settings.notification.desktopReason.doNotDisturb':
      'Windows 免打扰已开启。关闭免打扰后可重试。',
  'settings.notification.desktopReason.fullScreen': '当前处于全屏或演示状态。退出后可重试。',
  'settings.notification.desktopReason.systemBusy': 'Windows 当前暂停接收提醒，请稍后重试。',
  'settings.notification.desktopReason.inactiveDesktop':
      '当前桌面不可交互。解锁并返回桌面后可重试。',
  'settings.notification.desktopReason.quietTime': 'Windows 当前处于系统安静时段，请稍后重试。',
  'settings.notification.desktopReason.unsupported':
      '此 Windows 版本不支持所需通知能力。请更新 Windows 后重试。',
  'settings.notification.desktopReason.gameActiveOrUnknown':
      '游戏正在运行或状态尚未确认，暂不弹出桌面提醒。退出游戏后可重试。',
  'settings.notification.desktopReason.appActiveOrUnknown':
      '应用正在前台或前台状态尚未确认，暂不弹出桌面提醒。',
  'settings.notification.desktopReason.queueFull': '提醒队列已满，收起部分提醒后可重试。',
  'settings.notification.desktopReason.expired': '这次提醒已失效，请重新测试。',
  'settings.notification.desktopReason.unavailable': '暂时无法显示桌面提醒，请稍后重试。',
  'settings.notification.local.testTitle': '测试通知',
  'settings.notification.preview.example': '显示示例（不会发送）',
  'settings.notification.local.previewTitle': '弹出提醒显示多少内容',
  'settings.notification.local.position': '弹出位置（应用内与桌面）',
  'settings.notification.local.preview.fullContent':
      '显示新邀请和加入申请的数量，不展示聊天正文或个人资料。',
  'settings.notification.local.preview.sourceOnly': '只显示房间提醒，不显示数量。',
  'settings.notification.local.preview.hiddenDetails': '只显示有新通知，不显示来源或数量。',
  'settings.notification.local.description': '这些设置保存在本机，保存后生效。',
  'settings.notification.local.enabled': '显示应用内弹出提醒',
  'settings.notification.local.enabledDescription':
      '使用客户端时，提示新的房间邀请和加入申请。关闭后，未读气泡仍会保留。',
  'settings.notification.local.pending': '私信桌面通知、来源规则和游玩提醒仍在接入中。',
  'settings.notification.local.overlayDescription':
      '游戏在前台且浮层公告已开启时，提醒新的房间邀请和加入申请。不会自动打开浮层。',
  'settings.notification.local.windowsDescription':
      '后台显示已开启的桌面提醒；游戏、全屏或系统免打扰时保持安静。',
  'settings.notification.local.desktopTest': '测试 Windows 通知',
  'settings.notification.local.desktopTestBody': '这是一条桌面测试通知。点击可打开星海舰桥。',
  'settings.notification.local.desktopSubmitted': '已提交桌面提醒卡。关闭提醒不会标记已读。',
  'settings.notification.local.desktopFailed':
      '暂未显示提醒。请检查系统免打扰、游戏或全屏状态；旧版 Windows 可能不支持。',
  'settings.notification.local.genericTitle': '新通知',
  'settings.notification.local.roomTitle': '房间提醒',
  'settings.notification.local.hiddenBody': '你有新的通知，请打开通知页查看。',
  'settings.notification.local.sourceBody': '有新的房间消息，请前往房间查看。',
  'settings.notification.local.fullBody':
      '收到 {invitations} 个新邀请、{applications} 个新加入申请，请前往房间处理。',
  'settings.notification.title': '通知与提醒',
  'settings.notification.description': '选择接收提醒的方式、内容和来源。',
  'settings.notification.scope.device': '当前设备',
  'settings.notification.scope.account': '账号同步',
  'settings.notification.loading': '正在读取通知设置…',
  'settings.notification.retry': '重新读取',
  'settings.notification.signedOut.title': '登录后管理通知',
  'settings.notification.signedOut.body': '来源规则与外部内容预览属于账号设置；登录后才能读取和修改。',
  'settings.notification.unavailable.title': '暂时无法读取通知设置',
  'settings.notification.error.hostUnavailable': '通知服务暂时不可用，请稍后重试。',
  'settings.notification.error.readFailed': '暂时无法读取通知设置，请重试。',
  'settings.notification.error.writeFailed': '更改未保存，页面已保留最后一次确认的设置。',
  'settings.notification.error.writeConflict': '设置已更新，请重新读取后再修改。',
  'settings.notification.error.invalidResponse': '通知设置出现异常，请重新读取。',
  'settings.notification.error.unavailable': '通知设置当前不可用，请检查连接后重试。',
  'settings.notification.channels.title': '当前设备的提醒渠道',
  'settings.notification.channels.description': '选择这台电脑如何提醒你。',
  'settings.notification.channels.history.title': '应用内通知记录',
  'settings.notification.channels.history.description': '重要通知和待处理事项会保留在通知中心。',
  'settings.notification.channels.history.required': '自动保留',
  'settings.notification.channels.windows.title': 'Windows 桌面提醒',
  'settings.notification.channels.windows.description':
      '在桌面显示 StarBridge 通知，默认位于右下角。',
  'settings.notification.channels.directMessage.title': '私信使用 Windows 提醒',
  'settings.notification.channels.directMessage.description':
      '桌面提醒开启后，在后台收到新私信时显示提醒；开启前的消息不会补弹。',
  'settings.notification.channels.directMessage.defaultOff': '默认关闭',
  'settings.notification.channels.overlay.title': '游戏内浮层主动提醒',
  'settings.notification.channels.overlay.description': '游戏中显示邀请、提及和与你有关的重要提醒。',
  'settings.notification.channels.sound.title': '简短提示音',
  'settings.notification.channels.sound.description':
      '只为直接私信、邀请与本人相关的重要事件播放一次。',
  'settings.notification.channels.sound.pendingDescription': '声音提醒将在后续版本提供。',
  'settings.notification.channels.sound.pending': '暂不可用',
  'settings.notification.channels.position.label': '桌面提醒位置',
  'settings.notification.channels.position.description': '选择通知出现的位置。',
  'settings.notification.test.action': '测试应用内提醒',
  'settings.notification.test.title': 'StarBridge 通知',
  'settings.notification.test.body': '测试通知已显示',
  'settings.notification.position.topLeft': '左上角',
  'settings.notification.position.bottomLeft': '左下角',
  'settings.notification.position.topRight': '右上角',
  'settings.notification.position.bottomRight': '右下角（默认）',
  'settings.notification.preview.title': '外部提醒显示多少内容',
  'settings.notification.preview.description': '控制通知弹出时显示多少内容。',
  'settings.notification.preview.full.title': '显示完整内容',
  'settings.notification.preview.full.description': '显示允许公开的发送者、来源与一行正文。',
  'settings.notification.preview.source.title': '仅显示来源',
  'settings.notification.preview.source.description': '只显示产品来源、房间或事件类型，不显示正文。',
  'settings.notification.preview.hidden.title': '隐藏所有详情',
  'settings.notification.preview.hidden.description': '外部只显示“StarBridge 有新提醒”。',
  'settings.notification.sources.title': '按舰队、组织、房间和行动分别管理',
  'settings.notification.sources.description': '为每个来源选择不同的提醒方式。',
  'settings.notification.sources.count': '{count} 个来源',
  'settings.notification.sources.mode': '提醒模式',
  'settings.notification.sources.noGlobalDnd': '可在每个舰队、组织、房间或行动中单独设置免打扰。',
  'settings.notification.sources.empty.title': '当前没有可管理的来源',
  'settings.notification.sources.empty.description':
      '加入 RSI 官网舰队、社区组织、房间或行动后，对应来源会出现在这里。',
  'settings.notification.sourceKind.officialFleet': 'RSI 官网舰队',
  'settings.notification.sourceKind.community': '社区组织',
  'settings.notification.sourceKind.room': '房间',
  'settings.notification.sourceKind.friends': '好友',
  'settings.notification.sourceKind.directMessages': '私信',
  'settings.notification.sourceKind.operation': '行动',
  'settings.notification.mode.normal': '正常提醒',
  'settings.notification.mode.important': '仅关键变化',
  'settings.notification.mode.doNotDisturb': '免打扰',
  'settings.notification.activity.title': '玩家动态提醒',
  'settings.notification.activity.description': '选择需要提醒的玩家动态。',
  'settings.notification.activity.enabled.title': '启用玩家动态桌面提醒',
  'settings.notification.activity.enabled.description': '所选玩家状态变化时显示桌面通知，默认关闭。',
  'settings.notification.activity.audiences.title': '谁的动态需要提醒',
  'settings.notification.activity.audiences.description': '选择要关注的玩家。',
  'settings.notification.activity.audience.officialFleet': 'RSI 官网舰队成员',
  'settings.notification.activity.audience.friends': '好友',
  'settings.notification.activity.audience.room': '当前房间成员',
  'settings.notification.activity.events.title': '哪些变化需要提醒',
  'settings.notification.activity.events.description': '选择需要提醒的状态变化。',
  'settings.notification.activity.event.online': '玩家上线',
  'settings.notification.activity.event.offline': '玩家离线',
  'settings.notification.activity.event.gameStart': '开始游戏',
  'settings.notification.activity.event.gameStop': '结束游戏',
  'settings.notification.activity.behavior.title': '显示时机',
  'settings.notification.activity.behavior.description': '决定通知何时出现。',
  'settings.notification.activity.backgroundOnly.title':
      '仅在 StarBridge 位于后台时弹出',
  'settings.notification.activity.backgroundOnly.description':
      '正在查看 StarBridge 时不再重复弹出。',
  'settings.notification.activity.reduceInGame.title': '减少游戏中的桌面提醒',
  'settings.notification.activity.reduceInGame.description':
      '游戏中开启浮层时，暂停玩家动态弹窗。',
  'settings.notification.play.title': '连续游玩提醒',
  'settings.notification.play.description': '长时间游戏时提醒你休息和补水。',
  'settings.notification.play.enabled.title': '提醒我休息和补水',
  'settings.notification.play.enabled.description': '打开后按下面的时间间隔提醒。',
  'settings.notification.play.intervals.title': '提醒间隔',
  'settings.notification.play.first.title': '首次提醒',
  'settings.notification.play.first.description': '连续游玩多久后显示第一次提醒。',
  'settings.notification.play.repeat.title': '后续提醒',
  'settings.notification.play.repeat.description': '首次提醒后，按该间隔再次提醒。',
  'settings.notification.play.hours': '{count} 小时',
  'settings.notification.play.minutes': '{count} 分钟',
};

const traditionalNotificationSettingsStrings = <String, String>{
  'settings.notification.activationUnavailable':
      '暫時無法開啟這則提醒。可從通知頁重新整理查看；未讀狀態未改變。',
  'settings.notification.desktopReason.disabled': 'Windows 桌面提醒已關閉，請先開啟後再測試。',
  'settings.notification.desktopReason.throttled': '測試過於頻繁，請稍等兩秒再試。',
  'settings.notification.desktopReason.doNotDisturb': 'Windows 勿擾已開啟。關閉勿擾後可重試。',
  'settings.notification.desktopReason.fullScreen': '目前處於全螢幕或簡報狀態。退出後可重試。',
  'settings.notification.desktopReason.systemBusy': 'Windows 目前暫停接收提醒，請稍後重試。',
  'settings.notification.desktopReason.inactiveDesktop':
      '目前桌面無法互動。解鎖並返回桌面後可重試。',
  'settings.notification.desktopReason.quietTime': 'Windows 目前處於系統安靜時段，請稍後重試。',
  'settings.notification.desktopReason.unsupported':
      '此 Windows 版本不支援所需通知能力。請更新 Windows 後重試。',
  'settings.notification.desktopReason.gameActiveOrUnknown':
      '遊戲正在執行或狀態尚未確認，暫不彈出桌面提醒。退出遊戲後可重試。',
  'settings.notification.desktopReason.appActiveOrUnknown':
      '應用程式正在前景或前景狀態尚未確認，暫不彈出桌面提醒。',
  'settings.notification.desktopReason.queueFull': '提醒佇列已滿，收起部分提醒後可重試。',
  'settings.notification.desktopReason.expired': '這次提醒已失效，請重新測試。',
  'settings.notification.desktopReason.unavailable': '暫時無法顯示桌面提醒，請稍後重試。',
  'settings.notification.local.testTitle': '測試通知',
  'settings.notification.preview.example': '顯示範例（不會傳送）',
  'settings.notification.local.previewTitle': '彈出提醒顯示多少內容',
  'settings.notification.local.position': '彈出位置（應用內與桌面）',
  'settings.notification.local.preview.fullContent':
      '顯示新邀請和加入申請的數量，不展示聊天正文或個人資料。',
  'settings.notification.local.preview.sourceOnly': '只顯示房間提醒，不顯示數量。',
  'settings.notification.local.preview.hiddenDetails': '只顯示有新通知，不顯示來源或數量。',
  'settings.notification.local.description': '這些設定儲存在本機，儲存後生效。',
  'settings.notification.local.enabled': '顯示應用程式內彈出提醒',
  'settings.notification.local.enabledDescription':
      '使用用戶端時，提示新的房間邀請和加入申請。關閉後，未讀氣泡仍會保留。',
  'settings.notification.local.pending': '私訊桌面通知、來源規則和遊玩提醒仍在接入中。',
  'settings.notification.local.overlayDescription':
      '遊戲在前台且浮層公告已開啟時，提醒新的房間邀請和加入申請。不會自動開啟浮層。',
  'settings.notification.local.windowsDescription':
      '背景顯示已開啟的桌面提醒；遊戲、全螢幕或系統勿擾時保持安靜。',
  'settings.notification.local.desktopTest': '測試 Windows 通知',
  'settings.notification.local.desktopTestBody': '這是一則桌面測試通知。點擊可開啟星海艦橋。',
  'settings.notification.local.desktopSubmitted': '已提交桌面提醒卡。關閉提醒不會標記已讀。',
  'settings.notification.local.desktopFailed':
      '暫未顯示提醒。請檢查系統勿擾、遊戲或全螢幕狀態；舊版 Windows 可能不支援。',
  'settings.notification.local.genericTitle': '新通知',
  'settings.notification.local.roomTitle': '房間提醒',
  'settings.notification.local.hiddenBody': '你有新的通知，請開啟通知頁查看。',
  'settings.notification.local.sourceBody': '有新的房間訊息，請前往房間查看。',
  'settings.notification.local.fullBody':
      '收到 {invitations} 個新邀請、{applications} 個新加入申請，請前往房間處理。',
  'settings.notification.title': '通知與提醒',
  'settings.notification.description': '選擇接收提醒的方式、內容和來源。',
  'settings.notification.scope.device': '目前裝置',
  'settings.notification.scope.account': '帳號同步',
  'settings.notification.loading': '正在讀取通知設定…',
  'settings.notification.retry': '重新讀取',
  'settings.notification.signedOut.title': '登入後管理通知',
  'settings.notification.signedOut.body': '來源規則與外部內容預覽屬於帳號設定；登入後才能讀取和修改。',
  'settings.notification.unavailable.title': '暫時無法讀取通知設定',
  'settings.notification.error.hostUnavailable': '通知服務暫時不可用，請稍後再試。',
  'settings.notification.error.readFailed': '暫時無法讀取通知設定，請再試一次。',
  'settings.notification.error.writeFailed': '變更未儲存，頁面已保留最後一次確認的設定。',
  'settings.notification.error.writeConflict': '設定已更新，請重新讀取後再修改。',
  'settings.notification.error.invalidResponse': '通知設定出現異常，請重新讀取。',
  'settings.notification.error.unavailable': '通知設定目前不可用，請檢查連線後重試。',
  'settings.notification.channels.title': '目前裝置的提醒管道',
  'settings.notification.channels.description': '選擇這台電腦如何提醒你。',
  'settings.notification.channels.history.title': '應用程式內通知記錄',
  'settings.notification.channels.history.description': '重要通知和待處理事項會保留在通知中心。',
  'settings.notification.channels.history.required': '自動保留',
  'settings.notification.channels.windows.title': 'Windows 桌面提醒',
  'settings.notification.channels.windows.description':
      '在桌面顯示 StarBridge 通知，預設位於右下角。',
  'settings.notification.channels.directMessage.title': '私訊使用 Windows 提醒',
  'settings.notification.channels.directMessage.description':
      '桌面提醒開啟後，在背景收到新私訊時顯示提醒；開啟前的訊息不會補跳。',
  'settings.notification.channels.directMessage.defaultOff': '預設關閉',
  'settings.notification.channels.overlay.title': '遊戲內浮層主動提醒',
  'settings.notification.channels.overlay.description': '遊戲中顯示邀請、提及和與你有關的重要提醒。',
  'settings.notification.channels.sound.title': '簡短提示音',
  'settings.notification.channels.sound.description':
      '只為直接私訊、邀請與本人相關的重要事件播放一次。',
  'settings.notification.channels.sound.pendingDescription': '聲音提醒將在後續版本提供。',
  'settings.notification.channels.sound.pending': '暫不可用',
  'settings.notification.channels.position.label': '桌面提醒位置',
  'settings.notification.channels.position.description': '選擇通知出現的位置。',
  'settings.notification.test.action': '測試應用程式內提醒',
  'settings.notification.test.title': 'StarBridge 通知',
  'settings.notification.test.body': '測試通知已顯示',
  'settings.notification.position.topLeft': '左上角',
  'settings.notification.position.bottomLeft': '左下角',
  'settings.notification.position.topRight': '右上角',
  'settings.notification.position.bottomRight': '右下角（預設）',
  'settings.notification.preview.title': '外部提醒顯示多少內容',
  'settings.notification.preview.description': '控制通知彈出時顯示多少內容。',
  'settings.notification.preview.full.title': '顯示完整內容',
  'settings.notification.preview.full.description': '顯示允許公開的傳送者、來源與一行正文。',
  'settings.notification.preview.source.title': '僅顯示來源',
  'settings.notification.preview.source.description': '只顯示產品來源、房間或事件類型，不顯示正文。',
  'settings.notification.preview.hidden.title': '隱藏所有詳情',
  'settings.notification.preview.hidden.description': '外部只顯示「StarBridge 有新提醒」。',
  'settings.notification.sources.title': '按艦隊、組織、房間和行動分別管理',
  'settings.notification.sources.description': '為每個來源選擇不同的提醒方式。',
  'settings.notification.sources.count': '{count} 個來源',
  'settings.notification.sources.mode': '提醒模式',
  'settings.notification.sources.noGlobalDnd': '可在每個艦隊、組織、房間或行動中單獨設定勿擾。',
  'settings.notification.sources.empty.title': '目前沒有可管理的來源',
  'settings.notification.sources.empty.description':
      '加入 RSI 官網艦隊、社群組織、房間或行動後，對應來源會出現在這裡。',
  'settings.notification.sourceKind.officialFleet': 'RSI 官網艦隊',
  'settings.notification.sourceKind.community': '社群組織',
  'settings.notification.sourceKind.room': '房間',
  'settings.notification.sourceKind.friends': '好友',
  'settings.notification.sourceKind.directMessages': '私訊',
  'settings.notification.sourceKind.operation': '行動',
  'settings.notification.mode.normal': '正常提醒',
  'settings.notification.mode.important': '僅關鍵變化',
  'settings.notification.mode.doNotDisturb': '勿擾',
  'settings.notification.activity.title': '玩家動態提醒',
  'settings.notification.activity.description': '選擇需要提醒的玩家動態。',
  'settings.notification.activity.enabled.title': '啟用玩家動態桌面提醒',
  'settings.notification.activity.enabled.description': '所選玩家狀態變化時顯示桌面通知，預設關閉。',
  'settings.notification.activity.audiences.title': '誰的動態需要提醒',
  'settings.notification.activity.audiences.description': '選擇要關注的玩家。',
  'settings.notification.activity.audience.officialFleet': 'RSI 官網艦隊成員',
  'settings.notification.activity.audience.friends': '好友',
  'settings.notification.activity.audience.room': '目前房間成員',
  'settings.notification.activity.events.title': '哪些變化需要提醒',
  'settings.notification.activity.events.description': '選擇需要提醒的狀態變化。',
  'settings.notification.activity.event.online': '玩家上線',
  'settings.notification.activity.event.offline': '玩家離線',
  'settings.notification.activity.event.gameStart': '開始遊戲',
  'settings.notification.activity.event.gameStop': '結束遊戲',
  'settings.notification.activity.behavior.title': '顯示時機',
  'settings.notification.activity.behavior.description': '決定通知何時出現。',
  'settings.notification.activity.backgroundOnly.title':
      '僅在 StarBridge 位於背景時彈出',
  'settings.notification.activity.backgroundOnly.description':
      '正在查看 StarBridge 時不再重複彈出。',
  'settings.notification.activity.reduceInGame.title': '減少遊戲中的桌面提醒',
  'settings.notification.activity.reduceInGame.description':
      '遊戲中開啟浮層時，暫停玩家動態彈窗。',
  'settings.notification.play.title': '連續遊玩提醒',
  'settings.notification.play.description': '長時間遊戲時提醒你休息和補充水分。',
  'settings.notification.play.enabled.title': '提醒我休息和補水',
  'settings.notification.play.enabled.description': '開啟後按下面的時間間隔提醒。',
  'settings.notification.play.intervals.title': '提醒間隔',
  'settings.notification.play.first.title': '首次提醒',
  'settings.notification.play.first.description': '連續遊玩多久後顯示第一次提醒。',
  'settings.notification.play.repeat.title': '後續提醒',
  'settings.notification.play.repeat.description': '首次提醒後，按該間隔再次提醒。',
  'settings.notification.play.hours': '{count} 小時',
  'settings.notification.play.minutes': '{count} 分鐘',
};

const englishNotificationSettingsStrings = <String, String>{
  'settings.notification.activationUnavailable': 'This reminder could not be opened. Refresh the Notifications page to check it. Unread status is unchanged.',
  'settings.notification.desktopReason.disabled':
      'Windows desktop reminders are off. Enable them before testing.',
  'settings.notification.desktopReason.throttled':
      'Please wait two seconds before testing again.',
  'settings.notification.desktopReason.doNotDisturb':
      'Windows Do Not Disturb is on. Turn it off to test again.',
  'settings.notification.desktopReason.fullScreen':
      'A full-screen app or presentation is active. Exit it to test again.',
  'settings.notification.desktopReason.systemBusy':
      'Windows is currently suppressing reminders. Try again later.',
  'settings.notification.desktopReason.inactiveDesktop':
      'The desktop is not interactive. Unlock and return to it to test again.',
  'settings.notification.desktopReason.quietTime':
      'Windows is in its quiet period. Try again later.',
  'settings.notification.desktopReason.unsupported': 'This Windows version lacks the required notification support. Update Windows and retry.',
  'settings.notification.desktopReason.gameActiveOrUnknown': 'The game is running or its state is not confirmed. Close the game to test again.',
  'settings.notification.desktopReason.appActiveOrUnknown': 'The app is in the foreground or its foreground state is not confirmed. No desktop reminder was shown.',
  'settings.notification.desktopReason.queueFull':
      'The reminder queue is full. Dismiss some reminders and retry.',
  'settings.notification.desktopReason.expired':
      'This reminder has expired. Test again.',
  'settings.notification.desktopReason.unavailable':
      'Desktop reminders are temporarily unavailable. Try again later.',
  'settings.notification.local.testTitle': 'Test notification',
  'settings.notification.preview.example': 'Example (not sent)',
  'settings.notification.local.previewTitle': 'Pop-up notification content',
  'settings.notification.local.position':
      'Pop-up position (in-app and desktop)',
  'settings.notification.local.preview.fullContent': 'Show counts of new invitations and join requests, without chat text or personal information.',
  'settings.notification.local.preview.sourceOnly':
      'Show that this is a room notification, without counts.',
  'settings.notification.local.preview.hiddenDetails': 'Show only that there is a new notification, without its source or counts.',
  'settings.notification.local.description':
      'Stored on this device. Changes take effect after saving.',
  'settings.notification.local.enabled': 'Show in-app pop-up notifications',
  'settings.notification.local.enabledDescription': 'Show new room invitations and join requests while using the app. Turning this off keeps unread badges.',
  'settings.notification.local.pending': 'Direct-message desktop notifications, source rules and play reminders are still being connected.',
  'settings.notification.local.overlayDescription': 'Show new room invitations and join requests while the game is foreground and the overlay announcement is enabled. Does not open the overlay automatically.',
  'settings.notification.local.windowsDescription': 'Show enabled desktop alerts in the background. Stay quiet during games, full-screen apps and system Do Not Disturb.',
  'settings.notification.local.desktopTest': 'Test Windows notification',
  'settings.notification.local.desktopTestBody':
      'This is a desktop test notification. Click to open StarBridge.',
  'settings.notification.local.desktopSubmitted':
      'Desktop card submitted. Dismissing it does not mark anything as read.',
  'settings.notification.local.desktopFailed': 'Not shown. Check Do Not Disturb, games or full-screen apps. Older Windows versions may not support this feature.',
  'settings.notification.local.genericTitle': 'New notification',
  'settings.notification.local.roomTitle': 'Room notification',
  'settings.notification.local.hiddenBody':
      'You have new notifications. Open Notifications to view them.',
  'settings.notification.local.sourceBody':
      'There is new room activity. Open Rooms to view it.',
  'settings.notification.local.fullBody': 'New invitations: {invitations}. New join requests: {applications}. Open Rooms to respond.',
  'settings.notification.title': 'Notifications & alerts',
  'settings.notification.description':
      'Choose how, when, and where StarBridge alerts you.',
  'settings.notification.scope.device': 'This device',
  'settings.notification.scope.account': 'Account sync',
  'settings.notification.loading': 'Reading notification settings…',
  'settings.notification.retry': 'Read again',
  'settings.notification.signedOut.title': 'Sign in to manage notifications',
  'settings.notification.signedOut.body': 'Source rules and external preview privacy belong to your account and can be changed after sign-in.',
  'settings.notification.unavailable.title':
      'Notification settings are unavailable',
  'settings.notification.error.hostUnavailable':
      'Notification services are temporarily unavailable. Try again later.',
  'settings.notification.error.readFailed':
      'Notification settings could not be loaded. Try again.',
  'settings.notification.error.writeFailed':
      'The change was not saved. The last confirmed settings remain in place.',
  'settings.notification.error.writeConflict':
      'These settings changed. Read them again before making another change.',
  'settings.notification.error.invalidResponse': 'Something went wrong with your notification settings. Reload them to continue.',
  'settings.notification.error.unavailable': 'Notification settings are currently unavailable. Check the connection and try again.',
  'settings.notification.channels.title': 'Alert channels on this device',
  'settings.notification.channels.description':
      'Choose how this computer alerts you.',
  'settings.notification.channels.history.title': 'In-app notification history',
  'settings.notification.channels.history.description':
      'Important updates and pending items stay in the notification center.',
  'settings.notification.channels.history.required': 'Saved automatically',
  'settings.notification.channels.windows.title': 'Windows desktop alerts',
  'settings.notification.channels.windows.description':
      'Show StarBridge alerts on your desktop. Bottom right is the default.',
  'settings.notification.channels.directMessage.title':
      'Use Windows alerts for direct messages',
  'settings.notification.channels.directMessage.description': 'With desktop alerts enabled, show new direct messages in the background. Earlier messages will not trigger alerts.',
  'settings.notification.channels.directMessage.defaultOff': 'Off by default',
  'settings.notification.channels.overlay.title':
      'Proactive in-game overlay alerts',
  'settings.notification.channels.overlay.description':
      'Show invites, mentions, and important updates while you are in game.',
  'settings.notification.channels.sound.title': 'Short alert sound',
  'settings.notification.channels.sound.description': 'Play once for direct messages, invites, and important events that affect you.',
  'settings.notification.channels.sound.pendingDescription':
      'Sound alerts will be available in a later version.',
  'settings.notification.channels.sound.pending': 'Unavailable',
  'settings.notification.channels.position.label': 'Desktop alert position',
  'settings.notification.channels.position.description':
      'Choose where desktop alerts appear.',
  'settings.notification.test.action': 'Test in-app reminder',
  'settings.notification.test.title': 'StarBridge notification',
  'settings.notification.test.body':
      'The test notification appeared successfully',
  'settings.notification.position.topLeft': 'Top left',
  'settings.notification.position.bottomLeft': 'Bottom left',
  'settings.notification.position.topRight': 'Top right',
  'settings.notification.position.bottomRight': 'Bottom right (default)',
  'settings.notification.preview.title': 'How much external alerts reveal',
  'settings.notification.preview.description':
      'Choose how much content appears in pop-up alerts.',
  'settings.notification.preview.full.title': 'Show full content',
  'settings.notification.preview.full.description':
      'Show the permitted sender, source, and one line of content.',
  'settings.notification.preview.source.title': 'Show source only',
  'settings.notification.preview.source.description':
      'Show the product source, room, or event type without message content.',
  'settings.notification.preview.hidden.title': 'Hide all details',
  'settings.notification.preview.hidden.description':
      'External alerts only say that StarBridge has a new update.',
  'settings.notification.sources.title':
      'Manage fleets, communities, rooms, and operations separately',
  'settings.notification.sources.description':
      'Choose a different alert mode for each source.',
  'settings.notification.sources.count': '{count} sources',
  'settings.notification.sources.mode': 'Alert mode',
  'settings.notification.sources.noGlobalDnd': 'Set Do not disturb separately for each fleet, community, room, or operation.',
  'settings.notification.sources.empty.title': 'No sources to manage yet',
  'settings.notification.sources.empty.description': 'Your RSI fleet, communities, active room, and operations will appear here when available.',
  'settings.notification.sourceKind.officialFleet': 'RSI fleet',
  'settings.notification.sourceKind.community': 'Community',
  'settings.notification.sourceKind.room': 'Room',
  'settings.notification.sourceKind.friends': 'Friends',
  'settings.notification.sourceKind.directMessages': 'Private messages',
  'settings.notification.sourceKind.operation': 'Operation',
  'settings.notification.mode.normal': 'Normal',
  'settings.notification.mode.important': 'Important only',
  'settings.notification.mode.doNotDisturb': 'Do not disturb',
  'settings.notification.activity.title': 'Player activity alerts',
  'settings.notification.activity.description':
      'Choose which player activity should alert you.',
  'settings.notification.activity.enabled.title':
      'Enable player activity desktop alerts',
  'settings.notification.activity.enabled.description': 'Show desktop alerts when selected players change status. Off by default.',
  'settings.notification.activity.audiences.title':
      'Whose activity should alert you',
  'settings.notification.activity.audiences.description':
      'Choose the players you want to follow.',
  'settings.notification.activity.audience.officialFleet': 'RSI fleet members',
  'settings.notification.activity.audience.friends': 'Friends',
  'settings.notification.activity.audience.room': 'Current room members',
  'settings.notification.activity.events.title':
      'Which changes should alert you',
  'settings.notification.activity.events.description':
      'Choose the status changes you want to see.',
  'settings.notification.activity.event.online': 'Player online',
  'settings.notification.activity.event.offline': 'Player offline',
  'settings.notification.activity.event.gameStart': 'Game started',
  'settings.notification.activity.event.gameStop': 'Game stopped',
  'settings.notification.activity.behavior.title': 'When alerts appear',
  'settings.notification.activity.behavior.description':
      'Choose when these alerts appear.',
  'settings.notification.activity.backgroundOnly.title':
      'Pop up only while StarBridge is in the background',
  'settings.notification.activity.backgroundOnly.description':
      'Do not show another pop-up while you are viewing StarBridge.',
  'settings.notification.activity.reduceInGame.title':
      'Reduce desktop alerts in game',
  'settings.notification.activity.reduceInGame.description':
      'Pause player activity pop-ups while the in-game overlay is open.',
  'settings.notification.play.title': 'Continuous play reminders',
  'settings.notification.play.description':
      'Get rest and hydration reminders during long play sessions.',
  'settings.notification.play.enabled.title': 'Remind me to rest and hydrate',
  'settings.notification.play.enabled.description':
      'When enabled, reminders follow the intervals below.',
  'settings.notification.play.intervals.title': 'Reminder intervals',
  'settings.notification.play.first.title': 'First reminder',
  'settings.notification.play.first.description':
      'How long continuous play lasts before the first reminder.',
  'settings.notification.play.repeat.title': 'Repeat reminder',
  'settings.notification.play.repeat.description':
      'How often reminders repeat after the first one.',
  'settings.notification.play.hours': '{count} hours',
  'settings.notification.play.minutes': '{count} minutes',
};
