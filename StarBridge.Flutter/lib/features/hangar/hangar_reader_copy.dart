import 'package:flutter/widgets.dart';

/// Feature-local copy keeps the shared settings localization seam untouched.
class HangarReaderCopy {
  HangarReaderCopy(BuildContext context)
    : locale = Localizations.localeOf(context);
  final Locale locale;
  String pick(String cn, String tw, String en) => locale.languageCode != 'zh'
      ? en
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? tw
      : cn;
  String get title => pick('读取机库', '讀取機庫', 'Read hangar');
  String get hangar => pick('个人机库', '個人機庫', 'Personal hangar');
  String get back => pick('返回个人机库', '返回個人機庫', 'Back to hangar');
  String get open => pick('打开 RSI 机库', '開啟 RSI 機庫', 'Open RSI hangar');
  String get start => pick('开始读取', '開始讀取', 'Start reading');
  String get resume => pick('继续读取', '繼續讀取', 'Continue reading');
  String get retry => pick('重新打开', '重新開啟', 'Reopen');
  String get reread => pick('重新读取', '重新讀取', 'Read again');
  String get cancel => pick('取消读取', '取消讀取', 'Cancel reading');
  String get login => pick('前往账号与识别', '前往帳號與識別', 'Open account settings');
  String get intro => pick(
    '读取 RSI 机库中的舰船，核对后保存到本机。',
    '讀取 RSI 機庫中的艦船，核對後儲存到本機。',
    'Read the ships in your RSI hangar, review them and save on this device.',
  );
  String get notSaved => pick(
    '本次结果仅供预览，尚未保存到个人机库。',
    '本次結果僅供預覽，尚未儲存到個人機庫。',
    'This is a preview. It has not been saved to your hangar.',
  );
  String get noInventory =>
      pick('还没有可显示的机库资料', '還沒有可顯示的機庫資料', 'No hangar data to display yet');
  String get instructions => pick(
    '打开机库后，在网页中登录 RSI，点击头像展开账号信息，然后开始读取。',
    '開啟機庫後，在網頁中登入 RSI，點擊頭像展開帳號資訊，然後開始讀取。',
    'Open the hangar, sign in to RSI, open your account menu, then start reading.',
  );
  String get safety => pick(
    '登录状态保留在本机；过期时需重新登录。读取不会购买、赠送或回收物品。',
    '登入狀態保留在本機；過期時需重新登入。讀取不會購買、贈送或回收物品。',
    'Sign-in is kept on this device until it expires. Reading does not buy, gift or reclaim items.',
  );
  String get account => pick('应用内 Handle', '應用程式內 Handle', 'App Handle');
  String get preview => pick('读取结果', '讀取結果', 'Reading results');
  String get detectedShips => pick('已识别舰船', '已識別艦船', 'Recognized ships');
  String get liveResultsHint => pick(
    '随扫描逐页更新 · 尚未保存',
    '隨掃描逐頁更新 · 尚未儲存',
    'Updates as pages are read · Not saved',
  );
  String get awaitingShips => pick(
    '读取后，舰船会逐页显示在这里。',
    '讀取後，艦船會逐頁顯示在這裡。',
    'Ships will appear here as pages are read.',
  );
  String progress(int pages, int? total, int ships) => pick(
    '已读取 $pages / ${total ?? "—"} 页 · 已识别 $ships 艘',
    '已讀取 $pages / ${total ?? "—"} 頁 · 已識別 $ships 艘',
    '$pages / ${total ?? "—"} pages read · $ships ships found',
  );
  String count(int ships) => pick('$ships 艘舰船', '$ships 艘艦船', '$ships ships');
  String get previewLimit =>
      pick('此处最多展示 200 艘。', '此處最多展示 200 艘。', 'Showing up to 200 ships.');
  String status(String phase) => switch (phase) {
    'idle' => intro,
    'opening' => pick('正在打开 RSI 机库…', '正在開啟 RSI 機庫…', 'Opening RSI hangar…'),
    'ready' => instructions,
    'starting' => pick('正在核对账号…', '正在核對帳號…', 'Checking your account…'),
    'reading' => pick(
      '正在扫描，网页操作已锁定。你可以取消或退出。',
      '正在掃描，網頁操作已鎖定。你可以取消或離開。',
      'Scanning. Web controls are locked; you can cancel or leave.',
    ),
    'verifying' => pick('正在复查读取结果…', '正在複查讀取結果…', 'Verifying the results…'),
    'awaitingIdentity' => pick(
      '请点击网页右上角头像，展开账号信息后继续读取。',
      '請點擊網頁右上角頭像，展開帳號資訊後繼續讀取。',
      'Open the account menu at the top right of the web page, then continue.',
    ),
    'loginRequired' || 'navigation' => pick(
      '请先在网页中登录 RSI，进入机库后再读取。',
      '請先在網頁中登入 RSI，進入機庫後再讀取。',
      'Sign in to RSI and open your hangar before reading.',
    ),
    'identityReadFailed' => pick(
      '暂时无法读取网页账号信息。请重新打开机库后重试。',
      '暫時無法讀取網頁帳號資訊。請重新開啟機庫後重試。',
      'The web account information could not be read. Reopen the hangar and retry.',
    ),
    'identityAmbiguous' => pick(
      '网页中的账号信息不一致。请重新打开机库后重试。',
      '網頁中的帳號資訊不一致。請重新開啟機庫後重試。',
      'The web page contains conflicting account information. Reopen the hangar and retry.',
    ),
    'identityMismatch' => pick(
      '网页账号与应用内 Handle 不一致。请登录对应的 RSI 账号后重试。',
      '網頁帳號與應用程式內 Handle 不一致。請登入對應的 RSI 帳號後重試。',
      'The RSI account does not match your app Handle. Sign in to the matching account and retry.',
    ),
    'identityUnavailable' => pick(
      '请先在账号与识别中完成 RSI 身份验证。',
      '請先在帳號與識別中完成 RSI 身份驗證。',
      'Verify your RSI identity in Account & identity first.',
    ),
    'accountChanged' => pick(
      '登录账号已变化，本次读取已停止。请重新打开机库。',
      '登入帳號已變更，本次讀取已停止。請重新開啟機庫。',
      'Your signed-in account changed. Reopen the hangar to continue.',
    ),
    'cancelled' => pick(
      '已取消读取。个人机库未更改。',
      '已取消讀取。個人機庫未變更。',
      'Reading cancelled. Your saved hangar is unchanged.',
    ),
    'complete' => notSaved,
    'needsReview' => pick(
      '部分物品暂时无法识别。已保留可识别的舰船供你查看，结果尚未保存。',
      '部分物品暫時無法識別。已保留可識別的艦船供你查看，結果尚未儲存。',
      'Some items could not be identified. Review the recognized ships below; nothing has been saved.',
    ),
    'emptyUnconfirmed' => pick(
      '尚未读到物品。请确认网页已加载完成，再继续读取。',
      '尚未讀到物品。請確認網頁已載入完成，再繼續讀取。',
      'No items were read. Check that the page has finished loading, then continue.',
    ),
    'filtered' => pick(
      '请清除网页中的搜索和筛选，再重新读取。',
      '請清除網頁中的搜尋和篩選，再重新讀取。',
      'Clear the web page search and filters, then read again.',
    ),
    'runtime' => pick(
      '无法打开内置浏览器。请重新打开；若仍失败，请重启客户端。',
      '無法開啟內建瀏覽器。請重新開啟；若仍失敗，請重新啟動用戶端。',
      'The embedded browser could not open. Try reopening it; if it still fails, restart the app.',
    ),
    'hostUnavailable' => pick(
      '读取服务暂不可用，请重新启动客户端后重试。',
      '讀取服務暫時無法使用，請重新啟動用戶端後重試。',
      'The reader is unavailable. Restart the app and try again.',
    ),
    'timedOut' => pick(
      '网页响应超时。请检查连接后重试。',
      '網頁回應逾時。請檢查連線後重試。',
      'The page took too long to respond. Check your connection and retry.',
    ),
    'pageChanged' => pick(
      '网页内容已变化，本次读取已停止。请重新读取。',
      '網頁內容已變更，本次讀取已停止。請重新讀取。',
      'The page changed during reading. Start a new reading.',
    ),
    'unsupported' => pick(
      '暂时无法识别当前网页，请重新打开机库后重试。',
      '暫時無法識別目前網頁，請重新開啟機庫後重試。',
      'This page could not be read. Reopen the RSI hangar and retry.',
    ),
    _ => pick(
      '读取未完成，请重新打开机库后重试。',
      '讀取未完成，請重新開啟機庫後重試。',
      'Reading did not finish. Reopen the hangar and retry.',
    ),
  };
}
