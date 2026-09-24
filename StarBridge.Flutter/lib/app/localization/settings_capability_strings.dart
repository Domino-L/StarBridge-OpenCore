const simplifiedSettingsCapabilityStrings = <String, String>{
  'settings.capabilities.title': '已确认保留的能力',
  'settings.capabilities.description':
      '这些 WPF 已有或产品文档已确认的能力会按阶段接入；当前条目只说明去向，不会伪装成可用控件。',
  'settings.capabilities.status': '后续接入',
  'settings.capability.accountSafety.title': '账号状态与申诉',
  'settings.capability.accountSafety.description':
      '保留账号限制、处理结果与申诉入口，并继续使用权威账号状态。',
  'settings.capability.localRecognition.title': '游戏内服务器与舰船',
  'settings.capability.localRecognition.description':
      '显示当前服务器与舰船状态，并用于游戏内信息浮层。',
  'settings.capability.gameplayStatistics.title': '游玩时长记录',
  'settings.capability.gameplayStatistics.description':
      '继续支持明确授权、历史导入、公开范围与本地重置；未授权时不记录。',
  'settings.capability.localData.title': '本地数据管理',
  'settings.capability.localData.description': '保留安全导出、分类清理与影响说明，破坏性操作必须再次确认。',
  'settings.capability.dataStorage.title': '数据保存位置',
  'settings.capability.dataStorage.description':
      '保留查看、打开和迁移本机数据目录，并由 Native Host 执行文件操作。',
  'settings.capability.redemption.title': '兑换码与权益',
  'settings.capability.redemption.description':
      '保留 WPF 的兑换能力；登录后通过现有服务端核验，不在 Flutter 本地判断兑换结果。',
  'settings.capability.updates.title': '应用更新',
  'settings.capability.updates.description':
      '保留版本检查、更新状态和安全修复入口，安装过程继续由 Native Host 管理。',
  'settings.capability.stateSharing.title': '实时状态同步',
  'settings.capability.stateSharing.description':
      '管理在线、游戏中、飞船、位置与服务器状态；新账号只向好友开放最小默认投影。',
  'settings.capability.audience.title': '可见范围与按对象例外',
  'settings.capability.audience.description':
      '按“给谁看、看什么”管理默认范围和单个好友例外，显式拒绝始终优先。',
  'settings.capability.hangarSharing.title': '舰船共享',
  'settings.capability.hangarSharing.description':
      '保留长期共享、仅行动共享、不共享以及每个组织的独立设置入口。',
  'settings.capability.eventSharing.title': '协作事件共享',
  'settings.capability.eventSharing.description':
      '单独管理进入游戏、服务器、飞船、地点与生命状态事件，不与当前状态开关混用。',
  'settings.capability.socialPrivacy.title': '社交隐私',
  'settings.capability.socialPrivacy.description':
      '集中管理好友状态、陌生人私信、最近同玩和低可信位置等保护项。',
  'settings.capability.notificationChannels.title': '设备通知渠道',
  'settings.capability.notificationChannels.description':
      '管理应用内、声音、Windows 与浮层渠道；Windows 桌面卡新设备默认开启并从右下角显示。',
  'settings.capability.playerActivity.title': '玩家动态提醒',
  'settings.capability.playerActivity.description':
      '选择要提醒的玩家、状态变化与显示位置。',
  'settings.capability.playReminders.title': '连续游玩提醒',
  'settings.capability.playReminders.description':
      '保留首次提醒与后续间隔，提醒休息和补水，不改变游戏或房间状态。',
  'settings.capability.sourceRules.title': '来源提醒规则',
  'settings.capability.sourceRules.description':
      '舰队、社区、房间与行动分别保存正常、仅关键变化或免打扰，默认正常提醒。',
  'settings.capability.previewPrivacy.title': '外部提醒内容预览',
  'settings.capability.previewPrivacy.description':
      '控制 Windows 与短暂浮层显示完整内容、仅来源或隐藏详情，默认仅显示来源。',
  'settings.capability.deliveryControl.title': '免打扰、聚合与去重',
  'settings.capability.deliveryControl.description':
      '避免 Windows、声音与浮层重复投递；免打扰时未读只显示无数量圆点。',
  'settings.capability.runtimeStatus.title': '运行状态',
  'settings.capability.runtimeStatus.description':
      '显示 Host、游戏、身份、网络、浮层和配置目录等可验证状态。',
  'settings.capability.eventLog.title': '本地事件日志',
  'settings.capability.eventLog.description':
      '保留分类筛选、导出与清空，只展示已识别摘要，不把完整 Game.log 送入 Flutter。',
  'settings.capability.oneClickDiagnostics.title': '一键诊断与复制摘要',
  'settings.capability.oneClickDiagnostics.description':
      '检查配置、日志、连接和启动状态，并生成不含凭据与原始日志的安全摘要。',
  'settings.capability.maintenance.title': '本地维护',
  'settings.capability.maintenance.description': '保留打开目录、清理缓存和安全的数据修复入口。',
  'settings.capability.installation.title': '更新、修复与卸载',
  'settings.capability.installation.description':
      '保留重复安装检查、更新修复与卸载清理，并明确每次操作的影响。',
};

