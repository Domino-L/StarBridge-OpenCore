/// Copy for the one-time startup/close prompt shown to existing users who
/// skip first-use setup. Looked up by [OnboardingCopy].
const onboardingBehaviorPromptWords = <String, (String, String, String)>{
  'appBehavior.current': ('当前', '目前', 'Current'),
  'behaviorPrompt.title.both': ('启动与关闭方式', '啟動與關閉方式', 'Startup and closing'),
  'behaviorPrompt.title.startup': (
    '开机时怎么启动？',
    '開機時怎麼啟動？',
    'What should happen when Windows starts?',
  ),
  'behaviorPrompt.title.close': (
    '关闭主窗口时怎么处理？',
    '關閉主視窗時怎麼處理？',
    'What should happen when you close the main window?',
  ),
  'behaviorPrompt.intro.both': (
    'StarBridge 在后台运行时，才能在游戏里显示浮层、响应快捷键、识别游戏并记录游玩时长。请按你的习惯各选一项。',
    'StarBridge 在背景執行時，才能在遊戲裡顯示浮層、回應快捷鍵、識別遊戲並記錄遊玩時長。請依你的習慣各選一項。',
    'StarBridge needs to run in the background to show the in-game overlay, respond to shortcuts, recognize the game and record play time. Pick one of each.',
  ),
  'behaviorPrompt.intro.one': (
    'StarBridge 在后台运行时，才能在游戏里显示浮层、响应快捷键、识别游戏并记录游玩时长。请按你的习惯选一项。',
    'StarBridge 在背景執行時，才能在遊戲裡顯示浮層、回應快捷鍵、識別遊戲並記錄遊玩時長。請依你的習慣選一項。',
    'StarBridge needs to run in the background to show the in-game overlay, respond to shortcuts, recognize the game and record play time. Pick one.',
  ),
  'behaviorPrompt.chosen.startup': (
    '开机方式你之前已经选过：{choice}，这里不再询问。',
    '開機方式你之前已經選過：{choice}，這裡不再詢問。',
    'You already chose what happens at startup: {choice}. It is not asked again.',
  ),
  'behaviorPrompt.chosen.close': (
    '关闭方式你之前已经选过：{choice}，这里不再询问。',
    '關閉方式你之前已經選過：{choice}，這裡不再詢問。',
    'You already chose what happens on close: {choice}. It is not asked again.',
  ),
  'behaviorPrompt.need.both': (
    '请分别选择两项；任意组合都可以。',
    '請分別選擇兩項；任何組合都可以。',
    'Pick one of each; any combination is fine.',
  ),
  'behaviorPrompt.need.one': ('请选择一项。', '請選擇一項。', 'Pick one.'),
  'behaviorPrompt.local.both': (
    '这两项只影响本机，不会开启共享，也不会修改隐私设置。',
    '這兩項只影響本機，不會開啟共享，也不會修改隱私設定。',
    'Both only affect this device. Sharing and privacy settings do not change.',
  ),
  'behaviorPrompt.local.one': (
    '这一项只影响本机，不会开启共享，也不会修改隐私设置。',
    '這一項只影響本機，不會開啟共享，也不會修改隱私設定。',
    'This only affects this device. Sharing and privacy settings do not change.',
  ),
  'behaviorPrompt.later': ('稍后再说', '稍後再說', 'Later'),
  'behaviorPrompt.save': ('保存', '儲存', 'Save'),
  'behaviorPrompt.retry': ('重试', '重試', 'Retry'),
  'behaviorPrompt.done': ('完成', '完成', 'Done'),
};
