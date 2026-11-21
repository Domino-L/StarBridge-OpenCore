import 'package:flutter/widgets.dart';

const usageModeWords = <String, (String, String, String)>{
  'title': ('使用模式', '使用模式', 'Usage mode'),
  'description': ('选择本机模式或在线模式', '選擇本機模式或線上模式', 'Choose local or online mode'),
  'currentLocal': ('当前：本机模式', '目前：本機模式', 'Current: Local mode'),
  'currentOnline': ('当前：在线模式', '目前：線上模式', 'Current: Online mode'),
  'toLocal': ('切换到本机模式', '切換到本機模式', 'Switch to local mode'),
  'toOnline': ('切换到在线模式', '切換到線上模式', 'Switch to online mode'),
  'confirmLocal': (
    '切换到本机模式后，舰队、聊天、交易等在线功能会停用。账号资料会保留，以后切回在线还在。',
    '切換到本機模式後，艦隊、聊天、交易等線上功能會停用。帳號資料會保留，以後切回線上還在。',
    'Switching to local mode turns off online features such as fleets, chat, and trading. Your account details are kept for when you switch back online.',
  ),
  'switch': ('切换', '切換', 'Switch'),
  'cancel': ('取消', '取消', 'Cancel'),
  'cancelSwitch': ('取消切换', '取消切換', 'Cancel switch'),
  'checkNames': ('核对游戏名', '核對遊戲名稱', 'Check game names'),
  'enableOnline': ('开启在线功能', '開啟線上功能', 'Enable online features'),
  'switched': ('已切换到在线模式', '已切換到線上模式', 'Switched to online mode'),
  'failure.cancelled': ('切换已取消。', '切換已取消。', 'The switch was cancelled.'),
  'failure.rejected': (
    '未能完成这次切换。',
    '未能完成這次切換。',
    'This switch could not be completed.',
  ),
  'failure.storage': (
    '未能保存切换结果。',
    '未能儲存切換結果。',
    'The switch result could not be saved.',
  ),
  'failure.timeout': ('切换等待超时。', '切換等待逾時。', 'The switch timed out.'),
  'failure.unexpected': (
    '切换时出了问题。',
    '切換時出了問題。',
    'Something went wrong during the switch.',
  ),
  'failure.notCommitted': (
    '切换尚未生效。',
    '切換尚未生效。',
    'The switch has not taken effect.',
  ),
};

String usageModeText(Locale locale, String key) {
  final words = usageModeWords[key]!;
  if (locale.languageCode == 'en') return words.$3;
  if (locale.scriptCode == 'Hant' ||
      const {'TW', 'HK', 'MO'}.contains(locale.countryCode)) {
    return words.$2;
  }
  return words.$1;
}
