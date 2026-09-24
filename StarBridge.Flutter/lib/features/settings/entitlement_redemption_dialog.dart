import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../account/account_models.dart';

Future<void> showLegacyEntitlementRedemptionDialog(
  BuildContext context,
  ValueListenable<AccountProjection> account,
  BridgeClientSession? session,
) => showDialog<void>(
  context: context,
  builder: (_) => ValueListenableBuilder<AccountProjection>(
    valueListenable: account,
    builder: (context, owner, _) => EntitlementRedemptionDialog(
      key: ValueKey((owner.generation, owner.sessionState)),
      supported:
          owner.isLegacyAccount &&
          session != null &&
          session.hostCapabilities.contains('account.redeemLegacyEntitlements'),
      redeem: (code) async {
        if (session == null ||
            !owner.isLegacyAccount ||
            session.activeGeneration != owner.generation) {
          return 'sessionChanged';
        }
        final current = await session.request(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
        );
        if (current.accountContext == null ||
            current.payload['state'] != 'legacySignedIn' ||
            current.sessionGeneration != owner.generation ||
            account.value.generation != owner.generation) {
          return 'sessionChanged';
        }
        final result = await session.request(
          'account.redeemLegacyEntitlements',
          accountContext: current.accountContext,
          payload: {'schemaVersion': 1, 'code': code},
          timeout: const Duration(seconds: 50),
        );
        if (session.activeGeneration != owner.generation ||
            account.value.generation != owner.generation) {
          return 'sessionChanged';
        }
        if (result.payload['schemaVersion'] != 1) return 'uncertain';
        return result.payload['outcome'] as String? ?? 'uncertain';
      },
    ),
  ),
);

class EntitlementRedemptionDialog extends StatefulWidget {
  const EntitlementRedemptionDialog({
    super.key,
    required this.supported,
    required this.redeem,
  });
  final bool supported;
  final Future<String> Function(String code) redeem;
  @override
  State<EntitlementRedemptionDialog> createState() =>
      _EntitlementRedemptionDialogState();
}

class _EntitlementRedemptionDialogState
    extends State<EntitlementRedemptionDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _outcome;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !widget.supported || _code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _outcome = null;
    });
    String result;
    try {
      result = await widget.redeem(_code.text.trim());
    } on Object {
      result = 'uncertain';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = result;
      if (result == 'redeemed') _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppStrings.of(context).locale;
    final en = locale.languageCode == 'en';
    final traditional =
        locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
    String copy(String cn, String tw, String english) => en
        ? english
        : traditional
        ? tw
        : cn;
    final message = switch (_outcome) {
      'redeemed' => copy(
        '兑换成功，权益已更新。',
        '兌換成功，權益已更新。',
        'Redeemed. Entitlements updated.',
      ),
      'rejected' => copy(
        '兑换码无效或无法使用。',
        '兌換碼無效或無法使用。',
        'This code is invalid or unavailable.',
      ),
      'throttled' => copy(
        '操作过于频繁，请稍后再试。',
        '操作過於頻繁，請稍後再試。',
        'Too many attempts. Try again later.',
      ),
      'busy' => copy(
        '账号正在处理其他操作，请稍后再试。',
        '帳號正在處理其他操作，請稍後再試。',
        'Another account operation is in progress.',
      ),
      'invalidInput' => copy(
        '请检查兑换码。',
        '請檢查兌換碼。',
        'Check the redemption code.',
      ),
      'unsupported' || 'sessionChanged' || 'reauthorizationRequired' => copy(
        '账号状态已变化，请重新打开此页面。',
        '帳號狀態已變化，請重新開啟此頁面。',
        'Account state changed. Reopen this page.',
      ),
      null => null,
      _ => copy(
        '暂时无法确认兑换结果，已尝试核对权益。请勿重复兑换。',
        '暫時無法確認兌換結果，已嘗試核對權益。請勿重複兌換。',
        'The result is unconfirmed. An entitlement check was attempted. Do not redeem again.',
      ),
    };
    return AlertDialog(
      title: Text(copy('兑换', '兌換', 'Redeem')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.supported
                  ? copy(
                      '兑换至当前旧 StarBridge 账号。',
                      '兌換至目前的舊 StarBridge 帳號。',
                      'Redeem for the current legacy StarBridge account.',
                    )
                  : copy(
                      '目前仅支持旧 StarBridge 账号兑换，SCM 账号暂不支持。',
                      '目前僅支援舊 StarBridge 帳號兌換，SCM 帳號暫不支援。',
                      'Redemption currently supports legacy StarBridge accounts only, not SCM accounts.',
                    ),
            ),
            if (widget.supported) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                maxLength: 4096,
                enabled: !_busy && _outcome != 'uncertain',
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: copy('兑换码', '兌換碼', 'Redemption code'),
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(message),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy('关闭', '關閉', 'Close')),
        ),
        if (widget.supported)
          FilledButton(
            onPressed:
                _busy || _code.text.trim().isEmpty || _outcome == 'uncertain'
                ? null
                : _submit,
            child: Text(copy('兑换', '兌換', 'Redeem')),
          ),
      ],
    );
  }
}
