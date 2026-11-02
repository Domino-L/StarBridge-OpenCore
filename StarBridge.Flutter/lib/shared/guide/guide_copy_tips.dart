// Page tip strips. `points` items are separated by '|'.
const guideTipWords = <String, (String, String, String)>{
  'tip.gotIt': ('知道了', '知道了', 'Got it'),
  'tip.tour': ('带我走一遍', '帶我走一遍', 'Show me around'),
  'tip.fleet.title': (
    '你在 RSI 官网的舰队。',
    '你在 RSI 官網的艦隊。',
    'Your fleet from the RSI website.',
  ),
  'tip.fleet.points': (
    '概览：公告和要处理的事|成员：谁在线、谁已经进游戏|频道：舰队里聊天|舰船：队友愿意借出的船',
    '概覽：公告和要處理的事|成員：誰在線、誰已經進遊戲|頻道：艦隊裡聊天|艦船：隊友願意借出的船',
    'Overview: announcements and things to handle|Members: who is online or in game|Channel: fleet chat|Ships: ships teammates are willing to lend',
  ),
  'tip.fleet.note': (
    '队友能看到你多少状态，由你在共享与隐私里说了算。',
    '隊友能看到你多少狀態，由你在共享與隱私裡說了算。',
    'You decide in Sharing and privacy how much teammates can see.',
  ),
  'tip.fleet.action': ('看看共享设置', '看看共享設定', 'Sharing settings'),
  'tip.rooms.title': (
    '临时组队与即时状态。',
    '臨時組隊與即時狀態。',
    'Quick groups and live status.',
  ),
  'tip.rooms.points': (
    '按玩法和标签找车，申请上车|自己开房间招人，房主审批、管设置',
    '按玩法和標籤找車，申請上車|自己開房間招人，房主審批、管設定',
    'Find a group by gameplay and tags, then ask to join|Open your own room; as host you approve requests and manage settings',
  ),
  'tip.rooms.note': (
    '不用进舰队或组织也能玩。',
    '不用進艦隊或組織也能玩。',
    'No fleet or organization needed.',
  ),
  'tip.market.title': (
    '买卖游戏物品，进行交易默认你已经了解并同意SCM网站上的交易条款',
    '買賣遊戲物品，進行交易預設你已經了解並同意SCM網站上的交易條款',
    'Buy and sell game items. Trading means you have read and agree to the trading terms on the SCM website.',
  ),
  'tip.market.points': (
    '搜物品，看谁在卖、谁在收|自己挂单，同一件最多挂 3 条|SCM 托管交易：卖家发货，你进游戏验完货再确认收货|交易完双方互评，攒信誉',
    '搜物品，看誰在賣、誰在收|自己掛單，同一件最多掛 3 條|SCM 託管交易：賣家發貨，你進遊戲驗完貨再確認收貨|交易完雙方互評，攢信譽',
    'Search items to see who sells and who buys|Post listings, up to 3 per item|SCM escrow: the seller delivers, you check in game, then confirm receipt|Both sides rate each other afterwards',
  ),
  'tip.market.action': ('看看怎么挂单', '看看怎麼掛單', 'How listings work'),
  'tip.communities.title': (
    '跨舰队的长期组织，不影响你在 RSI 的舰队',
    '跨艦隊的長期組織，不影響你在 RSI 的艦隊',
    'Long-term groups across fleets; your RSI fleet is unaffected',
  ),
  'tip.communities.points': (
    '在“寻找组织”里搜一搜、申请加入，或者填邀请码|组织里有公告、日志和成员|可以把自己的船共享给组织',
    '在「尋找組織」裡搜一搜、申請加入，或者填邀請碼|組織裡有公告、日誌和成員|可以把自己的船共享給組織',
    'Search "Find organizations" and apply, or enter an invite code|Organizations have announcements, logs and members|You can share your ships with an organization',
  ),
  'tip.hangar.title': ('你的飞船都停在这儿', '你的飛船都停在這兒', 'Your ships live here'),
  'tip.hangar.points': (
    '从 RSI 官网读取舰船，你核对过才入库|收藏、筛选、翻看每艘船的详情|每艘船给舰队还是组织看，你自己定',
    '從 RSI 官網讀取艦船，你核對過才入庫|收藏、篩選、翻看每艘船的詳情|每艘船給艦隊還是組織看，你自己定',
    'Read ships from the RSI website; nothing is saved until you check it|Bookmark, filter and browse each ship|You decide whether your fleet or an organization sees each ship',
  ),
  'tip.hangar.note': (
    '数据存在这台电脑上。只是读取，不会买、送或回收任何东西。',
    '資料存在這台電腦上。只是讀取，不會買、送或回收任何東西。',
    'Data stays on this computer. Reading never buys, gifts or melts anything.',
  ),
  'tip.overlay.title': (
    '游戏里的信息，可以高度自定义',
    '遊戲裡的資訊，可以高度自訂',
    'In-game information, your way',
  ),
  'tip.overlay.points': (
    '舰队和房间各有一套浮层|换外观、拖布局|设快捷键，进出游戏自动开关',
    '艦隊和房間各有一套浮層|換外觀、拖佈局|設快捷鍵，進出遊戲自動開關',
    'Separate overlays for fleet and rooms|Change the look and drag the layout|Set a shortcut and auto open/close with the game',
  ),
  'tip.tools.title': (
    '玩游戏时顺手用的小工具',
    '玩遊戲時順手用的小工具',
    'Handy tools while you play',
  ),
  'tip.tools.points': (
    '行政机库：开放倒计时一眼看清，还能放进游戏内菜单|更多工具在路上',
    '行政機庫：開放倒數一眼看清，還能放進遊戲內選單|更多工具在路上',
    'Executive hangar: see the opening countdown, also in the in-game menu|More tools are on the way',
  ),
  'tip.settings.title': (
    '外观、语言、开机方式、隐私，都在这调整',
    '外觀、語言、開機方式、隱私，都在這調整',
    'Appearance, language, startup and privacy are all here',
  ),
  'tip.settings.points': (
    '共享与隐私：别人能看到你多少|账号与识别：在线账号、本地模式、游戏识别',
    '共享與隱私：別人能看到你多少|帳號與識別：線上帳號、本機模式、遊戲識別',
    'Sharing and privacy: how much others can see|Account and recognition: online account, local mode, game recognition',
  ),
  'tip.friends.title': (
    '加了好友，谁上线、谁进游戏一目了然',
    '加了好友，誰上線、誰進遊戲一目了然',
    'See at a glance which friends are online or in game',
  ),
  'tip.friends.points': (
    '搜昵称发申请|处理别人发来的申请|不想理的人可以屏蔽',
    '搜暱稱發申請|處理別人發來的申請|不想理的人可以封鎖',
    'Search a nickname to send a request|Handle requests sent to you|Block people you do not want to hear from',
  ),
  'tip.friends.note': (
    '谁能加你，在共享与隐私里设置。',
    '誰能加你，在共享與隱私裡設定。',
    'Choose who can add you in Sharing and privacy.',
  ),
  'tip.messages.title': (
    '和好友、队友私聊',
    '和好友、隊友私聊',
    'Private chats with friends and teammates',
  ),
  'tip.messages.points': (
    '陌生人第一次找你，会先进“消息请求”，你点了接受才开聊',
    '陌生人第一次找你，會先進「訊息請求」，你點了接受才開聊',
    'A first message from a stranger lands in Message requests until you accept it',
  ),
  'tip.messages.note': (
    '谁能私信你，在共享与隐私里设置。',
    '誰能私訊你，在共享與隱私裡設定。',
    'Choose who can message you in Sharing and privacy.',
  ),
  'tip.notifications.title': (
    '邀请、入队申请、审批结果、交易情况，都会在这儿提醒你',
    '邀請、入隊申請、審批結果、交易情況，都會在這兒提醒你',
    'Invitations, join requests, decisions and trade updates show up here',
  ),
  'tip.profile.title': (
    '别人点开你，看到的就是这一页',
    '別人點開你，看到的就是這一頁',
    'This is what others see when they open your profile',
  ),
  'tip.profile.points': (
    '头像、昵称、交易时段一直公开|下面的模块给不给看，隐私设置说了算|SCM 头像要去 RSI 官网换',
    '頭像、暱稱、交易時段一直公開|下面的模組給不給看，隱私設定說了算|SCM 頭像要去 RSI 官網換',
    'Avatar, nickname and trading hours are always public|Privacy settings decide whether the sections below are shown|Change an SCM avatar on the RSI website',
  ),
  'tip.profile.action': ('看看隐私设置', '看看隱私設定', 'Privacy settings'),
  'tip.achievements.title': (
    '你的星海履历',
    '你的星海履歷',
    'Your journey among the stars',
  ),
  'tip.achievements.points': (
    '达成条件，成就就会点亮挂在这儿|可以分类查看',
    '達成條件，成就就會點亮掛在這兒|可以分類查看',
    'Achievements light up here once you meet their conditions|Browse them by category',
  ),
};
