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
  String get clearData =>
      pick('退出 RSI 登录并清除数据', '登出 RSI 並清除資料', 'Sign out of RSI and clear data');
  String get clearConfirmation => pick(
    '这会退出机库读取里的 RSI 登录，并删除这台电脑上机库读取保存的浏览器数据（登录状态、Cookie、缓存）。已保存到本机的舰船不受影响。',
    '這會登出機庫讀取裡的 RSI，並刪除這台電腦上機庫讀取儲存的瀏覽器資料（登入狀態、Cookie、快取）。已儲存到本機的艦船不受影響。',
    'This signs you out of RSI in the hangar reader and deletes the browser data it stores on this computer (sign-in state, cookies and cache). Ships already saved on this device are unaffected.',
  );
  String get keepData => pick('取消', '取消', 'Cancel');
  String get acknowledge => pick('知道了', '知道了', 'OK');
  String get clearFailedTitle => pick('未能清除', '未能清除', "Couldn't clear");
  String get clearSuccess => pick(
    '已退出 RSI 登录，并清除了本机保存的 RSI 登录数据。下次读取机库时需要重新登录 RSI。',
    '已登出 RSI，並清除了本機儲存的 RSI 登入資料。下次讀取機庫時需要重新登入 RSI。',
    "Signed out of RSI and cleared the RSI sign-in data saved on this device. You'll need to sign in to RSI again the next time you read your hangar.",
  );
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
  String safety(bool remember) => remember
      ? pick(
          '登录状态保留在本机；过期时需重新登录。读取不会购买、赠送或回收物品。',
          '登入狀態保留在本機；過期時需重新登入。讀取不會購買、贈送或回收物品。',
          'Sign-in is kept on this device until it expires. Reading does not buy, gift or reclaim items.',
        )
      : pick(
          '不记住的话，读完会自动清除，下次要重新登录。读取不会购买、赠送或回收物品。',
          '不記住的話，讀完會自動清除，下次要重新登入。讀取不會購買、贈送或回收物品。',
          "If you don't, it is cleared after reading and you sign in again next time. Reading does not buy, gift or reclaim items.",
        );
  String get remember => pick(
    '在这台电脑上记住 RSI 登录',
    '在這台電腦上記住 RSI 登入',
    'Remember my RSI sign-in on this computer',
  );
  String get uncleared => pick(
    '上次没能清除 RSI 登录数据（可能正被占用）。可以点“退出 RSI 登录并清除数据”再试一次，或者重启星桥。',
    '上次沒能清除 RSI 登入資料（可能正被佔用）。可以點「登出 RSI 並清除資料」再試一次，或者重新啟動星橋。',
    'The RSI sign-in data could not be cleared last time (it may be in use). Use Sign out of RSI and clear data to try again, or restart StarBridge.',
  );
  String get unknownChoice => pick(
    '没能读取“记住 RSI 登录”这个设置，这次不会自动清除登录。可以重新勾选一次，或者点“退出 RSI 登录并清除数据”。',
    '沒能讀取「記住 RSI 登入」這個設定，這次不會自動清除登入。可以重新勾選一次，或者點「登出 RSI 並清除資料」。',
    "The Remember RSI sign-in setting couldn't be read, so sign-in is not cleared automatically this time. Set it again, or use Sign out of RSI and clear data.",
  );
  String get rememberLocked =>
      pick('读取中不能更改。', '讀取中不能變更。', "Can't be changed while reading.");
  String get rememberReopens => pick(
    '更改后网页会重新打开，需要重新登录一次。',
    '變更後網頁會重新開啟，需要重新登入一次。',
    'Changing it reopens the page; you sign in once more.',
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
    'clearing' => pick(
      '正在退出并清除…',
      '正在登出並清除…',
      'Signing out and clearing data…',
    ),
    'cleared' => pick('已退出并清除', '已登出並清除', 'Signed out and data cleared'),
    'forgotten' => pick(
      '已清除 RSI 登录。下次读取需要重新登录。',
      '已清除 RSI 登入。下次讀取需要重新登入。',
      'RSI sign-in cleared. Sign in again next time you read.',
    ),
    'choice_failed' => pick(
      '没能保存这个选择，请重试。',
      '沒能儲存這個選擇，請重試。',
      "This choice couldn't be saved. Try again.",
    ),
    'clear_busy' => pick(
      '浏览器数据仍被占用或暂时无法访问，未能完成清除。请稍后重试。',
      '瀏覽器資料仍被佔用或暫時無法存取，未能完成清除。請稍後重試。',
      'Browser data is still in use or temporarily inaccessible. Clearing did not finish. Try again shortly.',
    ),
    'clear_unsafe' => pick(
      '浏览器数据目录或其父目录是链接，为保护其他文件已停止清除。请检查目录后重试。',
      '瀏覽器資料目錄或其父目錄是連結，為保護其他檔案已停止清除。請檢查目錄後重試。',
      'The browser data folder or its parent is a link. Clearing stopped to protect other files. Check the folders and retry.',
    ),
    'clear_failed' => pick(
      '无法完成浏览器数据清除，尚未确认退出。请重试；若仍失败，请检查目录访问权限。',
      '無法完成瀏覽器資料清除，尚未確認登出。請重試；若仍失敗，請檢查目錄存取權限。',
      'Browser data could not be fully cleared; sign-out is not confirmed. Retry, or check folder permissions if it keeps failing.',
    ),
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