const traditionalSettingsCapabilityStrings = <String, String>{
  'settings.capabilities.title': '已確認保留的功能',
  'settings.capabilities.description':
      '這些 WPF 已有或產品文件已確認的功能會分階段接入；目前條目只說明去向，不會偽裝成可用控制項。',
  'settings.capabilities.status': '後續接入',
  'settings.capability.accountSafety.title': '帳號狀態與申訴',
  'settings.capability.accountSafety.description':
      '保留帳號限制、處理結果與申訴入口，並繼續使用權威帳號狀態。',
  'settings.capability.localRecognition.title': '遊戲內伺服器與艦船',
  'settings.capability.localRecognition.description':
      '顯示目前伺服器與艦船狀態，並用於遊戲內資訊浮層。',
  'settings.capability.gameplayStatistics.title': '遊玩時長記錄',
  'settings.capability.gameplayStatistics.description':
      '繼續支援明確授權、歷史匯入、公開範圍與本機重設；未授權時不記錄。',
  'settings.capability.localData.title': '本機資料管理',
  'settings.capability.localData.description': '保留安全匯出、分類清理與影響說明，破壞性操作必須再次確認。',
  'settings.capability.dataStorage.title': '資料儲存位置',
  'settings.capability.dataStorage.description':
      '保留查看、開啟和遷移本機資料目錄，並由 Native Host 執行檔案操作。',
  'settings.capability.redemption.title': '兌換碼與權益',
  'settings.capability.redemption.description':
      '保留 WPF 的兌換功能；登入後透過既有伺服器驗證，不在 Flutter 本機判斷結果。',
  'settings.capability.updates.title': '應用程式更新',
  'settings.capability.updates.description':
      '保留版本檢查、更新狀態和安全修復入口，安裝流程繼續由 Native Host 管理。',
  'settings.capability.stateSharing.title': '即時狀態同步',
  'settings.capability.stateSharing.description':
      '管理上線、遊戲中、艦船、位置與伺服器狀態；新帳號只向好友開放最小預設投影。',
  'settings.capability.audience.title': '可見範圍與按對象例外',
  'settings.capability.audience.description':
      '按「給誰看、看什麼」管理預設範圍和單一好友例外，明確拒絕永遠優先。',
  'settings.capability.hangarSharing.title': '艦船共享',
  'settings.capability.hangarSharing.description':
      '保留長期共享、僅行動共享、不共享以及每個組織的獨立設定入口。',
  'settings.capability.eventSharing.title': '協作事件共享',
  'settings.capability.eventSharing.description':
      '單獨管理進入遊戲、伺服器、艦船、位置與生命狀態事件，不與目前狀態開關混用。',
  'settings.capability.socialPrivacy.title': '社交隱私',
  'settings.capability.socialPrivacy.description':
      '集中管理好友狀態、陌生人私訊、最近同玩和低可信位置等保護項目。',
  'settings.capability.notificationChannels.title': '裝置通知管道',
  'settings.capability.notificationChannels.description':
      '管理應用程式內、聲音、Windows 與浮層管道；Windows 桌面卡新裝置預設開啟並從右下角顯示。',
  'settings.capability.playerActivity.title': '玩家動態提醒',
  'settings.capability.playerActivity.description':
      '選擇要提醒的玩家、狀態變化與顯示位置。',
  'settings.capability.playReminders.title': '連續遊玩提醒',
  'settings.capability.playReminders.description':
      '保留首次提醒與後續間隔，提醒休息和補水，不改變遊戲或房間狀態。',
  'settings.capability.sourceRules.title': '來源提醒規則',
  'settings.capability.sourceRules.description':
      '艦隊、社群、房間與行動分別儲存正常、僅關鍵變化或勿擾，預設正常提醒。',
  'settings.capability.previewPrivacy.title': '外部提醒內容預覽',
  'settings.capability.previewPrivacy.description':
      '控制 Windows 與短暫浮層顯示完整內容、僅來源或隱藏詳情，預設僅顯示來源。',
  'settings.capability.deliveryControl.title': '勿擾、彙整與去重',
  'settings.capability.deliveryControl.description':
      '避免 Windows、聲音與浮層重複投遞；勿擾時未讀只顯示無數量圓點。',
  'settings.capability.runtimeStatus.title': '執行狀態',
  'settings.capability.runtimeStatus.description':
      '顯示 Host、遊戲、身分、網路、浮層和設定目錄等可驗證狀態。',
  'settings.capability.eventLog.title': '本機事件記錄',
  'settings.capability.eventLog.description':
      '保留分類篩選、匯出與清空，只顯示已識別摘要，不把完整 Game.log 送入 Flutter。',
  'settings.capability.oneClickDiagnostics.title': '一鍵診斷與複製摘要',
  'settings.capability.oneClickDiagnostics.description':
      '檢查設定、記錄、連線和啟動狀態，並產生不含憑證與原始記錄的安全摘要。',
  'settings.capability.maintenance.title': '本機維護',
  'settings.capability.maintenance.description': '保留開啟目錄、清理快取和安全的資料修復入口。',
  'settings.capability.installation.title': '更新、修復與解除安裝',
  'settings.capability.installation.description':
      '保留重複安裝檢查、更新修復與解除安裝清理，並明確每次操作的影響。',
};

