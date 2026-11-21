import 'package:flutter/material.dart';

import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_states.dart' show marketTextAction;

String marketplaceFailureCode(Object error) => switch (error) {
  MarketplaceTradeError() => error.code,
  // Only the port's own pre-send refusal (offline mode, missing capability)
  // proves nothing was sent. The port's post-response check, the Host's
  // `marketplace.unavailable` and `marketplace.context_changed` can follow a
  // request SCM already received, so they stay uncertain for writes.
  FormatException(message: 'marketplace.offline') => 'marketplace.offline',
  _ => 'marketplace.unknown',
};

bool marketplaceNeedsLogin(String? code) => const {
  'marketplace.sign_in_required', 'marketplace.reauthorize_required',
}.contains(code);

/// Refusals raised before any request reaches SCM (Host preflight checks in
/// `OAuthPkceClient.Trades`/`Listings`, or the port's offline guard).
const marketplacePreflightFailures = {
  'marketplace.reauthorize_required', 'marketplace.invalid_request',
  'marketplace.offline',
};

const marketplaceRecoveryCopy = <String, List<String>>{
  '请先登录 SCM': ['请先登录 SCM', '請先登入 SCM', 'Sign in to SCM first'],
  '需要重新授权 SCM 才能操作': ['需要重新授权 SCM 才能操作', '需要重新授權 SCM 才能操作', 'Reauthorize SCM to continue'],
  '重新授权': ['重新授权', '重新授權', 'Reauthorize'],
  '登录': ['登录', '登入', 'Sign in'],
  '当前无法连接 SCM（离线或功能不可用）': ['当前无法连接 SCM（离线或功能不可用）', '目前無法連線 SCM（離線或功能無法使用）', 'Cannot connect to SCM (offline or feature unavailable)'],
  '请求未发出，请检查填写内容后重试': ['请求未发出，请检查填写内容后重试', '請求未送出，請檢查填寫內容後重試', 'Request not sent. Check the fields and try again'],
  '当前账号或连接已变化，请刷新后重试': ['当前账号或连接已变化，请刷新后重试', '目前帳號或連線已變更，請重新整理後重試', 'Account or connection changed. Refresh and try again'],
  '写入未确认，请刷新挂单后核对': ['写入未确认，请刷新挂单后核对', '寫入未確認，請重新整理掛單後核對', 'Write not confirmed. Refresh and check your listings'],
  '刷新核对': ['刷新核对', '重新整理並核對', 'Refresh and check'],
  '请先刷新核对上次操作结果，再编辑或发布挂单': ['请先刷新核对上次操作结果，再编辑或发布挂单', '請先重新整理並核對上次操作結果，再編輯或發布掛單', 'Refresh and check the last action before editing or publishing listings'],
  '保存后有效期从现在重新计算': ['保存后有效期从现在重新计算', '儲存後有效期從現在重新計算', 'Saving restarts the validity period from now'],
  '登录 SCM 后可以发布和管理挂单': ['登录 SCM 后可以发布和管理挂单', '登入 SCM 後可以發布和管理掛單', 'Sign in to SCM to publish and manage listings'],
  '暂时读不到我的挂单': ['暂时读不到我的挂单', '暫時無法讀取我的掛單', 'Could not load your listings'],
  '暂时读不到仓位，请重试': ['暂时读不到仓位，请重试', '暫時無法讀取倉位，請重試', 'Could not load storage spaces. Try again'],
};

String recoveryText(BuildContext context, String key) {
  final values = marketplaceRecoveryCopy[key];
  if (values == null) return key;
  final locale = marketLocale(context);
  return values[locale == 'en' ? 2 : locale == 'hant' ? 1 : 0];
}

class MarketplaceAuthNotice extends StatelessWidget {
  const MarketplaceAuthNotice(this.code, {this.login, super.key});
  final String? code;
  final Future<void> Function(BuildContext)? login;
  @override
  Widget build(BuildContext context) {
    final reauthorize = code == 'marketplace.reauthorize_required';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(recoveryText(context, reauthorize ? '需要重新授权 SCM 才能操作' : '请先登录 SCM')),
      marketTextAction(
        onPressed: login == null ? null : () => login!(context),
        child: Text(recoveryText(context, reauthorize ? '重新授权' : '登录')),
      ),
    ]);
  }
}
