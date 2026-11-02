/// Copy for the completed finish page: welcome, "你的资料" and the folded
/// results. Looked up by [OnboardingCopy].
const onboardingProfileWords = <String, (String, String, String)>{
  'done.title': ('欢迎来到星海舰桥', '歡迎來到星海艦橋', 'Welcome to StarBridge'),
  'done.lead.online': (
    '设置已经生效。进入之前，可以顺手看一眼你的资料。',
    '設定已經生效。進入之前，可以順手看一眼你的資料。',
    'Your setup is in effect. Before you go in, you can check your profile.',
  ),
  'done.lead.local': (
    '设置已经生效，下面是实际保存的结果。',
    '設定已經生效，下面是實際儲存的結果。',
    'Your setup is in effect. Below is what was actually saved.',
  ),
  'enterApp': ('进入星海舰桥', '進入星海艦橋', 'Enter StarBridge'),
  'results.title': ('保存结果', '儲存結果', 'Saved results'),
  'results.expand': ('展开', '展開', 'Show'),
  'results.collapse': ('收起', '收起', 'Hide'),
  'profile.title': ('你的资料', '你的資料', 'Your profile'),
  'profile.intro': (
    '可选 · 好友和舰队成员会看到这些，随时可以在个人资料页修改',
    '可選 · 好友和艦隊成員會看到這些，隨時可以在個人資料頁修改',
    'Optional · Friends and fleet members see this. You can change it on your profile page any time.',
  ),
  'profile.loading': ('正在读取你的资料…', '正在讀取你的資料…', 'Reading your profile…'),
  'profile.loadFailed': (
    '暂时读不到你的资料，可以稍后在个人资料页修改。',
    '暫時讀不到你的資料，可以稍後在個人資料頁修改。',
    'Your profile could not be read. You can change it later on your profile page.',
  ),
  'profile.avatarSource': ('来自 RSI 账号', '來自 RSI 帳號', 'From your RSI account'),
  'profile.avatarChange': ('去 RSI 修改 ↗', '去 RSI 修改 ↗', 'Change on RSI ↗'),
  'profile.rsiOpenFailed': (
    '暂时无法打开 RSI 官网，请稍后再试。',
    '暫時無法開啟 RSI 官網，請稍後再試。',
    'The RSI website could not be opened. Try again later.',
  ),
  'profile.name': ('昵称', '暱稱', 'Nickname'),
  'profile.handle': ('游戏 Handle', '遊戲 Handle', 'Game Handle'),
  'profile.status.unsaved': ('未保存', '未儲存', 'Not saved'),
  'profile.status.saved': ('已保存', '已儲存', 'Saved'),
  'profile.status.failed': ('保存失败', '儲存失敗', 'Not saved'),
  'profile.nameNote': (
    '在星海舰桥里显示的名字，最多 32 个字符。不会修改游戏 Handle。',
    '在星海艦橋裡顯示的名字，最多 32 個字元。不會修改遊戲 Handle。',
    'The name shown in StarBridge, up to 32 characters. Your game Handle does not change.',
  ),
  'profile.unsavedNote': (
    '昵称还没保存；直接进入会保留原昵称。',
    '暱稱還沒儲存；直接進入會保留原暱稱。',
    'Not saved yet. If you go in now, your current nickname stays.',
  ),
  'profile.savedNote': (
    '好友和舰队成员现在看到的就是这个名字。',
    '好友和艦隊成員現在看到的就是這個名字。',
    'Friends and fleet members now see this name.',
  ),
  'profile.renameUnavailable': (
    '这里暂时不能修改昵称，可以稍后在个人资料页修改。',
    '這裡暫時不能修改暱稱，可以稍後在個人資料頁修改。',
    'The nickname cannot be changed here right now. You can change it later on your profile page.',
  ),
  'profile.keptName': (
    '昵称没有改，仍是“{name}”。',
    '暱稱沒有改，仍是「{name}」。',
    'Your nickname is still “{name}”.',
  ),
  'profile.save': ('保存昵称', '儲存暱稱', 'Save nickname'),
  'profile.saving': ('正在保存…', '正在儲存…', 'Saving…'),
  'profile.retry': ('重试', '重試', 'Retry'),
  'profile.save.failed': (
    '网络中断，没能保存。',
    '網路中斷，沒能儲存。',
    'The connection dropped and it was not saved.',
  ),
  'profile.save.conflict': (
    '昵称刚在别处改过，已重新读取。',
    '暱稱剛在別處改過，已重新讀取。',
    'The nickname was just changed elsewhere and has been reread.',
  ),
  'profile.save.invalid': (
    '这个昵称不符合要求。',
    '這個暱稱不符合要求。',
    'This nickname is not allowed.',
  ),
  'profile.save.forbidden': (
    '账号没有修改资料的权限。',
    '帳號沒有修改資料的權限。',
    'This account is not allowed to change its profile.',
  ),
  'profile.save.cancelled': (
    '已取消授权。',
    '已取消授權。',
    'Authorization was cancelled.',
  ),
  'profile.save.unconfirmed': (
    '无法确认是否保存成功，已重新读取当前昵称。',
    '無法確認是否儲存成功，已重新讀取目前暱稱。',
    'It could not be confirmed whether it saved. The current nickname has been reread.',
  ),
  'profile.save.unavailable': (
    '暂时无法保存。',
    '暫時無法儲存。',
    'It cannot be saved right now.',
  ),
};