const englishSettingsCapabilityStrings = <String, String>{
  'settings.capabilities.title': 'Confirmed capabilities to retain',
  'settings.capabilities.description': 'These WPF capabilities and documented product decisions will be connected in stages. These rows show their destination without pretending they work yet.',
  'settings.capabilities.status': 'Planned',
  'settings.capability.accountSafety.title': 'Account status and appeals',
  'settings.capability.accountSafety.description': 'Retains account restrictions, outcomes, and appeal entry points backed by authoritative account state.',
  'settings.capability.localRecognition.title':
      'In-game server and ship',
  'settings.capability.localRecognition.description': 'Shows the current server and ship in the in-game information overlay.',
  'settings.capability.gameplayStatistics.title': 'Playtime tracking',
  'settings.capability.gameplayStatistics.description': 'Keeps explicit consent, history import, visibility and local reset. Nothing is recorded without consent.',
  'settings.capability.localData.title': 'Local data management',
  'settings.capability.localData.description': 'Keeps safe export, scoped clearing and impact summaries, with confirmation for destructive actions.',
  'settings.capability.dataStorage.title': 'Data storage location',
  'settings.capability.dataStorage.description': 'Keeps viewing, opening and migrating the device data directory through the Native Host.',
  'settings.capability.redemption.title': 'Codes and entitlements',
  'settings.capability.redemption.description': 'Retains WPF redemption through the existing server validation path. Flutter will not decide outcomes locally.',
  'settings.capability.updates.title': 'Application updates',
  'settings.capability.updates.description': 'Keeps version checks, update state and repair entry points while installation remains owned by the Native Host.',
  'settings.capability.stateSharing.title': 'Realtime state sharing',
  'settings.capability.stateSharing.description': 'Controls online, in-game, ship, location and server state. New accounts expose only a minimal friend projection by default.',
  'settings.capability.audience.title': 'Audience and per-person exceptions',
  'settings.capability.audience.description': 'Organizes privacy by who can see what, with explicit denial always taking priority.',
  'settings.capability.hangarSharing.title': 'Ship sharing',
  'settings.capability.hangarSharing.description': 'Keeps long-term, operation-only and no-sharing choices with independent settings for each organization.',
  'settings.capability.eventSharing.title': 'Collaboration event sharing',
  'settings.capability.eventSharing.description': 'Separately controls game, server, ship, location and life-state events instead of mixing them with current-state switches.',
  'settings.capability.socialPrivacy.title': 'Social privacy',
  'settings.capability.socialPrivacy.description': 'Collects friend presence, stranger messages, recently played and low-confidence location protections.',
  'settings.capability.notificationChannels.title':
      'Device notification channels',
  'settings.capability.notificationChannels.description': 'Controls in-app, sound, Windows and overlay channels. Branded Windows cards default on and appear at bottom right on new devices.',
  'settings.capability.playerActivity.title': 'Player activity alerts',
  'settings.capability.playerActivity.description': 'Choose players, status changes and where alerts appear.',
  'settings.capability.playReminders.title': 'Continuous play reminders',
  'settings.capability.playReminders.description': 'Keeps first and repeat intervals for rest and hydration without changing game or room state.',
  'settings.capability.sourceRules.title': 'Source notification rules',
  'settings.capability.sourceRules.description': 'Stores Normal, Important only, or Do not disturb independently for fleets, communities, rooms and operations. Normal is the default.',
  'settings.capability.previewPrivacy.title': 'External notification previews',
  'settings.capability.previewPrivacy.description': 'Controls full content, source only, or hidden details for Windows and transient overlay alerts. Source only is the default.',
  'settings.capability.deliveryControl.title':
      'Do not disturb, grouping, and deduplication',
  'settings.capability.deliveryControl.description': 'Prevents duplicate Windows, sound and overlay delivery. Do not disturb reduces unread counts to an unnumbered dot.',
  'settings.capability.runtimeStatus.title': 'Runtime status',
  'settings.capability.runtimeStatus.description': 'Shows verifiable Host, game, identity, network, overlay and configuration-directory state.',
  'settings.capability.eventLog.title': 'Local event log',
  'settings.capability.eventLog.description': 'Keeps filtering, export and clearing for recognized summaries without sending the full Game.log to Flutter.',
  'settings.capability.oneClickDiagnostics.title':
      'One-click diagnostics and safe copy',
  'settings.capability.oneClickDiagnostics.description': 'Checks configuration, logs, connectivity and startup, then produces a summary without credentials or raw logs.',
  'settings.capability.maintenance.title': 'Local maintenance',
  'settings.capability.maintenance.description': 'Keeps directory access, cache cleanup and safe data-repair entry points.',
  'settings.capability.installation.title': 'Update, repair, and uninstall',
  'settings.capability.installation.description': 'Keeps duplicate-install checks, update repair and uninstall cleanup with explicit impact summaries.',
};
